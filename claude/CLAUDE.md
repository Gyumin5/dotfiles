# Global Instructions

## Gemini CLI Integration

사용자가 "gemini로 해줘", "gemini한테 물어봐", "gemini에게 시켜" 등 Gemini CLI를 사용하라는 요청을 하면 아래 규칙을 따른다.

### 도구
- `gemini-ask` 스크립트 (경로: ~/.local/bin/gemini-ask)

### 주제별 세션 관리 (핵심)
Gemini에게 요청을 보낼 때, 현재 요청의 주제와 기존 세션 목록을 비교하여 적절한 세션을 선택한다.

**판단 순서:**
1. `gemini-ask --list` 로 기존 세션 목록(summary)을 확인한다
2. 현재 요청 주제와 매칭되는 세션이 있으면 → `gemini-ask --topic "주제키워드" "프롬프트"`
3. 매칭되는 세션이 없거나, 명확히 새로운 주제이면 → `gemini-ask --new "프롬프트"`
4. 사용자가 명시적으로 "이어서" 등을 말하면 → `gemini-ask "프롬프트"` (latest resume)
5. 특정 세션을 지정하면 → `gemini-ask --session <uuid> "프롬프트"`

### 사용 패턴
```bash
# 세션 목록 확인 (주제 판단용)
gemini-ask --list

# 주제 매칭으로 세션 자동 선택
gemini-ask --topic "코드리뷰" "이 함수도 리뷰해줘"

# 새 주제 → 새 세션
gemini-ask --new "새로운 주제 시작"

# 최근 세션 이어서
gemini-ask "이어서 질문"

# 파일 내용 전달
cat file.py | gemini-ask --topic "코드리뷰" "이 코드를 리뷰해줘"
```

### 워크플로우
1. 사용자 요청 수신
2. `gemini-ask --list`로 세션 확인 → 주제 매칭 판단
3. 적절한 세션으로 `gemini-ask` 호출 (필요한 컨텍스트를 프롬프트나 stdin으로 함께 전달)
4. Gemini 응답을 사용자에게 전달
5. 필요시 후속 작업 수행

### 주의사항
- gemini-ask의 timeout은 충분히 길게 설정한다 (최소 30초)
- 긴 코드는 stdin으로 pipe하여 전달한다
- Gemini 응답이 잘린 것 같으면 사용자에게 알린다
- 주제 판단이 애매하면 사용자에게 어떤 세션을 쓸지 물어본다
