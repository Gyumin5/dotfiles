# Global Instructions

## 응답 원칙

- 한국어 우선. 한자(漢字) 사용 금지.
- 설명은 짧고 정확하게. 불확실하면 "확실하지 않다"고 명시.
- 먼저 관련 파일과 진입점만 좁혀서 읽기. 불필요한 대규모 스캔 금지.
- 변경은 작게, 검증은 자주.
- 글 작성 시 `**굵게**` (별표 두 개 감싸기) 사용 금지. 강조는 대문자, 따옴표, 줄바꿈으로.

## 프로젝트 지식 자동 기록

사용자가 프로젝트 지시(빌드, 코드 스타일, 금지 사항, 워크플로우)를 하면 프로젝트 CLAUDE.md에 기록.

- CLAUDE.md 없으면 생성 여부를 물어볼 것
- 기록 후 "CLAUDE.md에 기록했습니다" 한 줄만 출력
- 일회성 지시는 기록하지 않음

## AI 협업 규칙 (최우선)

**"AI", "gemini", "codex" 키워드가 있으면 다른 모든 skill보다 우선.**

| 요청                                 | 동작                 |
| ------------------------------------ | -------------------- |
| "gemini로/한테"                      | gemini-ask skill     |
| "codex로/한테"                       | codex-ask skill      |
| "AI 협업/크로스체크/세컨드 오피니언" | ai-collaborate skill |
| "코드 리뷰/PR 리뷰"                  | /code-review         |

**필수 규칙:**

- Bash timeout 600000ms (10분)
- AI 협업 시 gemini-ask + codex-ask **둘 다** 호출. 한쪽만 호출 금지.
- 모든 AI 응답을 반드시 수신. 응답 없이 진행 금지.
- 실패 시 해당 PID만 kill 후 재시도 (pkill 금지). 무한 재시도.

## 복잡도 판단 및 안내

요청을 받으면 먼저 복잡도를 판단하라. 아래에 해당하면 바로 실행하지 말고 안내 + 복사 가능한 프롬프트를 제공:

- **판단력 필요** (복잡한 버그, 설계 결정, 논문 분석 등) → `think`를 앞에 붙인 전체 프롬프트를 만들어서 제공
- **작업량 많음** (대규모 리팩토링, 여러 파일 동시 수정, 새 기능 전체 구현) → `/effort high` 전환을 안내한 뒤 프롬프트 제공
- **둘 다** → `/effort high` 전환 안내 + `think` 포함 프롬프트 제공

프롬프트는 사용자가 그대로 복사해서 입력할 수 있는 완성형으로 작성. 단순 작업은 안내 없이 바로 실행.

## 도구 규칙

- HTML 열기: `xdg-open` 대신 `google-chrome`
- 파일 탐색: 사용자가 경로를 지정하지 않으면 현재 프로젝트 내에서만 검색
- 텔레그램 reply 후 터미널에 확인 메시지 출력하지 않음

## Memory 관리

### 저장 기준

- "다음 대화에서도 쓸 가치가 있는가?"로 판단
- 우선순위: 사용자 규칙 > 프로젝트 결정 > 피드백 > 참조
- 저장 금지: 일회성 Q&A, 코드에서 읽을 수 있는 것, 임시 상태

### 파일 규칙

- 주제별 관리. 파일명 prefix: `user_`, `feedback_`, `project_`, `reference_`
- 누적보다 덮어쓰기. 현재 유효한 상태만 유지
- MEMORY.md는 인덱스만 (파일당 1줄, 150자 이내)
- AI 호출 시 관련 memory 자동 첨부

## 세션 유지

- **"새 세션을 열라" 제안 금지.** 같은 세션에서 계속 작업.
- 압축 후 `progress.md`를 먼저 읽고 이어서 진행.

## progress.md

작업 요청 시 생성, 단위 완료 시 업데이트, "완료" 시 삭제. 항상 덮어쓰기.

## history.md

프로젝트 루트에 완료 작업 누적 기록. 형식: `- [YYYY-MM-DD] 내용`

## 압축 전 저장

사용자가 "압축할 거니 저장해" 또는 유사 표현을 하면:
1. progress.md — 현재 진행 중인 작업 상태 저장 (덮어쓰기)
2. history.md — 이번 세션에서 완료한 작업 추가 (누적)

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
