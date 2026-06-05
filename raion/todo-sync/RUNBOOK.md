# raion 업무 todo 자동화 — RUNBOOK (재구성·운영 절차)

목적: 포맷/재설치/세션 재시작 후에도 이 문서 + install.sh 만으로 todo 자동화를 복원·운영한다.
가드: 이 시스템은 Tailscale 노드명이 "raion"인 머신에서만 동작/설치한다.

## 구성요소
- 진실원본: SQLite `todo.db` (WAL). 단일 writer = `todoctl.py`. 직접 편집 금지.
- 사람이 읽는 뷰: `todo.md` (todoctl 변경 시 자동 export).
- 자동정리: 살아있는 Claude(이 텔레그램 세션)의 CronCreate 2개.
  - 증분: cron `8 * * * *` (24/7 매시간), prompt = `prompts/incremental.txt`
  - 브리핑: cron `1 9 * * 1-5` (평일 09:00), prompt = `prompts/briefing.txt`
  - chat_id 8689118207.
- guardian: cron `30 6 * * *` (매일) — 위 2개+자기자신을 멱등 재생성해 7일 만료 시계 갱신 + `state.json` 갱신. prompt = `prompts/guardian.txt`
- 메일·Teams 읽기: 현재 claude.ai Microsoft365 MCP(읽기전용, 이 세션 인증)로만 가능.
- 상태계약: `state.json` (session_heartbeat/last_cron_rearm/last_incremental_run/last_briefing_run/last_m365_success/auth_required).
- watchdog(예정, systemd --user 타이머): M365 안 읽음. state.json 만 보고 stale(heartbeat 끊김/브리핑 안 옴/만료 임박/auth_required) 시 텔레그램 경보. = 침묵 실패 방지.

## 제약 (왜 이렇게 설계했나)
- CronCreate는 세션 전용·인메모리·7일 만료. 세션 죽으면 사라짐 → guardian로 매일 갱신(생존 중), 죽으면 watchdog 경보로 사람이 재가동.
- 메일/Teams 읽기는 인터랙티브 세션 MCP에 묶임. 헤드리스/순수 스크립트 불가. 완전 무인은 MS Graph 위임권한(관리자 동의) 필요 → 대기 중.
- 자식 claude 세션 생성 금지(텔레그램 long-poll 충돌).
- Claude가 SessionStart 훅+settings.json 자가설치하는 지속장치는 안전분류기 차단 → 기본 미사용.

## 포맷 후 재구성 절차
1. dotfiles 설치: `bash install.sh` (raion 가드가 자동으로 todo 자산·의존성·DB init·watchdog 설치).
2. 이 텔레그램 세션에서 "todo 스케줄 켜줘" 라고 말한다 → Claude가 CronList 확인 후 증분/브리핑/guardian cron 등록.
3. Microsoft365 MCP 재인증(/mcp). 안 되면 메일·Teams 자동수집만 멈추고, 수동 todo는 계속 동작.
4. 확인: 텔레그램 "목록" → 정상 응답. state.json heartbeat 갱신 확인.

## cron 재무장 절차 (세션 내, 멱등)
- CronList로 기존 확인 → 중복이면 그대로, 없거나 만료임박이면 prompts/*.txt 내용으로 CronCreate(recurring=true, durable=true) 재등록.
- 재등록 후 state.json의 last_cron_rearm/cron_next_expiry 갱신.

## Graph 승인 후 목표(완전 무인)
- 별도 systemd --user 서비스가 Graph 토큰(auth.py)으로 메일·Teams 직접 읽어 todoctl 호출.
- CronCreate·인터랙티브 MCP 의존 제거. watchdog는 그대로 헬스 경보.

## 안전/보안
- token_cache.json(런타임 생성)·todo.db·last_check.txt·state.json 은 repo에 넣지 않음(런타임/비밀).
- config.json의 client/tenant ID는 식별자(비밀 아님).
- 토큰류는 권한 600, ~/raion/todo-sync(700) 내 보관.

## 사용자 승인 기록
- 2026-06-05 텔레그램(chat_id 8689118207): 사용자가 "자동으로 다 되게, 충분히 기록해서 알아서 처리"를 명시 승인. 단 Claude 자가 SessionStart 훅은 기본 제외(분류기 정책), watchdog는 install.sh(사람 실행) 경유 설치.
