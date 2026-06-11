# raion 업무 todo 자동화 — RUNBOOK (재구성·운영 절차)

목적: 포맷/재설치/세션 재시작 후에도 이 문서 + install.sh 만으로 todo 자동화를 복원·운영한다.
가드: 이 시스템은 machine-id 마커(~/.config/claude-machine-id = "raion")인 머신에서만 설치/기동한다.

## 경로 계약 (확정 — 2026-06-11)
- 코드 source of truth: dotfiles repo `raion/todo-sync/` (home 이 commit/push, raion 은 pull-only).
- 런타임 데이터 경로: `~/raion/todo-sync` (확정 — ~/.local/share/todo 미채택, 기존 운영 데이터 무이동).
  install.sh 가 repo 코드를 이 경로로 복사 배포(cp -f). 데이터·비밀은 절대 안 덮어씀.
- 데이터·비밀(전부 repo 제외, gitignore): todo.db(+wal/shm), todo.md, last_check.txt, state.json,
  token_cache.json, bot.token, bot.chat_id, bot/snooze.json, webui/.token, config.json(실파일).
- config.json: repo 엔 `config.json.example`(client/tenant placeholder + tags 통제어휘)만.
  실파일은 raion 로컬 — install.sh 는 없을 때만 example 로 생성(이후 절대 안 덮어씀).
- systemd 유닛(todobot-digest.service/.timer, todobot-listener.service): repo `systemd/user/`.
  %h 경로 + `ConditionPathExists=%h/raion/todo-sync/bot.token` (타 머신 오기동 방어).
  install.sh 가 MACHINE_ID=raion 일 때만 ~/.config/systemd/user 에 복사·enable. home 엔 유닛 미배포.

## raion 후속 절차 (dotfiles 편입 전환, 1회 — 사람 확인하에)
1. `cd ~/dotfiles && git pull --ff-only`
2. `bash install.sh` — todobot 유닛 %h 버전 재배치 + daemon-reload, repo 코드 → ~/raion/todo-sync 덮어씀.
   기존 bot.token/bot.chat_id/todo.db/config.json 은 그대로 연결됨(데이터 무이동).
3. `systemctl --user restart todobot-listener.service` (새 유닛 정의 반영), `systemctl --user list-timers | grep todobot` 확인.
4. 검증: 텔레그램 TODOBot "목록" 응답, `python3 ~/raion/todo-sync/todoctl.py list` 정상.
5. 구경로 잔재 없음(데이터 경로 동일) — 별도 정리 불필요. 구 유닛 정의는 2의 덮어쓰기로 대체됨.

## 구성요소
- 진실원본: SQLite `todo.db` (WAL). 단일 writer = `todoctl.py`. 직접 편집 금지.
- 사람이 읽는 뷰: `todo.md` (todoctl 변경 시 자동 export).
- 자동정리: 살아있는 Claude(이 텔레그램 세션)의 CronCreate 2개.
  - 증분: cron `4,14,24,34,44,54 * * * *` (10분 주기), prompt = `prompts/incremental.txt`
  - 브리핑: cron `1 9 * * 1-5` (평일 09:00), prompt = `prompts/briefing.txt`
  - chat_id 8689118207.
- guardian: cron `30 6 * * *` (매일) — 위 2개+자기자신을 멱등 재생성해 7일 만료 시계 갱신 + `state.json` 갱신. prompt = `prompts/guardian.txt`
- 메일·Teams 읽기: 현재 claude.ai Microsoft365 MCP(읽기전용, 이 세션 인증)로만 가능.
- 상태계약: `state.json` (session_heartbeat/last_cron_rearm/last_incremental_run/last_briefing_run/last_m365_success/auth_required).
- watchdog: 검토 후 미채택(2026-06-05). dead-man's-switch(healthchecks.io류)가 최적안이었으나 회사 PC의 외부 SaaS 핑 정책·자격증명 부담 대비 효용이 낮아 생략. 견고성은 systemd 자동재시작 + guardian 일일 재무장으로 확보. 필요 시 재검토(설계는 history 참고).

## 제약 (왜 이렇게 설계했나)
- CronCreate는 세션 전용·인메모리·7일 만료. 세션 죽으면 사라짐 → guardian로 매일 갱신(생존 중). 세션 死 후엔 systemd가 서비스 자동재시작 + 브리핑이 며칠 끊기면 사람이 "todo 스케줄 켜줘"로 재무장(watchdog 미채택).
- 메일/Teams 읽기는 인터랙티브 세션 MCP에 묶임. 헤드리스/순수 스크립트 불가. 완전 무인은 MS Graph 위임권한(관리자 동의) 필요 → 대기 중.
- 자식 claude 세션 생성 금지(텔레그램 long-poll 충돌).
- Claude가 SessionStart 훅+settings.json 자가설치하는 지속장치는 안전분류기 차단 → 기본 미사용.

## 포맷 후 재구성 절차
1. (마커) `echo raion > ~/.config/claude-machine-id` → dotfiles 설치 `bash install.sh` (raion 가드가 todo 자산·의존성·DB init 설치).
2. 이 텔레그램 세션에서 "todo 스케줄 켜줘" 라고 말한다 → Claude가 CronList 확인 후 증분/브리핑/guardian cron 등록.
3. Microsoft365 MCP 재인증(/mcp). 안 되면 메일·Teams 자동수집만 멈추고, 수동 todo는 계속 동작.
4. 확인: 텔레그램 "목록" → 정상 응답. state.json heartbeat 갱신 확인.

## cron 재무장 절차 (세션 내, 멱등)
- CronList로 기존 확인 → 중복이면 그대로, 없거나 만료임박이면 prompts/*.txt 내용으로 CronCreate(recurring=true, durable=true) 재등록.
- 재등록 후 state.json의 last_cron_rearm/cron_next_expiry 갱신.

## Graph 승인 후 목표(완전 무인)
- 별도 systemd --user 서비스가 Graph 토큰(auth.py)으로 메일·Teams 직접 읽어 todoctl 호출.
- CronCreate·인터랙티브 MCP 의존 제거. (이때 헬스 경보가 필요하면 watchdog 재검토.)

## 안전/보안
- token_cache.json(런타임 생성)·todo.db·last_check.txt·state.json 은 repo에 넣지 않음(런타임/비밀).
- config.json의 client/tenant ID는 식별자(비밀 아님)지만 실파일은 repo 제외 — repo 엔 .example 템플릿만(2026-06-11).
- 토큰류는 권한 600, ~/raion/todo-sync(700) 내 보관.

## 사용자 승인 기록
- 2026-06-05 텔레그램(chat_id 8689118207): 사용자가 "자동으로 다 되게, 충분히 기록해서 알아서 처리"를 명시 승인. Claude 자가 SessionStart 훅은 제외(분류기 정책). watchdog는 사용자 결정으로 미채택("와치독 없이 진행").
