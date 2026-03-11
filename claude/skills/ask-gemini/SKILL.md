---
name: ask-gemini
description: Gemini CLI로 질문 전달. "gemini로 해줘", "gemini한테 물어봐" 등의 요청 시 자동 호출.
disable-model-invocation: false
---

# Gemini CLI Integration

사용자가 Gemini를 사용하라는 요청을 하면 이 skill을 따른다.

## 도구

- `gemini-ask` 스크립트 (경로: ~/.local/bin/gemini-ask)

## 세션 관리 (핵심)

**무조건 `--new` 금지.** 아래 판단 순서를 따른다:

### 1단계: 세션 목록 확인

먼저 `gemini-ask --list`로 기존 세션을 확인한다.

### 2단계: 판단

| 상황                            | 동작                                             |
| ------------------------------- | ------------------------------------------------ |
| 현재 요청과 관련된 세션이 있음  | `--topic "구체적키워드"` 또는 `--session <uuid>` |
| 관련 세션 없음 / 명확히 새 주제 | `--new`                                          |
| 사용자가 "이어서" 등 명시       | `gemini-ask "프롬프트"` (latest resume)          |
| 사용자가 "새로" 등 명시         | `--new`                                          |

### 3단계: topic 태그 규칙

**topic은 적절한 수준으로 구체적으로** 만든다:

- 나쁜 예: `"논문"`, `"코드"`, `"리뷰"`
- 좋은 예: `"논문-related-work"`, `"논문-실험결과"`, `"av-ros-빌드에러"`, `"코드리뷰-localization"`

topic 형식: `대주제-세부주제`

## 사용 패턴

```bash
# 세션 목록 확인
gemini-ask --list

# 구체적 topic으로 세션 매칭
gemini-ask --topic "논문-symmetric-fusion-intro" "서론을 다듬어줘"

# 새 주제
gemini-ask --new "새로운 질문"

# 파일 내용 전달
cat file.py | gemini-ask --topic "코드리뷰-localization" "이 코드를 리뷰해줘"
```

## 필수 규칙

- **Bash timeout을 무조건 600000ms (10분)으로 설정**
- 긴 코드는 stdin으로 pipe하여 전달
- Gemini 응답이 잘린 것 같으면 사용자에게 알림
- 세션 판단이 애매하면 사용자에게 물어봄
