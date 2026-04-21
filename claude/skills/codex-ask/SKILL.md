---
name: codex-ask
description: Codex CLI로 질문 전달. "codex로/한테", "codex 의견", "codex에 물어봐", "codex로 분석/리뷰" 등 codex 키워드 포함 요청 시 자동 호출.
disable-model-invocation: false
effort: low
---

# Codex CLI Integration

도구: `codex-ask` (~/.local/bin/codex-ask)

## 핵심 규칙
- Bash timeout 무조건 600000ms (기본 2분이면 잘림)
- 긴 컨텍스트는 stdin pipe + 짧은 arg ($1 인자 항상 필수, 인자 없는 호출 금지)
- "$(cat file)" 방식은 ARG_MAX 128KB 한계, 큰 프롬프트는 stdin
- heredoc + $() 중첩 금지 (한글 quoting 깨짐)
- 파일 수정 권한 없음 (--full-auto 금지)
- 응답이 잘린 듯하면 사용자에게 알림

## 세션 관리
무조건 --new 금지. 순서:
1. `codex-ask --list`로 기존 세션 확인 (현재 cwd 매칭)
2. 매칭 판단:
   - 관련 세션 있음 → `--topic "구체적키워드"` 또는 `--session <uuid>`
   - 관련 세션 없음 / 명확히 새 주제 → `--new`
   - 사용자 "이어서" → `codex-ask "프롬프트"` (latest resume)
   - 사용자 "새로" → `--new`
3. topic은 구체적: 나쁜 예 "논문/코드". 좋은 예 "논문-related-work", "av-ros-빌드에러"
   형식: 대주제-세부주제[-키워드]

## Deep 모드
"깊게/더 열심히/심층/deep" → `--deep` 추가. timeout 동일 600000ms.

## 사용 예
```bash
codex-ask --list
codex-ask --topic "논문-symmetric-fusion-intro" "서론 다듬어줘"
codex-ask --deep --new "복잡한 분석"
cat file.py | codex-ask --topic "코드리뷰-localization" "리뷰해줘"
```
