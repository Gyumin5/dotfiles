#!/bin/bash
# tool-latency: PostToolUse 훅. tool_name + duration_ms를 로그.
# 5초 이상 오래 걸린 호출은 stderr로 경고 (Claude transcript에 표시).

INPUT=$(cat 2>/dev/null || echo '{}')
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
DUR=$(echo "$INPUT" | jq -r '.duration_ms // empty' 2>/dev/null)
[ -z "$TOOL" ] && exit 0
[ -z "$DUR" ] && exit 0

LOG="$HOME/.claude/logs/tool-latency.log"
mkdir -p "$(dirname "$LOG")"

# Bash인 경우 명령 첫 토큰도 기록
EXTRA=""
if [ "$TOOL" = "Bash" ]; then
    cmd=$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null | head -c 80 | tr '\n' ' ')
    EXTRA=" cmd=\"$cmd\""
fi

echo "[$(date -Iseconds)] tool=$TOOL dur_ms=$DUR$EXTRA" >> "$LOG"

# 5000ms 이상이면 transcript 경고
if [ "$DUR" -gt 5000 ] 2>/dev/null; then
    echo "[tool-latency] $TOOL took ${DUR}ms (>5s)" >&2
fi
exit 0
