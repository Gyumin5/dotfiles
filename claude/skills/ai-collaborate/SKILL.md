---
name: ai-collaborate
description: Gemini + Codex 병렬 협업. "AI 협업해줘", "크로스체크해줘", "세컨드 오피니언", "다른 AI한테 물어봐", "AI한테 리뷰" 등의 요청 시 자동 호출.
disable-model-invocation: false
---

# AI 병렬 협업 모드

사용자가 "다른 AI한테 물어봐", "AI 협업해줘", "크로스체크해줘", "세컨드 오피니언", "AI한테 리뷰해달라고 해" 등을 요청하면 이 skill을 따른다.

**중요: gemini-ask, codex-ask skill을 호출하지 말 것. Bash tool로 직접 실행한다.**

## Memory 주입 (모든 호출에 적용)

**모든 AI 호출 시 프로젝트 memory를 프롬프트 앞에 첨부한다.**

1. `~/.claude/projects/` 하위의 현재 프로젝트 memory 디렉토리에서 모든 `.md` 파일을 읽는다 (MEMORY.md 제외)
2. 내용을 `[Project Memory]` 블록으로 묶어서 프롬프트 앞에 첨부
3. memory가 없으면 생략

```bash
# memory 수집 예시
MEMORY_DIR="$HOME/.claude/projects/-home-gmoh-$(basename $(pwd))/memory"
MEMORY_CONTENT=""
if [ -d "$MEMORY_DIR" ]; then
  for f in "$MEMORY_DIR"/*.md; do
    [ "$(basename "$f")" = "MEMORY.md" ] && continue
    MEMORY_CONTENT+="$(cat "$f")\n---\n"
  done
fi
```

프롬프트 구성:

```
[Project Memory]
{memory 내용}

[질문]
{실제 질문}
```

## 모드 구분

### 1. 단순 협업 (기본)

**트리거:** "AI 협업해줘", "크로스체크해줘", "세컨드 오피니언" 등

1. `gemini-ask --new`와 `codex-ask --new`를 **병렬 Bash tool call로 동시 실행** (foreground, timeout: 600000)
2. 응답을 기다리는 동안 **Claude가 자신의 의견을 정리**한다
3. Gemini/Codex 응답이 도착하면 3자 의견을 비교하고, **Claude가 종합 판단을 내린다**:
   - 합의점: 3자가 동의하는 부분
   - 쟁점: 의견이 갈리는 부분 + Claude의 최종 판단과 근거
   - 결론: Claude가 추천하는 방향

### 2. 멀티라운드 토론

**트리거:** "AI 토론해줘", "깊게 논의해줘", "합의할때까지", "토론", "여러 라운드", "반복 토론" 등

#### 라운드 1: 독립 의견 수집

1. `gemini-ask --new "[memory] + 질문"` — 병렬 foreground
2. `codex-ask --new "[memory] + 질문"` — 병렬 foreground
3. Claude도 자기 의견 정리
4. 3자 응답 수집 후 쟁점 파악

#### 라운드 2~N: 교차 토론

1. 이전 라운드의 다른 AI 의견을 각 AI에게 전달 (세션 이어가기):

   ```bash
   # --new 없이 호출 → 이전 세션 이어감
   gemini-ask "다른 AI들의 의견입니다:
   [Codex 의견] ...
   [Claude 의견] ...
   동의하는 부분과 반박할 부분을 구분해서 답변해줘." 2>&1

   codex-ask "다른 AI들의 의견입니다:
   [Gemini 의견] ...
   [Claude 의견] ...
   동의하는 부분과 반박할 부분을 구분해서 답변해줘." 2>&1
   ```

2. Claude도 다른 AI 의견에 대한 반박/동의 정리
3. 합의/쟁점 재분석

#### 종료 조건

- 3자 의견이 실질적으로 합의에 도달
- 또는 최대 3라운드 도달 (사용자가 "계속"이라고 하면 추가 라운드 가능)
- 종료 시 최종 종합 보고서 작성

#### 실패 처리

- AI 응답이 안 오는 경우 (timeout):
  - 10초 대기 후 1회 재시도
  - 재시도도 실패 시 해당 AI 없이 진행, 사용자에게 알림
  - "Gemini 응답 실패. Claude + Codex 2자로 진행합니다."

### 3. 코드 리뷰 요청

"AI한테 코드 리뷰해달라고 해", "AI한테 리뷰 받아봐" 등의 경우:

1. `/code-review` 실행 (Claude 자체 멀티에이전트 리뷰)
2. 동시에 해당 코드를 `gemini-ask`와 `codex-ask`에 pipe로 전달하여 리뷰 요청
3. 3자 리뷰 결과를 통합:
   - 공통으로 지적한 문제 (높은 신뢰도)
   - 한쪽만 지적한 문제 (검토 필요)
   - 개선 제안 종합
4. 필요시 코드 수정안 제시

## 파일 작업 규칙

**Gemini/Codex는 의견만 제공한다. 파일 수정, 생성, 삭제는 반드시 Claude만 수행한다.**
codex-ask에 `--full-auto` 등 파일 수정 옵션을 절대 사용하지 마라.

## Claude의 역할 (핵심)

Claude는 **단순 정리자가 아니라 적극적 참여자**다:

- Gemini/Codex 응답을 기다리기 전에 **자기 의견을 먼저 형성**
- 다른 AI의 의견에 **동의/반박 근거를 구체적으로** 제시
- 의견이 갈릴 때 **최종 추천안과 그 이유**를 명확히 제시
- 다른 AI가 틀렸다고 판단되면 솔직하게 지적

## 사용 패턴

```bash
# 단순 협업 — 두 Bash tool을 병렬로 동시 호출 (run_in_background 사용 금지)
gemini-ask --new "[memory]\n질문 내용" 2>&1   # Bash tool call 1 (timeout: 600000)
codex-ask --new "[memory]\n질문 내용" 2>&1    # Bash tool call 2 (timeout: 600000)
# → 두 결과가 모두 도착한 후 종합

# 멀티라운드 토론도 동일하게 병렬 foreground
gemini-ask "상대 의견: ... 반박해줘" 2>&1     # Bash tool call 1 (timeout: 600000)
codex-ask "상대 의견: ... 반박해줘" 2>&1      # Bash tool call 2 (timeout: 600000)

# 코드 리뷰
cat file.cpp | gemini-ask --new "[memory]\n이 코드를 리뷰해줘" 2>&1
cat file.cpp | codex-ask --new "[memory]\n이 코드를 리뷰해줘" 2>&1
```

### Deep 모드

사용자가 "깊게 생각해봐", "좀 더 열심히", "심층 분석", "deep" 등을 언급하면 codex-ask에 `--deep` 플래그를 추가한다.

**`--deep`은 codex-ask 전용. gemini-ask에는 없는 옵션.**

**⚠️ Bash timeout은 반드시 600000ms (10분)으로 설정. 기본값 2분이면 응답이 잘린다.**

## 출력 형식

### 단순 협업

```
## Claude 의견
(Gemini/Codex 응답 전에 먼저 형성한 내 분석)

## Gemini 의견
(응답 요약)

## Codex 의견
(응답 요약)

## 종합 판단
- 합의: ...
- 쟁점: ... → Claude 판단: ...
- 결론: ...
```

### 멀티라운드 토론

```
## 라운드 1
### Claude 의견: ...
### Gemini 의견: ...
### Codex 의견: ...
### 쟁점 파악: ...

## 라운드 2
### Claude 반박/동의: ...
### Gemini 반박/동의: ...
### Codex 반박/동의: ...
### 합의 진전: ...

## 최종 종합
- 합의된 사항: ...
- 미합의 쟁점: ... → Claude 최종 판단: ...
- 결론: ...
```

## 토론 결과 저장

멀티라운드 토론이 끝나면 결론을 memory에 저장할지 사용자에게 묻는다.
저장하면 다음 토론에서 이전 결론을 참조할 수 있다.
