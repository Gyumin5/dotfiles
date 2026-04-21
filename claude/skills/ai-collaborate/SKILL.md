---
name: ai-collaborate
description: Gemini + Codex 병렬 협업. "AI 협업해줘", "크로스체크해줘", "세컨드 오피니언", "다른 AI한테 물어봐", "AI한테 리뷰", "AI 토론", "합의할때까지" 등의 요청 시 자동 호출.
disable-model-invocation: false
effort: high
---

# AI 병렬 협업

## 핵심 규칙
- gemini-ask, codex-ask는 Bash tool로 직접 실행 (skill로 호출 금지)
- 두 호출은 병렬 foreground Bash tool call (run_in_background 금지)
- Bash timeout 반드시 600000ms (기본 2분이면 잘림)
- 파일 수정·생성·삭제는 Claude만 수행. codex-ask에 --full-auto 금지
- 모든 호출에 [Project Memory] 첨부 (아래)
- Claude는 정리자 아님: 응답 기다리는 동안 자기 의견 먼저 형성, 다른 AI 의견에 동의/반박 근거 제시, 갈리면 최종 추천안 명시

## Memory 첨부

```bash
MEMORY_DIR="$HOME/.claude/projects/-home-gmoh-$(basename $(pwd))/memory"
MEMORY=""
[ -d "$MEMORY_DIR" ] && for f in "$MEMORY_DIR"/*.md; do
  [ "$(basename "$f")" = "MEMORY.md" ] || MEMORY+="$(cat "$f")\n---\n"
done
```

프롬프트 형식:
```
[Project Memory]
{MEMORY}

[질문]
{질문}
```

## 모드

### 단순 협업 (기본)
트리거: "AI 협업", "크로스체크", "세컨드 오피니언"
1. gemini-ask --new + codex-ask --new 병렬 호출
2. Claude도 자기 의견 형성 (대기 중)
3. 종합: 합의점 / 쟁점 + Claude 판단 / 결론

### 멀티라운드 토론
트리거: "AI 토론", "깊게 논의", "합의할때까지", "여러 라운드"
- 라운드 1: 독립 의견 (--new 사용)
- 라운드 2~N: 이전 라운드 다른 AI 의견을 각자에게 전달 (세션 이어가기, --new 없이). 동의/반박 구분 요청
- 종료: 실질 합의 OR 최대 3라운드 (사용자 "계속"이면 추가)
- 끝나면 결론을 memory 저장할지 사용자에게 물어보기

### 코드 리뷰
트리거: "AI한테 코드 리뷰", "AI한테 리뷰 받아"
1. /code-review 실행 (Claude 멀티에이전트)
2. 동시에 cat file | gemini-ask --new ... + cat file | codex-ask --new ...
3. 통합: 공통 지적(고신뢰) / 단일 지적(검토) / 개선안 종합

## Deep 모드
"깊게", "더 열심히", "deep" 등 → codex-ask에 --deep 추가. gemini-ask는 미지원.

## 실패 처리
AI 응답 timeout: 10초 후 1회 재시도. 또 실패면 해당 AI 제외하고 진행 + 사용자 알림 ("Gemini 실패. Claude+Codex로 진행")

## 출력 형식

단순 협업:
```
## Claude 의견 (먼저 형성)
## Gemini 의견
## Codex 의견
## 종합: 합의 / 쟁점+Claude판단 / 결론
```

멀티라운드:
```
## 라운드 N
- Claude / Gemini / Codex 의견 (또는 반박)
- 합의 진전
## 최종 종합
- 합의 / 미합의 쟁점+Claude 최종판단 / 결론
```
