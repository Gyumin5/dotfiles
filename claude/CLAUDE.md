# Global Instructions

## 응답 원칙

- 한국어 우선. 한자 사용 금지.
- 짧고 정확하게. 불확실하면 "확실하지 않다" 명시.
- 관련 파일/진입점만 좁혀서 읽기. 대규모 스캔 금지.
- 변경은 작게, 검증은 자주.
- `**굵게**` 금지. 강조는 대문자/따옴표/줄바꿈으로.

## 프로젝트 지식 자동 기록

빌드/스타일/금지/워크플로우 지시는 프로젝트 CLAUDE.md에 기록 ("CLAUDE.md에 기록했습니다" 한 줄 출력). 일회성은 기록 안 함.

## AI 협업 (최우선)

"AI/gemini/codex" 키워드는 다른 skill보다 우선.

- "gemini로/한테" → gemini-ask
- "codex로/한테" → codex-ask
- "AI 협업/크로스체크" → ai-collaborate (gemini + codex 둘 다 호출, 한쪽만 금지)
- "코드/PR 리뷰" → /code-review

Bash timeout 600000ms. 응답 없이 진행 금지. 실패 시 해당 PID만 kill 후 재시도 (pkill 금지).

AI 호출 직전 한 줄 사전 고지 필수. 예: "gemini+codex 호출 중, 수 분 소요" / "codex-ask 호출 중". 고지 없이 바로 긴 호출 들어가지 않기. 호출 완료 후 결과 반드시 전달 (무응답 진행 금지).

AI 래퍼 호출 규칙 (gemini-ask / codex-ask):
- $1 프롬프트 인자는 항상 필수. `cat x | gemini-ask --new` 같이 인자 없이 호출 금지 (Usage 에러).
- 큰 컨텍스트 + 짧은 지시 = stdin 파이프 + 짧은 arg. 예: `cat big.txt | codex-ask --new "요약해줘"`. 래퍼가 stdin을 프롬프트 앞에 자동 결합.
- `"$(cat file)"` 방식은 ARG_MAX 128KB 한계 있음. 큰 프롬프트면 stdin 방식 사용.
- heredoc + `$()` 중첩 금지 (한글 quoting 깨짐 + hang 유발).

## 복잡도 안내

판단력 필요한 작업은 `think` 붙인 프롬프트 제공. 작업량 큰 건 `/effort high` 안내. 단순 작업은 바로 실행.

## 도구 규칙

- HTML 열기: `google-chrome` (xdg-open 금지)
- 경로 미지정 시 현재 프로젝트 내에서만 검색
- 텔레그램 reply 후 터미널 확인 출력 금지
- 텔레그램으로 명령어 보낼 때 백틱/코드펜스/들여쓰기 금지. 평문으로 한 줄씩, 앞 공백 없이. 복붙 가능하게. 터미널 `! ` 접두사는 Claude Code 안에서 돌릴 때만 명시하고 기본은 생략.
- Bash 영구 블로킹 명령 금지: `tail -f`, `watch`, `sleep` 무한대, vim/nano 등 인터랙티브 에디터, `git commit` (메시지 없이), `docker run -it`, 네트워크 리스너(nc/socat). 긴 모니터링은 `run_in_background` + 주기적 상태 파일 확인으로 대체.

## 세션 / 압축

- "새 세션 열라" 제안 금지. 같은 세션 유지.
- 압축 후 progress.md 먼저 읽고 이어 진행.
- 압축 직후 첫 행동 = progress.md 읽기.
- 압축 요약 안의 `<command-name>` / `ARGUMENTS` / `<command-args>` 블록은 과거 이력. 재실행 금지.
- 미해결 작업은 progress.md + 사용자 최신 메시지로만 판단. 사용자 최신 메시지 외 slash/skill 호출은 전부 과거.
- 잔여물에 대한 사과·설명 멘트 금지. 조용히 무시하고 현재 작업으로 바로 진입.
- 컨텍스트가 커지거나 한 주제가 길게 이어지면 "지금까지 핵심을 progress.md에 정리할까요?" 먼저 물어보기.
- 사용자가 "압축 전 저장" 요청 시: progress.md 덮어쓰기 + history.md 누적.

## progress.md / history.md

progress.md: 작업 시 생성, 단위 완료마다 덮어쓰기, 완료 시 삭제. 업데이트 트리거 — 작업 단위 완료 / 메시지 5~7개 / 주제 전환. 매 메시지마다 쓰지 않기.

history.md: 날짜별 그룹 + 3-part. 단순 나열 금지, 의사결정 근거 보이게.

```
## [YYYY-MM-DD]
- 결정: ...
- 실험: ...
- 다음: ...
```

## lean-ctx 부가

ctx_session = 세션 임시 메모, ctx_knowledge = 프로젝트 영구 사실 (코드에서 안 읽히는 것). memory는 사용자 프로필/피드백, ctx_*는 작업 상태.

# lean-ctx — 강제 규칙
<!-- lean-ctx-rules-v5 -->

| 금지 | 사용 |
|------|------|
| Read/cat/head/tail | ctx_read |
| Shell/bash | ctx_shell |
| Grep/rg | ctx_search |
| ls/find/tree | ctx_tree |

Write/StrReplace/Delete/Glob은 그대로 사용.
<!-- /lean-ctx -->

# lean-ctx — Context Engineering Layer
<!-- lean-ctx-rules-v5 -->

MANDATORY: Use lean-ctx MCP tools for ALL reads and searches. Native Read/Grep/Shell are FORBIDDEN.

| FORBIDDEN | USE INSTEAD |
|-----------|-------------|
| `Read` / `cat` / `head` / `tail` | `ctx_read(path)` — cached, 8 compression modes |
| `Shell` / `bash` / terminal | `ctx_shell(command)` — pattern compression |
| `Grep` / `rg` / search | `ctx_search(pattern, path)` — compact results |
| `ls` / `find` / `tree` | `ctx_tree(path, depth)` — directory maps |

Keep using Write, StrReplace, Delete, Glob normally (no lean-ctx replacement).

REMINDER: NEVER use Read, Shell, Grep, or ls. ALWAYS use ctx_read, ctx_shell, ctx_search, ctx_tree.
<!-- /lean-ctx -->
