---
name: ai-collaborate
description: Gemini + Codex 병렬 협업. "AI 협업해줘", "크로스체크해줘", "세컨드 오피니언", "다른 AI한테 물어봐" 등의 요청 시 자동 호출.
disable-model-invocation: false
---

# AI 병렬 협업 모드

사용자가 "다른 AI한테 물어봐", "AI 협업해줘", "다른 모델 의견도 들어봐", "크로스체크해줘", "세컨드 오피니언", "AI랑 검토해줘" 등을 요청하면 이 skill을 따른다.

## 워크플로우

**중요: ask-gemini, ask-codex skill을 호출하지 말 것. Bash tool로 직접 실행한다.**

1. 동일한 프롬프트를 `gemini-ask`와 `codex-ask`에 **Bash tool 병렬 호출**로 전달
2. **Bash timeout 600000ms (10분)** 필수
3. 각 응답을 **출처 표기**하여 정리:
   - **Gemini 의견**: ...
   - **Codex 의견**: ...
4. Claude(나)의 의견도 함께 제시
5. 의견이 다르면 차이점을 요약
6. 사용자가 최종 판단할 수 있도록 비교 형태로 전달

## 사용 패턴

```bash
# 병렬 호출 (두 명령을 동시에 Bash tool로 실행)
gemini-ask --new "질문 내용" 2>&1
codex-ask --new "질문 내용" 2>&1
```

## 출력 형식

```
## Gemini 의견
(응답 요약)

## Codex 의견
(응답 요약)

## Claude 의견
(내 분석)

## 비교 정리
| 항목 | Gemini | Codex | Claude |
|------|--------|-------|--------|
| ... | ... | ... | ... |
```
