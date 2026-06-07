# Claude Code 미문서화 옵션 — 존재 검증 매트릭스 (2026-06-08)

직전 ai-debate(run-20260607T224521Z) 결론에 따른 "첫 실행 항목 1개" = 비파괴·단발·저위험 검증.
일일 리서치 글#2("I read the Claude Code source code")가 주장한 미문서화 옵션이
"우리가 실제로 설치한 버전에 식별자로 존재하는가" 만 확인한다.

## 메타
- 일시: 2026-06-08 (KST)
- 머신: home (gmoh-Z790-AORUS-ELITE-X)
- claude 버전: 2.1.166 (Claude Code)
- 바이너리: /home/gmoh/.local/share/claude/versions/2.1.166 (ELF 64-bit, 235M, not stripped)

## 방법 (왜 이 방법인가)
- 토론이 정한 범위 = 모델/API/MCP/Telegram 호출 없이 "존재/파싱/무해" 확인.
- 채택한 검증 = 설치된 단일 실행 바이너리에 대한 read-only 문자열 grep (`grep -a -c <식별자>`).
  CLI 를 띄우는 것보다도 부수효과 0 이고, "옵션 식별자 실재" 를 직접 본다.
- 한계(중요): grep 존재 = 그 문자열이 번들에 있다는 것뿐. 실제 동작/지원/스키마/버전별
  활성화는 증명하지 못함. 일부 count 는 무관한 부분일치일 수 있음(식별자가 특이할수록 신뢰↑).
  동작 확인은 모델/세션 호출이 필요 → 이번 범위 밖(아래 deferred).
- 격리 환경 준비도 해둠(이번엔 grep 으로 충분해 CLI 미실행):
  empty MCP = `{"mcpServers":{}}`, env -i + HOME/XDG/CLAUDE_CONFIG_DIR 임시 + 토큰 무력화로
  `claude --strict-mcp-config --mcp-config <empty> --help` 가능. 모델 호출 필요 시 즉시 중단 규칙.

## 결과 매트릭스 (grep 존재)

| option | scope | 출처 주장 | grep count | verdict | risk_note |
|---|---|---|---|---|---|
| additionalContext | hook 응답(Pre/Post/SessionStart) | 컨텍스트 주입 | 33 | EXISTS | 우리 훅 이미 유사 사용(reply-injector) |
| permissionDecision | PreToolUse 응답 | allow/deny 강제 | 15 | EXISTS | 권한 우회 가능 → 도입 시 감사로그 필수 |
| permissionDecisionReason | PreToolUse 응답 | UI 사유 | 5 | EXISTS | — |
| updatedInput | PreToolUse 응답 | 파라미터 재작성 | 61 | EXISTS | 입력 변조 → 보안 체크리스트 대상 |
| updatedMCPToolOutput | PostToolUse 응답 | MCP 출력 변조 | 6 | EXISTS(실행 deferred) | 부수효과 가능 |
| initialUserMessage | SessionStart | 첫 메시지 prepend | 7 | EXISTS | — |
| watchPaths | SessionStart | 파일변경 감시 | 11 | EXISTS(실행 deferred) | 무인 runaway 위험 |
| asyncRewake | hook 설정 | exit2 시 모델 재각성 | 5 | EXISTS(실행 deferred) | 자동 재각성=runaway 위험 |
| disable-model-invocation | skill frontmatter | 자동호출 차단 | 10 | EXISTS | 저위험·유용 |
| omitClaudeMd | agent frontmatter | CLAUDE.md 무시 | 4 | EXISTS | "편향제거" 주장은 과장 가능 |
| requiredMcpServers | agent frontmatter | MCP 없으면 미로드 | 3 | EXISTS | 저위험·유용 |
| criticalSystemReminder_EXPERIMENTAL | agent frontmatter | 매턴 재주입·압축생존 | 5 | EXISTS | 명칭에 EXPERIMENTAL, 불안정 가정 |
| autoMemoryEnabled | settings | 세션후 메모리 추출 | 5 | EXISTS(실행 deferred) | 우리 progress/history append-only 충돌 검토 |
| autoDreamEnabled | settings | 24h 메모리 통합 | 4 | EXISTS(실행 deferred) | ADR 조용한 재작성 위험 → 샌드박스만 |
| autoMode | settings | YOLO 자동승인 분류 | 18 | EXISTS(실행 deferred) | 자동승인=고위험, 보안 검토 전 금지 |
| soft_deny | autoMode 하위 | 부드러운 거부목록 | 24 | EXISTS | autoMode 스키마 실재 정황 보강 |
| effort | skill frontmatter/일반 | 추론 깊이 | 299 | EXISTS | count 큼=일반 용어일 수 있음 |
| statusMessage | hook 설정 | 상태표시 | 62 | EXISTS | — |
| initialUserMessage | SessionStart | (중복확인) | 7 | EXISTS | — |
| CLAUDE_CODE_AUTO_COMPACT_WINDOW | env(글#1) | 조기 압축 임계 | 10 | EXISTS | 저위험, 시도 가치 |
| "MAGIC DOC" (정확 문구) | 백그라운드 문서 갱신 | 파일 한정 편집 | 0 | NOT FOUND | 글#2 주장 중 유일 미확인 — 명칭/대소문자 다르거나 부정확 가능 |

## 판정 요약
- 글#2가 주장한 미문서화 식별자 대부분이 우리 설치본(2.1.166)에 실재함 → "전부 허구" 는 아님.
  단, 식별자 존재 ≠ 문서화된 대로 동작. 특히 동작·스키마는 미검증.
- 유일하게 정확 문구로 안 잡힌 것: "MAGIC DOC". (다른 표기 가능성 있으나 현 시점 미확인.)
- 직전 토론의 "과장 주장" 경고와 정합: 식별자는 있어도 글의 효능 서술(예: omitClaudeMd
  '편향제거', autoDream '안전한 모순해소')은 별도 검증 필요.

## 이번에 실행하지 않음 (deferred — 부수효과/운영영향)
다음은 grep 존재만 확인했고 "동작 실행" 은 하지 않음. 별도 throwaway repo + 버전고정 +
timeout + 비용/rate-limit 한도 + 테스트 allowlist + progress checkpoint 하에서만 검증:
- asyncRewake, watchPaths, updatedMCPToolOutput, autoMode, autoMemoryEnabled, autoDreamEnabled.
사유: 자동 재각성/감시/자동승인/자동 메모리 재작성은 무인 9세션 운영에 runaway·스팸·
rate-limit·ADR 오염 위험. 운영 dotfiles·systemd·Telegram·메모리 파일은 미변경.

## 다음 후보 (저위험부터, 운영 적용 전 각 1줄 실험)
1. disable-model-invocation / requiredMcpServers — 저위험, 즉시 유용(스킬·에이전트 안정화).
2. CLAUDE_CODE_AUTO_COMPACT_WINDOW — 단일 세션에서 조기 압축 임계 시험.
3. additionalContext(SessionStart) — 이미 유사 사용 중, 표준화 검토.
나머지(권한/입력/출력 변조, auto 계열)는 보안·runaway 검토 후 throwaway 환경에서만.

## 검증(이 작업 자체)
- 생성 파일 1개뿐: docs/research/claude-undocumented-options-matrix-2026-06-08.md.
- 모델/API/MCP/Telegram 호출 0. systemd unit/timer 신규 0. 운영 설정/메모리 변경 0.
- 전부 read-only grep + 디렉터리 1개 생성. git revert 로 즉시 원복 가능.
