# Global Instructions

## AI 협업 규칙

사용자가 다른 AI 도구 사용을 요청할 때 아래 트리거 규칙을 따른다.

### 트리거 판단
| 요청 유형 | 호출 대상 |
|-----------|-----------|
| "gemini로 해줘", "gemini한테 물어봐" | Gemini만 |
| "codex로 해줘", "codex한테 물어봐" | Codex만 |
| "다른 AI한테 물어봐", "AI 협업해줘", "다른 모델 의견도 들어봐", "크로스체크해줘", "세컨드 오피니언" 등 | Gemini + Codex 둘 다 (병렬 호출) |

### 병렬 협업 모드
둘 다 호출할 때:
1. 동일한 프롬프트를 `gemini-ask`와 `codex-ask`에 **병렬**로 전달
2. 각 응답을 **출처 표기**하여 정리 (Gemini 의견 / Codex 의견)
3. 의견이 다르면 차이점을 요약하고, Claude(나) 의견도 함께 제시
4. 사용자가 최종 판단할 수 있도록 비교 형태로 전달

---

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
- **gemini-ask 호출 시 Bash tool의 timeout을 무조건 600000ms (10분)으로 설정한다**
- 긴 코드는 stdin으로 pipe하여 전달한다
- Gemini 응답이 잘린 것 같으면 사용자에게 알린다
- 주제 판단이 애매하면 사용자에게 어떤 세션을 쓸지 물어본다

## Codex CLI Integration

사용자가 "codex로 해줘", "codex한테 물어봐", "codex에게 시켜" 등 Codex CLI를 사용하라는 요청을 하면 아래 규칙을 따른다.

### 도구
- `codex-ask` 스크립트 (경로: ~/.local/bin/codex-ask)
- `codex-cli` MCP 서버 (Claude Code 내장 - codex mcp-server)

### 주제별 세션 관리 (핵심)
Codex에게 요청을 보낼 때, 현재 요청의 주제와 기존 세션 목록을 비교하여 적절한 세션을 선택한다.

**판단 순서:**
1. `codex-ask --list` 로 기존 세션 목록(summary)을 확인한다
2. 현재 요청 주제와 매칭되는 세션이 있으면 → `codex-ask --topic "주제키워드" "프롬프트"`
3. 매칭되는 세션이 없거나, 명확히 새로운 주제이면 → `codex-ask --new "프롬프트"`
4. 사용자가 명시적으로 "이어서" 등을 말하면 → `codex-ask "프롬프트"` (latest resume)
5. 특정 세션을 지정하면 → `codex-ask --session <uuid> "프롬프트"`

### 사용 패턴
```bash
# 세션 목록 확인 (주제 판단용)
codex-ask --list

# 주제 매칭으로 세션 자동 선택
codex-ask --topic "코드리뷰" "이 함수도 리뷰해줘"

# 새 주제 → 새 세션
codex-ask --new "새로운 주제 시작"

# 최근 세션 이어서
codex-ask "이어서 질문"

# 파일 내용 전달
cat file.py | codex-ask --topic "코드리뷰" "이 코드를 리뷰해줘"
```

### 워크플로우
1. 사용자 요청 수신
2. `codex-ask --list`로 세션 확인 → 주제 매칭 판단
3. 적절한 세션으로 `codex-ask` 호출 (필요한 컨텍스트를 프롬프트나 stdin으로 함께 전달)
4. Codex 응답을 사용자에게 전달
5. 필요시 후속 작업 수행

### MCP 서버 (codex-cli)
- Claude Code에서 직접 Codex 도구를 호출 가능 (mcp.json에 등록됨)
- `codex mcp-server`로 실행되며, Codex의 코드 실행/분석 기능 사용 가능

### 주의사항 (필수 - 반드시 지킬 것)
- **codex-ask, gemini-ask 호출 시 Bash tool의 timeout을 무조건 600000ms (10분)으로 설정한다**
- `--deep` 사용 시 timeout을 600000ms (10분)으로 설정한다
- "깊게 생각해", "deep think", "자세히 분석해" 등의 요청 시 `codex-ask --deep`으로 호출한다
- 긴 코드는 stdin으로 pipe하여 전달한다
- Codex 응답이 잘린 것 같으면 사용자에게 알린다
- 주제 판단이 애매하면 사용자에게 어떤 세션을 쓸지 물어본다
