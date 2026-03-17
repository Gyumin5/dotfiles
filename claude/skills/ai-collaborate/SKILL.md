---
name: ai-collaborate
description: Gemini + Codex 병렬 협업. "AI 협업해줘", "크로스체크해줘", "세컨드 오피니언", "다른 AI한테 물어봐", "AI한테 리뷰" 등의 요청 시 자동 호출.
disable-model-invocation: false
---

# AI 병렬 협업 모드

사용자가 "다른 AI한테 물어봐", "AI 협업해줘", "크로스체크해줘", "세컨드 오피니언", "AI한테 리뷰해달라고 해" 등을 요청하면 이 skill을 따른다.

**중요: ask-gemini, ask-codex skill을 호출하지 말 것. Bash tool로 직접 실행한다.**

## 워크플로우

### 일반 질문

1. `gemini-ask`와 `codex-ask`를 **Bash tool `run_in_background: true`로 백그라운드 실행**
2. 응답을 기다리는 동안 **Claude가 자신의 의견을 정리**한다
3. Gemini/Codex 응답이 도착하면 3자 의견을 비교하고, **Claude가 종합 판단을 내린다**:
   - 합의점: 3자가 동의하는 부분
   - 쟁점: 의견이 갈리는 부분 + Claude의 최종 판단과 근거
   - 결론: Claude가 추천하는 방향

### 코드 리뷰 요청

"AI한테 코드 리뷰해달라고 해", "AI한테 리뷰 받아봐" 등의 경우:

1. `/code-review` 실행 (Claude 자체 멀티에이전트 리뷰)
2. 동시에 해당 코드를 `gemini-ask`와 `codex-ask`에 pipe로 전달하여 리뷰 요청
3. 3자 리뷰 결과를 통합:
   - 공통으로 지적한 문제 (높은 신뢰도)
   - 한쪽만 지적한 문제 (검토 필요)
   - 개선 제안 종합
4. 필요시 코드 수정안 제시

## Claude의 역할 (핵심)

Claude는 **단순 정리자가 아니라 적극적 참여자**다:

- Gemini/Codex 응답을 기다리기 전에 **자기 의견을 먼저 형성**
- 다른 AI의 의견에 **동의/반박 근거를 구체적으로** 제시
- 의견이 갈릴 때 **최종 추천안과 그 이유**를 명확히 제시
- 다른 AI가 틀렸다고 판단되면 솔직하게 지적

## 사용 패턴

```bash
# 백그라운드 실행 (Bash tool에서 run_in_background: true 사용)
gemini-ask --new "질문 내용" 2>&1   # run_in_background: true
codex-ask --new "질문 내용" 2>&1    # run_in_background: true

# 코드 리뷰 백그라운드 실행
cat file.cpp | gemini-ask --new "이 코드를 리뷰해줘" 2>&1   # run_in_background: true
cat file.cpp | codex-ask --new "이 코드를 리뷰해줘" 2>&1    # run_in_background: true
```

**주의: `--deep`은 codex-ask 전용 (xhigh reasoning). 사용자가 명시할 때만 사용. gemini-ask에는 없는 옵션.**

**⚠️ Bash timeout은 반드시 600000ms (10분)으로 설정. 기본값 2분이면 응답이 잘린다.**

## 출력 형식

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
