# SETUP.md — 환경 복원 가이드

이 dotfiles 를 새 머신에 clone 한 뒤 운영자(gmoh) 의 Claude Code 멀티세션 환경을
그대로 살리기 위한 절차. 사람이 한 번 읽고 따라 할 수 있도록 작성. 작은 사고들
의 컨텍스트는 history.md / progress.md 참조.

요구 OS: Linux (Ubuntu 20.04+ 기준), systemd user instance 가능해야 함.

---

## 1. 아키텍처 개요

- 9개 Claude Code 세션을 systemd `--user` 서비스로 상시 실행.
  세션 이름: 251229, albert, bias, dotfiles, helipr, intensitylio, new-loc, resume, velocity.
- 각 세션은 `claude` CLI + plugin:telegram MCP 로 자기 텔레그램 봇에 long-poll attach.
  운영자는 외출 중 텔레그램으로 9개 봇 중 원하는 봇에 메시지 → 그 세션이 응답.
- `cs` CLI (`bin/cs`) 가 세션 통제 (list / restart / rotate / status / cl 등).
- 컨트롤봇 (@syve_cnwl_bot, `claude-control-bot.service`) 은 별도 long-poll 프로세스 —
  claude 한도/멈춤 무관하게 cs 제어 가능.
- 자동화 가드 (systemd timer 단위) 다수:
  - `claude-progress-updater` (15분) — 각 세션 progress.md 자동 갱신.
  - `claude-session-healthcheck` (15분) — assistant 60분 hang 시 자동 cs restart (shadow).
  - `claude-api-5xx-watcher` (30초) — API 5xx 감지 시 컨트롤봇 알림.
  - `claude-bun-zombie-cleaner` (60초) — orphan plugin:telegram bun 정리.
  - `claude-rate-limit-recovery` (5분) — 5h/7d 차단 해제 시 알림 + queue flush.
  - `claude-telegram-healthcheck` (1분) — 9개 봇 getUpdates 상태 점검.
  - `claude-weekly-stability-check` (cron 주간) — 7일 운영 자기 점검.
  - `claude-memory-lifecycle` (1주) — memory 파일 만료/정리.
  - `claude-watchdog` (5분) — failed 서비스 자동 복구.
- AI 토론 단일 진입점: `ai-debate` (bin/), POOL = codex + gemini(agy) + claude(격리 HOME).
- daily research: `claude-daily-research` (cron 월/목 05:30 KST) → HN/GitHub 키워드 검색 →
  ai-debate 평가 → 추천 1~5건 텔레그램 전송.

---

## 2. 의존성

### CLI 도구

```
sudo apt install -y jq curl git python3 python3-pip
# claude code CLI: Anthropic 설치 스크립트 — 한 번 깔면 ~/.local/share/claude/versions/* 로 자동 업데이트
curl -fsSL https://claude.ai/install.sh | bash
# bun (plugin:telegram MCP 가 bun 으로 server.ts 실행)
curl -fsSL https://bun.sh/install | bash
# gh (PR/PR 관련 도구)
sudo apt install -y gh
# codex CLI (OpenAI), agy (Antigravity, Google)
npm i -g @openai/codex
# agy 는 antigravity.dev 배포 패키지 (절대경로 /home/gmoh/.local/bin/agy)
```

### Python 패키지

거의 표준 라이브러리만 사용. python3-requests 정도면 충분.

### 텔레그램 봇

세션마다 별도 봇 토큰 필요 (머신별로 세션 수 다름 — `machines/<machine>.list` 참고).
BotFather → 세션 수만큼 봇 + 머신별 컨트롤봇 1개.
- 각 세션 디렉토리에 `.claude/telegram/.env` 만들고 `TELEGRAM_BOT_TOKEN=...` 한 줄. (gitignore, 머신 로컬)
- 컨트롤봇 토큰은 `~/.claude/control-bot/.env` 에 `CONTROL_BOT_TOKEN=` + `ALLOWED_USER_ID=`.
- chat_id 는 운영자 8689118207 고정 (코드 다수 곳에 하드코딩).
- 같은 봇 토큰을 두 머신/세션이 공유하면 inbound 가 한쪽만 수신됨 (getUpdates 단일 소비자). 머신·세션마다 다른 봇 토큰 사용.

---

## 3. Clone + install

```bash
git clone git@github.com:Gyumin5/dotfiles.git ~/dotfiles
cd ~/dotfiles
./install.sh
```

`install.sh` 가 처리하는 것:
- `~/.claude/settings.json` symlink → `dotfiles/claude/settings.json`
- `~/.claude/hooks/` symlink → `dotfiles/claude/hooks/`
- `~/.local/bin/PATH` 추가 + `bin/*` symlink (claude-userbot-* 포함)
- systemd unit 전체 동기화 (`cp -f` 덮어씀, git=source of truth) + `daemon-reload`
- 머신 식별 (아래) 후 `machines/<machine>.list` 의 세션만 `enable --now` (토큰 .env 있는 것만)

설치 전 선행 (머신 식별):
- `echo home > ~/.config/claude-machine-id` (또는 `raion` 등). 이 마커가 어떤 세션을 enable 할지 결정하는 진실원천.
- 마커 없으면 install 이 tailscale 노드명으로 기본값 시도. 그래도 못 정하면 unit 복사만 하고 enable 은 skip.
- 머신 식별로 hostname/`/etc/machine-id` 안 씀 (rename·clone 시 충돌). 마커 파일이 진실원천.

---

## 4. systemd 활성화

세션 enable 은 `install.sh` 가 머신 마커 + `machines/<machine>.list` 로 자동 처리한다
(Restart=always 라 cl 종료해도 자동 부활). 수동으로 하려면:

```bash
# 마커 머신의 매니페스트에 적힌 세션만 (토큰 .env 있는 것만 — ConditionPathExists 2중 가드)
while read -r s; do
  case "$s" in ''|\#*) continue;; esac
  systemctl --user enable --now "claude-$s.service"
done < machines/$(cat ~/.config/claude-machine-id).list
```

- 머신별 세션 목록은 `machines/home.list`, `machines/raion.list` 에 선언. 3대째는 `machines/<name>.list` 추가.
- 각 세션 unit 에 `ConditionPathExists=<wd>/.claude/telegram/.env` — 토큰 없는 머신에선 start 가 실패 아니라 스킵 (같은 봇 2중 inbound 방지).
- 잘못된 머신에서 enable 돼도 토큰 없으면 무해하게 스킵.

가드 / 타이머:

```bash
systemctl --user enable --now claude-progress-updater.timer
systemctl --user enable --now claude-session-healthcheck.timer
systemctl --user enable --now claude-api-5xx-watcher.timer
systemctl --user enable --now claude-bun-zombie-cleaner.timer
systemctl --user enable --now claude-rate-limit-recovery.timer
systemctl --user enable --now claude-telegram-healthcheck.timer
systemctl --user enable --now claude-memory-lifecycle.timer
systemctl --user enable --now claude-bun-ensure.timer
# 컨트롤봇
systemctl --user enable --now claude-control-bot.service
```

---

## 4b. 유저봇 (텔레그램 user-mode) — 크로스세션 주입 + rate-limit 자동재개

내 텔레그램 계정으로 임의 봇 채팅에 메시지를 발사하는 발신기 (Telethon/MTProto).
용도: (a) 어느 세션에든 프롬프트 수동 주입, (b) rate-limit 해제 시 큐 자동 flush.

발신기는 한 머신(home)에만 둔다. 다른 머신(raion)은 ssh 로 home 발신기에 위임.

home 세팅 (1회):
```bash
pip install --user telethon                       # python3.8 호환 1.43.x
mkdir -p ~/.claude/userbot && chmod 700 ~/.claude/userbot
# .env 작성 (채팅 금지, 터미널에서 직접). my.telegram.org 발급 값:
#   API_ID=...
#   API_HASH=...
chmod 600 ~/.claude/userbot/.env
claude-userbot-login                               # 전화+SMS 인증 → userbot.session 생성 (인터랙티브)
# 세션→봇 매핑 (수동 --session 주입용). 봇 @username 은 다음으로 조회 가능:
#   python -c "from telethon.sync import TelegramClient; ..."  또는 targets.json.example 참고
cp ~/.claude/userbot/targets.json.example ~/.claude/userbot/targets.json && nano ~/.claude/userbot/targets.json
```

비-home 머신 (raion) 세팅 — 발신기 없이 home 에 위임:
```bash
# tailscale SSH 로 raion↔home 무인 ssh 먼저 (양쪽): sudo tailscale set --ssh
#   + admin ACL 의 ssh action 을 check → accept (무인 재인증 불가 방지)
printf 'USERBOT_HOST=gmoh@home\n' > ~/.claude/userbot/relay.conf && chmod 600 ~/.claude/userbot/relay.conf
```

동작 / 사용:
- 수동 주입: `claude-userbot-send --session <세션이름> "메시지"` (targets.json 매핑) 또는 `claude-userbot-send @봇 "메시지"`.
- 자동재개: `rate-limit-recovery` 가 해제 감지 시 큐 있는 세션 봇에 `trigger:queue-flush` 발송.
  - home 세션: 로컬 유저봇이 직접 발송.
  - 비-home 세션: `relay.conf` 의 `USERBOT_HOST` 로 home 에 ssh 위임 (그 PC 가 자기 .env 로 봇 @username 해석 → home 유저봇이 발송).
  - trigger 는 대상 세션이 **idle** 일 때만 hook 으로 flush 됨 (rate-limit 걸린 세션은 idle 이라 정상). busy 세션엔 turn-중간 주입돼 hook 미발동 → 다음 사용자 메시지가 flush.
- 자격증명(`.env`, `userbot.session`)·`relay.conf` 는 전부 git 밖, chmod 600, 머신 로컬. 절대 commit/채팅 금지.

---

## 5. 운영 정책 / 안전장치 (요약)

- 세션 service 의 `Restart=always` — 어떤 이유로 죽어도 5초 뒤 자동 부활.
  cs rotate / cs restart 의 stop 단계는 systemctl stop 이라 autorestart 비대상 (안전).
- `rate-limit-guard` (PreToolUse 훅) — 5h ≥ 90% 또는 7d ≥ 99% 면 거의 모든 tool 차단.
  예외: telegram reply/edit/react/download + Bash 첫 명령이 ai-debate/codex-ask/gemini-ask/ai-collaborate/agy.
- `rate-limit-prompt-guard` (UserPromptSubmit 훅) — 차단 중 사용자 prompt 큐잉, 해제 시 flush.
- `prompt-length-guard` — 800K 토큰 이상 차단 (1M 데드락 예방).
- `large-read-guard` — 5MB / 10K 줄 초과 파일 통째 read 차단.
- `secrets-scan-guard` — git commit/push 직전 자격증명 패턴 검사.
- `telegram-reply-enforcer` (Stop 훅) — 텔레그램 메시지 reply tool 미호출 시 차단.
  예외: API 5xx 응답.
- `bun-zombie-cleaner` — cwd-deleted + cgroup inactive 인 plugin:telegram bun 만 SIGTERM.
- `claude-progress-updater` — 자식 claude 띄울 때 `--strict-mcp-config` + 빈 mcp config 강제.
  → 부모 plugin:telegram 충돌 회피.

---

## 6. progress.md / history.md 규칙

역할 분리 엄격:
- `progress.md` = 재개용 실행 상태 (현재 세션이 어디까지 했고 다음 행동이 뭐고 무엇이 막혀있나).
  hard limit 120줄. status 필수: active / paused / abandoned / handoff.
- `history.md` = 결정 로그 (append-only ADR). [DECISION] 마커 commit 시 자동 append.
- `history/active.md` = 현재 유효한 결정 10~20개 compact view. SessionStart 훅이 progress.md +
  active.md 만 주입. 본 history.md / 월별 archive 는 lazy load.

---

## 7. 자주 쓰는 명령

```bash
cs list                     # 9개 세션 상태
cs restart <name>           # 세션 재시작 (jsonl 유지)
cs rotate <name>            # fresh 세션 (jsonl archive)
cs cl <name>                # 인터랙티브 attach (Termius → ssh → cs cl 패턴)
cs status                   # 시스템 전체 상태

ai-debate "topic"           # 외부 AI 합의 토론
gemini-ask "..."            # agy(Antigravity → Gemini 3.5) wrap
codex-ask "..."             # OpenAI codex wrap (단독 사용 금지, ai-debate 경유)

# 가드 임시 우회
touch ~/.claude/state/rate-limit-bypass.flag             # global
touch ~/.claude/state/rate-limit-bypass-<proj>.flag      # 프로젝트별
BYPASS_SECRETS_SCAN=1 git commit ...                     # secrets 스캔 우회
```

---

## 8. 알려진 주의사항

- claude CLI 자식 호출 (`claude config list`, `claude -p ...`) 하면 부모 세션의
  plugin:telegram MCP getUpdates 충돌 → 부모 세션 telegram MCP 끊김. 자동 복구
  불가. cs restart 해야 함. 자식 claude 가 꼭 필요하면 `--strict-mcp-config
  --mcp-config <empty.json>` 강제.
- progress.md 위치는 반드시 현재 systemd unit 의 WorkingDirectory. ~/.claude/projects/
  같은 키 폴더에 mkdir 금지 (av-ros-test-* 찌꺼기 사고 후).
- 시각 표기는 항상 KST (`date '+%Y-%m-%d %H:%M KST'`). UTC 라벨 사고 후.
- gemini-cli 직접 호출 금지 — agy shim 경유. ~/.config/gcloud 잔재가 OAuth invalid_grant
  유발하니 의심 시 mv ~/.config/gcloud ~/.config/gcloud.bak-<date>.
- Telegram MCP plugin disconnect 가 간헐 발생 — 근본 원인 미진단. cs restart 로 복구.
- ai-debate cache 키 32-char (128bit) SHA256. task_preview + task_sha256 진단 저장.
  cross-topic cache hit 의심 시 stderr WARNING 노출.
- 유저봇 자동재개 trigger 는 대상 세션이 idle 일 때만 hook flush. busy 세션은 turn-중간 주입돼
  hook 미발동 (같은 세션에서 자기 자신 테스트하면 항상 busy → flush 안 되는 함정). 검증은 별도 idle 세션으로.
- 텔레그램 inbound 는 봇 채팅당 한 세션만 수신 (getUpdates 단일 소비자). 토큰 공유 금지.

---

## 9. 향후 확장 후보 (현재 보류)

- DeepClaude (Claude Code 모델 백엔드 분리) — 리스크 (외부 API 노출) 커서 거부.
- Moo Tasks (다중 세션 MCP 칸반) — 기능 중복 + Docker/MySQL 부담으로 거부.
- session-limit-watcher — "You've hit your session limit" 즉시 알림. 현재 보류.
- Telegram → slash command 사이드카 — Remote Control 보완 평가 후 결정.

---

## 10. 참고

- progress.md 의 Decisions In Force 섹션 = 항상 적용되는 운영 결정.
- history/active.md = 현재 유효한 결정 10~20개 compact view (SessionStart 주입 대상).
- ~/.claude/CLAUDE.md = 전역 운영 원칙 (응답 규칙, 도구 규칙, 사고 규칙). dotfiles 외부
  파일 — 이쪽도 별도 백업/문서화 필요.
