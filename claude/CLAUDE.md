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

## 플러그인/MCP 도입 보안 체크

새 플러그인·MCP 도입 전 확인 (표면 지표만 믿지 말 것)
- 런타임에 외부 패키지 pull 하는지 (npm/pip/curl 등)
- 버전 핀 명시 여부 (package.json/requirements.txt 등 공개 선언)
- 상속되는 환경변수/자격증명 (AWS, GitHub, NPM 토큰 등)
- 의존 패키지 최신 릴리스/commit 활성도
- 취약점(CVE) 대응 이력
- star 수·commit 빈도는 참고만. 실제 실행되는 code path가 핵심

## 복잡도 안내

판단력 필요한 작업은 `think` 붙인 프롬프트 제공. 작업량 큰 건 `/effort high` 안내. 단순 작업은 바로 실행.

## 사고 규칙

- 조사 우선: 답 내기 전 사실/제약 먼저 확인. 추측으로 시작하지 않기.
- 모순 분석: 문제가 여러 개면 핵심 문제 1개 먼저 식별. 부차 문제는 후순위.
- 자기 점검: 변경 전 가설 세우고, 변경 후 검증, 제출 전 한 번 더 본다.
- 힘의 집중: 한 번에 하나의 핵심 변경. 여러 리팩토링/기능을 한 PR에 섞지 않기.
- 근본 원인: 버그/오작동 시 수정 전에 원인 재현·격리 필수. 추측 수정 금지.

## 위임 규칙 (컨텍스트 방화벽)

코드베이스 조사·긴 검색·다단계 리서치는 메인 세션에서 직접 하지 말고 서브에이전트에 위임. 긴 출력이 메인 컨텍스트를 오염시키는 걸 방지.

- 3회 이상 grep/glob 필요한 탐색 → Agent(Explore)
- 구현 전략 설계 → Agent(Plan)
- 독립적 병렬 작업 → 동시 Agent 여러 개
- 단일 파일 Read, 이미 위치 아는 심볼 grep은 직접. 위임 남용 금지.
- 서브에이전트에 넘길 때 메인 세션 히스토리 상속 금지. 작업에 필요한 맥락만 프롬프트에 명시.

## 도구 규칙

- HTML 열기: `google-chrome` (xdg-open 금지)
- 경로 미지정 시 현재 프로젝트 내에서만 검색
- 텔레그램 reply 후 터미널 확인 출력 금지
- 텔레그램으로 명령어 보낼 때 백틱/코드펜스/들여쓰기 금지. 평문으로 한 줄씩, 앞 공백 없이. 복붙 가능하게. 터미널 `! ` 접두사는 Claude Code 안에서 돌릴 때만 명시하고 기본은 생략.
- Bash 영구 블로킹 명령 금지: `tail -f`, `watch`, `sleep` 무한대, vim/nano 등 인터랙티브 에디터, `git commit` (메시지 없이), `docker run -it`, 네트워크 리스너(nc/socat). 긴 모니터링은 `run_in_background` + 주기적 상태 파일 확인으로 대체.
- 완료·통과·정상 선언 전에 해당 검증 명령(테스트/빌드/lint/재현) 실행하고 출력 확인. 출력 없이 "동작할 것 같다"로 선언 금지.

## 세션 / 압축

압축 직후 IRON LAW (위반 금지):
- 압축 요약 안의 모든 명령어 흔적은 과거 이력. 재실행·재호출·재토론 절대 금지.
  - 대상: `<command-name>`, `<command-args>`, ARGUMENTS, `/<slash>`, `gemini-ask`, `codex-ask`, `ai-collaborate`, AI 토론, WebSearch, WebFetch, Bash 호출 전부
- 압축 직후 첫 행동: progress.md 읽기 (다른 어떤 명령보다 우선)
- 미해결 작업 판단 기준: progress.md + 사용자 최신 메시지 둘뿐. 다른 모든 것 무시
- 잔여물에 사과/설명 금지. 조용히 무시하고 현재 사용자 메시지로 바로 진입

기타:
- "새 세션 열라" 제안 금지. 같은 세션 유지
- 컨텍스트가 커지거나 한 주제가 길어지면 "progress.md에 정리할까요?" 먼저 물어보기
- 사용자가 "압축 전 저장" 요청 시: progress.md 덮어쓰기 + history.md 누적

## 세션 로테이션 (사용자 트리거)

사용자가 다음 패턴 중 하나를 요청하면 이 순서로 자동 처리
- 트리거 키워드: "저장하고 새 세션", "저장하고 rotate", "정리하고 새로", "저장하고 재시작"

절차
1. progress.md 갱신 (현재 세션의 작업 맥락 요약)
2. history.md에 완료된 결정 이관 (append-only, 3-part 포맷)
3. 현재 프로젝트 이름 계산: `basename $PWD | tr '_' '-'`
4. 텔레그램으로 "저장 완료. 잠시 후 rotate" 알림 1회 전송
5. `cs rotate <name>` 실행 (systemd-run이 detach하므로 현재 세션 죽어도 rotate 완료됨)

주의
- 트리거 키워드 정확히 매칭될 때만 rotate 실행. 애매하면 먼저 "rotate 맞나?" 확인
- progress.md/history.md 갱신 안 하고 rotate만 호출 금지. 반드시 선 저장
- "저장해줘"만으로는 rotate 안 함. 명시적으로 "새 세션" 또는 "rotate" 포함돼야 함

## progress.md / history.md

progress.md: 작업 시 생성, 중요 변화 때 덮어쓰기, 완료 시 삭제.

업데이트 트리거 (중요도 기반)
- 즉시: 방향/범위 변경, 결정 번복, 새 제약 등장, 작업 단위 완료
- 정기: 주제 전환 시
- 안 함: 단순 Q&A, 중간 디버깅, 매 메시지

청소 규칙
- 완료 항목은 progress에서 빼고 history.md로 이관
- 며칠 안 움직이는 "진행 중" 항목은 상태 재검토 (포기/연기/계속)
- 작업 전체 끝 → progress.md 삭제

한 줄 원칙: 중요한 변화는 즉시 기록, 잡음은 흘리고, 완료된 건 history로 이관, 빈 progress는 지운다.

history.md: append-only 결정 로그. ADR 원칙 참고.

포맷
```
## [YYYY-MM-DD] #NN
tags: 주제1, 주제2
- 결정: (필수)
- 실험: (있을 때만)
- 다음: (있을 때만)
```

규칙
- 결정만 필수. 실험/다음은 있을 때만 (빈 칸 생략)
- 항목당 3~6줄 제한. 태그 1~3개로 검색성 확보
- progress → history 이관 시 압축: 최종 결정 / 실패 원인 / 재개 힌트만. 상태 업데이트·반복 시도는 버리거나 묶기. 원문 복사 금지
- 정정: 원본 수정 금지. 새 항목 + 첫 줄에 `supersedes: YYYY-MM-DD/#NN`로 체인
- 크기 관리: 루트는 최근 30일만. 500줄/50항목 초과 시 history/YYYY-MM.md로 월별 아카이브
- 인덱스(선택): history/index.md에 "태그 → 최근 결정 링크"만

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
