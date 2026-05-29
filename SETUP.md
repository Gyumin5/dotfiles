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

9개 세션마다 별도 봇 토큰 필요. BotFather → 새 봇 9개 + 컨트롤봇 1개.
- 각 세션 디렉토리에 `.claude/telegram/.env` 만들고 `TELEGRAM_BOT_TOKEN=...` 한 줄.
- 컨트롤봇 토큰은 `~/.claude/control-bot/.env` 에 같은 형식.
- chat_id 는 운영자 8689118207 고정 (코드 다수 곳에 하드코딩).

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
- `~/.local/bin/PATH` 추가 + `bin/*` symlink

별도 수동 단계 (install.sh 가 아직 안 함):
- systemd unit 복사: `cp dotfiles/systemd/user/*.service dotfiles/systemd/user/*.timer ~/.config/systemd/user/`
- `systemctl --user daemon-reload`
- 필요한 타이머 활성화 (아래 4번).

---

## 4. systemd 활성화

운영자 9개 세션 (Restart=always 로 두면 cl 종료해도 자동 부활):

```bash
for s in 251229 albert bias dotfiles helipr intensitylio new-loc resume velocity; do
    systemctl --user enable --now claude-$s.service
done
```

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
