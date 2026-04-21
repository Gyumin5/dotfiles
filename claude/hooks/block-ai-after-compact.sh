#!/bin/bash
# block-ai-after-compact: PreToolUse 훅. 압축 직후 N분간 gemini-ask/codex-ask/ai-collaborate Bash 호출을 차단.
# 모델이 compact 요약의 과거 tool use를 보고 자동으로 AI 재호출하는 것을 방지.
# 사용자가 명시적으로 요청할 때만 (N분 지난 뒤 또는 명시적 재요청 후) 허용.

set -uo pipefail

FLAG="$HOME/.claude/state/just-compacted.flag"
BLOCK_WINDOW_SEC=300  # 5분

# stdin JSON에서 bash 명령 추출
INPUT=$(cat 2>/dev/null || echo '{}')
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$CMD" ] && exit 0

# AI 호출 패턴 매칭
if ! echo "$CMD" | grep -qE 'gemini-ask|codex-ask|ai-collab'; then
    exit 0
fi

# 압축 플래그 확인
[ ! -f "$FLAG" ] && exit 0

now=$(date +%s)
mtime=$(stat -c %Y "$FLAG" 2>/dev/null || echo 0)
age=$(( now - mtime ))

if [ "$age" -gt "$BLOCK_WINDOW_SEC" ]; then
    # 윈도우 지남. 이제 허용하고 플래그 정리
    rm -f "$FLAG"
    exit 0
fi

# 윈도우 안에서 AI 호출 시도 → 차단
remaining=$(( BLOCK_WINDOW_SEC - age ))
echo "[block-ai-after-compact] 압축 직후 ${age}초. AI 호출 차단 (${remaining}초 뒤 자동 해제). 사용자가 명시적으로 재요청해야 진행." >&2

# exit 2로 PreToolUse 차단
exit 2
