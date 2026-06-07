# 저위험 옵션 verifiability triage (2026-06-08)

경로 결정 ai-debate(run-20260607T231209Z) 결론 = B: 모델호출 canary 지금 안 함.
대신 모델호출 0회로 저위험 옵션 4종을 분류한다:
VERIFIED_STATIC / NEEDS_MODEL_CALL / UNSUITABLE_CANARY / HUMAN_AB_REQUIRED.

- claude 버전: 2.1.166 (바이너리 read-only grep + 우리 훅 소스 + 운영 관측).
- 모델/API/MCP/Telegram 호출 0. 운영 dotfiles·~/.claude·설정·메모리 무변경.

## 결과

### 1. additionalContext — VERIFIED_STATIC ✓
근거: 우리 훅이 이미 산출하고 매 세션 주입됨(운영 관측). 예: claude/hooks/inject-briefing.sh
(`"additionalContext": ctx`), prompt-length-guard.sh, rate-limit-prompt-guard.sh,
postcompact-warn.sh, telegram-reply-injector.sh, session-start-context.sh. 실제 세션의
system-reminder("SessionStart hook additional context", "UserPromptSubmit ... additionalContext")가
주입 동작을 증명. → 추가 검증 불필요. 이미 채택·사용 중.

### 2. requiredMcpServers — VERIFIED_STATIC ✓ (소스 함수 확인)
근거: 바이너리에 실제 판정 함수 존재 —
`if(!H.requiredMcpServers||H.requiredMcpServers.length===0) return true;
 return H.requiredMcpServers.every((q)=> available.some((K)=> K.toLowerCase()...))`.
즉 requiredMcpServers 없으면 통과, 있으면 "나열된 서버가 가용 MCP에 전부(대소문자 무시) 존재"해야
에이전트 로드. 로드시점 순수 술어 → 모델호출 불필요로 의미 확정.
의미: 특정 MCP가 없으면 그 에이전트를 아예 안 띄움. 안전·결정적.
적용처: 현재 우리 custom 에이전트 없음 → 즉시 적용 대상 없음. 향후 MCP 의존 에이전트 추가 시 사용.

### 3. disable-model-invocation — VERIFIED_STATIC(파싱/의미 추정), 완전확인은 NEEDS_MODEL_CALL
근거: 바이너리에서 `argument-hint`, `arguments`, `user-invocable` 와 한 묶음으로 파싱됨.
스킬/커맨드 frontmatter 의 인식 필드로, user-invocable(=명시 호출만) 토글과 짝. 의미는
"모델 자동호출 차단, /명령으로만". 자동호출 억제 효과의 100% 행동확인은 모델 턴 관측 필요(가치 낮음 —
의미가 user-invocable 쌍으로 이미 명확).
적용처: 우리 스킬은 의도적으로 키워드 자동라우팅(ai-collaborate 등) → 지금 붙이면 라우팅 깨짐.
즉시 적용 대상 없음. "특정 스킬을 자동호출에서 빼고 싶을 때" 만 사용.

### 4. CLAUDE_CODE_AUTO_COMPACT_WINDOW — HUMAN_AB_REQUIRED
근거: 식별자 존재 확인(grep 10). 효과(토큰 임계 조기 압축)는 긴 실세션에서만 관측 가능하고,
우리 PreCompact 24h 가드·ENABLE_PROMPT_CACHING_1H·압축 IRON LAW(progress/history 처리)와
상호작용 가능 → canary 부적합. 도입하려면 단일 비핵심 세션에서 인간 A/B + 관측 필요.

## 종합
- 모델호출 없이 끝낼 수 있는 것은 끝남: additionalContext(이미 사용), requiredMcpServers(소스로 의미 확정),
  disable-model-invocation(파싱·의미 확정).
- 셋 다 "이해/안전"은 확인됐으나 즉시 적용할 사용처가 없음(우리 셋업과 맞지 않거나 이미 사용 중).
  → 불필요한 변경 안 함. 향후 필요 시 근거로 활용.
- 모델호출이 꼭 필요한 잔여: disable-model-invocation 의 자동호출 억제 100% 행동확인뿐인데 가치 낮음 →
  지금 승인요청 안 함. AUTO_COMPACT_WINDOW 는 인간 A/B 대상으로 별도.
- 결론: 이 트랙에서 자율로 더 할 안전 작업은 사실상 소진. 남은 건 (a)CLAUDE.md 재분류 등 인간 A/B,
  (b)가치 낮은 모델호출 확인뿐. 다음은 사용자 지정 권장.

## 검증(이 작업)
- 신규 파일 1개(이 문서)만. 모델호출 0, 운영/설정/메모리/ systemd 무변경. git revert 로 원복.
