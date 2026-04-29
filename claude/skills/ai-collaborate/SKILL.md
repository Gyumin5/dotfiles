---
name: ai-collaborate
description: Gemini + Codex 멀티 라운드 합의 토론. "AI 협업해줘", "크로스체크해줘", "세컨드 오피니언", "AI 토론", "합의할때까지", "비판자 포함" 등의 요청 시 자동 호출. 단일 진입점 — 매 호출이 비판자 포함 합의 토론.
disable-model-invocation: false
effort: high
---

# AI 합의 토론 (단일 진입점)

## 핵심
- 모든 협업/토론 트리거는 ai-debate CLI 한 가지 경로로 통일.
- 라운드마다 codex×2 + gemini×2 (각 AI가 debater + critic 두 역할 동시에) 병렬 호출.
- gemini 다 죽어도 codex 2개로 debater+critic 확보됨.
- JSON 표준 출력. 라운드 간 이전 출력을 컨텍스트로 전달. 합의될 때까지 반복 (max 3 라운드).
- 최종은 codex arbiter가 final_decision/action_steps/verification_plan/dissent로 통일 정리.
- 산출물 ~/.claude/state/ai-debate/run-<ts>/ 저장.

## 호출 규칙
- Bash tool로 직접 실행. 호출 직전 한 줄 사전 고지 필수 ("ai-debate 호출 중, 수 분 소요").
- `ai-debate "task"` 또는 stdin pipe — `cat file | ai-debate "검토"`.
- timeout 600000ms (라운드 최대 3 + arbiter = 4 phase. phase당 최대 600초).
- 큰 컨텍스트는 stdin으로. task arg는 짧게.
- 프로젝트 메모리는 기본 OFF. 토론 품질 보호. 필요 시 `--with-memory`.
- max rounds 조정: `--max-rounds 2` (가벼운 케이스), 기본 3.

## 출력 형식 (사용자 응답)
- 라운드별 한 줄 요약 (debater positions / critic should_proceed 표시)
- 마지막에 ARBITER 블록: FINAL + rationale + action_steps + verification_plan + dissent
- 토큰 절약 위해 모든 debater/critic 원문은 dump 안 함. run_dir 경로만 안내.

## 실패 처리
- gemini 429/parse 실패는 자연스럽게 무시 (codex 2개로 충분). 사용자 알림 불필요.
- codex 둘 다 실패면 그 라운드 무효 → 다음 라운드 재시도.
- arbiter 실패면 그 사실만 알리고 라운드 결과 dump.

## 코드 리뷰 변형
"AI한테 코드 리뷰" / "AI한테 리뷰 받아" 트리거:
- /code-review (Claude 멀티에이전트) 실행과 병행해서 `cat file | ai-debate "리뷰: <파일> 의 문제점·개선안"` 호출.
- 통합: 공통 지적(고신뢰) / 단일 지적(검토) / arbiter 권고안.

## 안 하는 것
- 트리거 분리 (모든 협업 키워드는 ai-debate 단일 경로). 사용자 결정 (2026-04-29).
- ai-debate 안에서 claude 호출 (부모 세션 telegram MCP를 disrupt). 풀은 codex+gemini만.
- 1라운드만 돌고 종료 (합의 추구가 본질).
