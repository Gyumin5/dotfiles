---
name: project-init
description: 프로젝트 분석 후 맞춤형 CLAUDE.md + AGENTS.md 자동 생성
disable-model-invocation: true
---

# /project-init: 프로젝트 맞춤형 CLAUDE.md + AGENTS.md 자동 생성

현재 프로젝트 디렉토리를 분석하고, 프로젝트 유형에 맞는 설정 파일들을 생성하라.

## 단계

### 1. 프로젝트 분석

아래 항목들을 자동 탐지하라:

- 빌드 시스템 (catkin, cmake, npm, cargo, pip 등)
- 언어 (C++, Python, Rust, TypeScript 등)
- 프레임워크 (ROS, Flask, React 등)
- 테스트 프레임워크 (gtest, pytest, jest 등)
- 린터/포매터 (.clang-format, black, ruff, eslint 등)
- 기존 CLAUDE.md, AGENTS.md, .cursorrules 등
- 주요 디렉토리 구조

### 2. 사용자 확인

분석 결과를 요약하여 보여주고, 추가 정보를 물어봐라:

- 탐지된 스택이 맞는지
- 추가로 포함할 규칙이 있는지
- 원격 빌드 등 특수 워크플로우가 있는지

### 3. 파일 생성

확인 후 아래 파일들을 생성하라:

#### CLAUDE.md (프로젝트 루트)

포함할 내용:

- **Stack**: 언어, 프레임워크, 버전
- **Build**: 정확한 빌드 명령어 (단일 패키지 빌드, 전체 빌드)
- **Test**: 정확한 테스트 명령어 (단일 테스트, 전체 테스트)
- **Style**: 기존 포매터/린터 설정 참조
- **Do not**: 금지 패턴 (프로젝트에서 자주 실수할 수 있는 것들)
- **Done means**: 완료 기준 (빌드 성공, 테스트 통과 등)

#### AGENTS.md (프로젝트 루트, 선택)

멀티 AI 도구 호환용 공용 규칙. CLAUDE.md와 중복을 피하고, 범용적인 규칙만 포함.

### 4. 서브디렉토리 CLAUDE.md (해당 시)

- LaTeX 논문 디렉토리가 있으면 → `paper/CLAUDE.md` 또는 해당 디렉토리에 생성
- 실험/데이터 분석 디렉토리가 있으면 → 해당 디렉토리에 생성

## 규칙

- 200줄 이내로 간결하게 작성
- 추상적 문구("깔끔하게", "잘 테스트해") 금지, 구체적 명령어만
- 기존 파일이 있으면 덮어쓰지 말고 병합 제안
- 생성 후 각 파일 내용을 보여줘서 사용자가 검토할 수 있게
