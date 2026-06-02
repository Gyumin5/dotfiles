---
name: ai-collaborate
description: 모든 외부 AI 호출의 단일 진입점. Gemini + Codex 멀티 라운드 합의 토론. "AI 협업/크로스체크/세컨드오피니언/AI 토론/합의/비판자/gemini/codex/AI한테 물어봐" 등 외부 AI를 부르는 모든 키워드 시 자동 호출. gemini-ask·codex-ask 단독 사용 금지 — 의도가 단일 질의라도 ai-collaborate가 라우팅.
disable-model-invocation: false
effort: high
---

# AI 합의 토론 (단일 진입점)

## 핵심
- 모든 협업/토론 트리거는 ai-debate CLI 한 가지 경로로 통일.
- 풀 = [codex, gemini, claude]. 라운드마다 풀의 각 agent 를 역할 수만큼 호출 (기본 역할 debater+critic → 3 agent × 2 역할 = 6콜/라운드).
- claude 는 격리 HOME(/home/gmoh/.claude-iso)으로 호출 → 부모 세션 telegram MCP / .claude.json 충돌 회피 (그래서 풀에 포함 가능).
- 일부 provider(예: gemini 429, codex 장애)가 죽어도 나머지로 debater+critic 확보됨.
- JSON 표준 출력. 라운드 간 이전 출력을 컨텍스트로 전달. 합의되면 조기 종료, 안 되면 max_rounds 까지 반복 (기본 2, --deep 시 5).
- 합의 조건: critic 전부 should_proceed=true + debater position 수렴.
- 최종은 codex arbiter가 final_decision/action_steps/verification_plan/dissent로 통일 정리.
- 성공 콜 / 예정 콜 < 2/3 이면 arbiter 건너뛰고 실패 종료.
- 산출물 ~/.claude/state/ai-debate/run-<ts>/ 저장.

## 호출 규칙
- Bash tool로 직접 실행. 호출 직전 한 줄 사전 고지 필수 ("ai-debate 호출 중, 수 분 소요").
- `ai-debate "task"` 또는 stdin pipe — `cat file | ai-debate "검토"`.
- timeout 600000ms. phase당 최대 600초. (기본 2라운드 + arbiter. --deep 5라운드면 더 김.)
- 큰 컨텍스트는 stdin으로. task arg는 짧게.
- 프로젝트 메모리는 기본 OFF. 토론 품질 보호. 필요 시 `--with-memory`.
- 라운드: 기본 2. 가벼우면 `--max-rounds 1`, 깊게는 `--deep`(5라운드).
- 동적 역할: `--auto-roles` (planner LLM 이 task 보고 역할 자동선정, critic 자동추가), `--max-roles N`(기본 4).
  명시는 `--roles debater,...`. 예산 가드 `--max-total-calls`(기본 24, 초과 시 시작 전 중단). `--dry-run` 으로 예상 콜수만.
- 캐시: 같은 task 24h 재호출 시 캐시. 우회 `--no-cache` 또는 `--seed`.

## 출력 형식 (사용자 응답)
- 라운드별 한 줄 요약 (debater positions / critic should_proceed 표시)
- 마지막에 ARBITER 블록: FINAL + rationale + action_steps + verification_plan + dissent
- 토큰 절약 위해 모든 debater/critic 원문은 dump 안 함. run_dir 경로만 안내.

## 실패 처리
- gemini 429/parse 실패는 자연스럽게 무시 (codex/claude 로 충분). 사용자 알림 불필요.
- 성공 콜 / 예정 콜 < 2/3 이면 arbiter 건너뛰고 실패 종료 (라운드 결과는 dump).
- arbiter(codex) 실패면 그 사실만 알리고 라운드 결과 dump.

## 코드 리뷰 변형
"AI한테 코드 리뷰" / "AI한테 리뷰 받아" 트리거:
- /code-review (Claude 멀티에이전트) 실행과 병행해서 `cat file | ai-debate "리뷰: <파일> 의 문제점·개선안"` 호출.
- 통합: 공통 지적(고신뢰) / 단일 지적(검토) / arbiter 권고안.

## 안 하는 것
- 트리거 분리 (모든 협업 키워드는 ai-debate 단일 경로). 사용자 결정 (2026-04-29).
- 부모 세션 claude 직접 호출 (telegram MCP disrupt). 풀의 claude 는 격리 HOME(/home/gmoh/.claude-iso) 전용.
- arbiter 를 codex 외 다른 agent 로 (항상 codex arbiter).
