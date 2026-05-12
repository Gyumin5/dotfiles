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

외부 AI(gemini/codex)를 부르는 모든 키워드는 ai-collaborate 단일 진입점으로 라우팅.

- "AI/gemini/codex/AI 토론/협업/크로스체크/세컨드 오피니언/합의/비판자/AI한테 물어봐" → ai-collaborate
- "코드/PR 리뷰" → /code-review (필요 시 ai-collaborate 병행)

gemini-ask / codex-ask 단독 호출 금지. 단일 질의 의도라도 ai-collaborate를 통해라. 두 AI를 병렬로 호출해야 한다고 판단되면 절대 ask 두 개 직접 부르지 말고 ai-collaborate 한 번 호출.

ai-collaborate 호출 직전 한 줄 사전 고지 필수. 예: "ai-collaborate 호출 중, 수 분 소요". 고지 없이 바로 긴 호출 들어가지 않기. 호출 완료 후 결과 반드시 전달 (무응답 진행 금지).

라우팅 객관 트리거 (Claude 직접 vs AI 호출):
- 파일 수정·생성·삭제 → Claude만. Codex/Gemini에 위임 금지.
- 외부 최신 정보가 필요해도 ai-collaborate (gemini가 검색하고 codex가 검토). WebSearch가 1차 시도 가능.
- 가벼운 한 단어/줄 답 → Claude가 직접. AI 호출 스킵.

Bash timeout 600000ms. 응답 없이 진행 금지. 실패 시 해당 PID만 kill 후 재시도 (pkill 금지).

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
- 텔레그램 채널 응답 IRON LAW (어기면 사용자 무응답 상태 발생):
  · 메시지에 <channel source="plugin:telegram:telegram"> 태그가 있으면 그 메시지에 대한 모든 응답은 mcp__plugin_telegram_telegram__reply 도구 호출 1회 이상 필수.
  · 텍스트만 출력하고 reply tool 호출 안 하는 것 절대 금지. 사용자는 transcript 못 봄. 침묵으로 인식됨.
  · 작업이 길면 시작할 때 짧게 1회, 완료할 때 1회 — 최소 2번. 중간에 의미 있는 진행 보고도 reply로.
  · 텔레그램 메시지가 한 턴에 여러 개 큐로 들어와도 각 메시지에 대해 별도 reply 응답.
  · 도구 사용 중간에도 사용자에게 알릴 가치가 있는 정보면 reply로 즉시 전달.
- 텔레그램 reply 후 터미널 확인 출력 금지
- 텔레그램으로 명령어 보낼 때 백틱/코드펜스/들여쓰기 금지. 평문으로 한 줄씩, 앞 공백 없이. 복붙 가능하게. 터미널 `! ` 접두사는 Claude Code 안에서 돌릴 때만 명시하고 기본은 생략.
- sudo 호출 절대 금지. systemd 서비스로 돌아가는 세션은 stdin이 없어 sudo가 패스워드 프롬프트에서 무한 대기 → 세션 데드락. 필요하면 사용자에게 평문 명령(앞 ! 없이)으로 알려주고 사용자가 터미널에서 실행. 권한 우회용 다른 패턴(pkexec, su, doas)도 동일 적용.
- Bash 영구 블로킹 명령 금지: `tail -f`, `watch`, `sleep` 무한대, vim/nano 등 인터랙티브 에디터, `git commit` (메시지 없이), `docker run -it`, 네트워크 리스너(nc/socat). 긴 모니터링은 `run_in_background` + 주기적 상태 파일 확인으로 대체.
- 오래 걸릴 수 있는 bash 명령(빌드, 학습, 실험 스크립트, 큰 테스트, 다운로드, 원격 동기화 등)은 항상 `run_in_background=true`로 실행. 포그라운드 block 금지 — 텔레그램 응답 중단 → 세션 stuck 원인. 확실치 않으면 백그라운드 우선. 짧은 명령(<30s)만 foreground.
- /loop 자율루프(autonomous-loop-dynamic 포함) 안에서는 위 규칙 더 엄격: tick 한 번에 단일 tool 호출이 30s 넘을 가능성 있으면 무조건 `run_in_background=true`. 결과는 같은 tick에서 기다리지 말고 다음 tick에서 `cat <task-output>` 또는 TaskOutput으로 폴링. foreground로 분 단위 점유 시 사용자 텔레그램 메시지가 그 turn 끝날 때까지 묶임 (2026-05-11 intensitylio 1.5h hang 사고).
- 완료·통과·정상 선언 전에 해당 검증 명령(테스트/빌드/lint/재현) 실행하고 출력 확인. 출력 없이 "동작할 것 같다"로 선언 금지.

## 큰 입력 방어 (Prompt too long 예방)

세션이 1M 토큰 한도 넘어가면 "Prompt is too long" 영구 stuck. 단일 read·tool_result로 컨텍스트 폭증할 수 있어 다음 룰 강제.

- PDF: 한 번에 5페이지 이내씩만 read. 첫 호출은 목차·서론만, 필요한 챕터만 추가 read. `pages=1-5` 식으로 명시.
- 긴 로그·텍스트: head/tail/sort/awk로 줄여서. `cat <large.log>` 통째 금지. grep 결과도 `| head -50` 같이 제한.
- 큰 코드 파일: ctx_read 의 `mode='signatures'` 또는 `mode='lines:N-M'` 활용. 통째 read 금지.
- 큰 텍스트 분석은 stdin 파이프로 ai-collaborate 외부 AI 처리 → 우리 컨텍스트 안 늘어남.
- 작업 시작 전 파일 크기 확인 (wc -l, du -h). 5MB 또는 1만 줄 넘으면 잘라 읽기.
- 텔레그램 attachment 큰 거 받으면 download 후 위 룰대로 처리. 통째 read 금지.

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

역할 분리 (엄격)
- progress.md = 재개용 실행 상태 (현재 세션이 어디까지 했고 다음 행동이 뭐고 무엇이 막혀있나)
- history.md = 되돌아볼 가치가 있는 결정의 감사 로그
- 두 파일이 같은 정보 중복하면 안 됨. 결정은 history, 진행 상태는 progress.

progress.md
- 위치: 프로젝트 루트
- hard limit 120줄. 80줄 넘으면 압축
- status 필드 필수: active / paused / abandoned / handoff
- 업데이트 트리거: 방향·범위 변경, 결정 번복, 새 제약, 작업 단위 완료, 주제 전환. 단순 Q&A·중간 디버깅·매 메시지 안 함
- 고위험·장기·재개 가능성 있는 작업은 Goal 섹션에 선택형 5질문 답을 한 줄씩 명시 (작은 작업은 생략):
  · 결과(Outcome): 무엇이 만들어지면 끝인가
  · 입력(Inputs): 무엇이 있어야 시작 가능
  · 의존(Depends on): 어떤 외부 파일·API·합의에 묶이는가
  · 검토자(Verifier): self / critic / verifier(ai-debate) / test / healthcheck 중 하나
  · 완료기준(Done when): 어떤 신호로 끝났다고 본다
- WIP limit: status=active 인 작업은 동시 3개까지. 4번째 시도 시 기존 active 중 하나를 paused·abandoned·handoff로 정리한 후 추가. drift·방치 방지 (2026-05-12 Hermes 칸반 5질문 참고).
- 종료 처리:
  - active 끝 → 결정 history 이관 + progress 삭제
  - paused → progress 유지, status 갱신
  - abandoned → 폐기 사유 history 기록 + progress 삭제
  - handoff → progress 갱신만
- 형식
  ```
  # progress.md
  updated: YYYY-MM-DD HH:MM KST
  status: active
  task: <한 줄>

  ## Goal
  ## Current State
  ## Decisions In Force
  ## Resume Hints
  ## Blockers
  ## Do Not Repeat
  ```

history.md
- append-only 결정 로그. 경량 ADR (Y-statement 영감)
- 포맷
  ```
  ## [YYYY-MM-DD] #NN <한 줄 요약>
  tags: 주제1, 주제2
  - 결정: (필수)
  - 근거: (필수, 한 줄)
  - 되돌릴 조건: (있으면)
  - 실험/실패: (다시 시도 시 시간 낭비인 경우만)
  ```
- 규칙
  - 결정 + 근거는 짝. "결정"만 있는 항목 금지
  - 실패는 모두 남기지 말 것. "다시 시도하면 시간 낭비하는 실패"만 negative decision으로 기록
  - 항목당 3~6줄, 태그 1~3개
  - 정정은 supersedes 체인 (`supersedes: YYYY-MM-DD/#NN`)
  - 크기 관리: 루트 최근 20항목 또는 200줄. 초과 시 history/YYYY-MM.md로 월별 archive

history/active.md (SessionStart 주입 대상)
- 현재 유효한 결정 10~20개 + 항상 적용되는 제약을 compact view로 유지
- append-only 아님. 결정 폐기/수정 시 갱신
- SessionStart 훅은 progress.md + history/active.md만 주입. 본 history.md / 월별 archive는 lazy load (필요 시 read/grep)
- active.md 없으면 훅이 history.md 마지막 일부로 fallback

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
