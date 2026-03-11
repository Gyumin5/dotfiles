---
name: handoff-verify
description: 작업 완료 후 fresh-context 서브에이전트로 검증. "검증해줘", "확인해줘", "handoff verify" 등의 요청 시 호출.
disable-model-invocation: true
---

# /handoff-verify: Fresh-Context 검증

작업 완료 후 서브에이전트를 띄워 **fresh context에서** 빌드/테스트/린트를 검증한다.
기존 컨텍스트의 편향 없이 실제로 동작하는지 확인하는 것이 핵심.

## 워크플로우

### 1. 프로젝트 타입 감지

프로젝트 루트의 파일들로 타입을 판단:

| 감지 파일                     | 프로젝트 타입 | 검증 파이프라인                                 |
| ----------------------------- | ------------- | ----------------------------------------------- |
| `package.json`                | Node.js       | `npm run build && npm test`                     |
| `Cargo.toml`                  | Rust          | `cargo check && cargo test`                     |
| `CMakeLists.txt`              | CMake/C++     | `cmake --build build && ctest --test-dir build` |
| `setup.py` / `pyproject.toml` | Python        | `python -m pytest`                              |
| `*.tex` (main)                | LaTeX         | `latexmk -pdf main.tex`                         |
| `catkin_make` / `package.xml` | ROS           | `catkin_make` or `colcon build`                 |

CLAUDE.md에 Build/Test 섹션이 있으면 그 명령어를 우선 사용.

### 2. 서브에이전트 실행

Agent tool로 서브에이전트를 spawning한다:

```
Agent tool 호출:
- subagent_type: "general-purpose"
- prompt: 아래 검증 프롬프트
- model: "sonnet" (빠른 검증용)
```

**서브에이전트 프롬프트 템플릿:**

```
이 프로젝트를 fresh context에서 검증해라.

1. 프로젝트 CLAUDE.md를 읽어라 (있으면)
2. 아래 명령어를 순서대로 실행:
   - [타입체크 명령어]
   - [린트 명령어]
   - [빌드 명령어]
   - [테스트 명령어]
3. 각 단계의 결과를 보고:
   - ✅ PASS: 성공
   - ❌ FAIL: 에러 내용 + 분류
4. 에러 분류:
   - **Fixable**: import 누락, 타입 에러, 린트 에러 등 → 자동 수정 시도 (최대 3회)
   - **Non-Fixable**: 설계 문제, 외부 의존성 등 → 보고만
5. 최종 결과를 아래 형식으로 보고:
   ## 검증 결과
   - TypeCheck: ✅/❌
   - Lint: ✅/❌
   - Build: ✅/❌
   - Test: ✅/❌ (N/M passed)
   ## 자동 수정
   - (수정한 내용 목록)
   ## Non-Fixable 이슈
   - (수정 불가 이슈 목록)
```

### 3. 결과 정리

서브에이전트 결과를 받아서 사용자에게 보고:

- 전체 PASS → "검증 완료 ✅"
- Fixable 에러 수정됨 → 수정 내용 요약
- Non-Fixable 에러 → 이슈 목록 + 해결 방향 제안

## 규칙

- 서브에이전트는 반드시 **sonnet** 모델 사용 (비용 효율)
- 자동 수정은 **최대 3회** 재시도
- 수정 후 반드시 다시 빌드/테스트 실행하여 확인
- 검증 대상이 불명확하면 사용자에게 확인
