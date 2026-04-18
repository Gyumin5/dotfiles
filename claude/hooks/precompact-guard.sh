#!/bin/bash
# precompact-guard: 압축 직전 progress.md 상태 점검.
# 룰: CWD에 progress.md가 있고, 최근 2시간 이내에 갱신되지 않았으면 압축 차단 (exit 2).
# 의도: stale한 progress.md 위에서 압축이 일어나면 다음 세션이 잘못된 맥락으로 이어감 → 사전 갱신 강제.
# CWD에 progress.md 없으면 통과.

set -uo pipefail

LOG=/home/gmoh/.claude/logs/precompact.log
mkdir -p "$(dirname "$LOG")"

# stdin JSON에서 cwd 추출 (없으면 현재 PWD)
INPUT=$(cat 2>/dev/null || echo '{}')
CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
[ -z "$CWD" ] && CWD="$PWD"

ts=$(date '+%Y-%m-%d %H:%M:%S')
PROG="$CWD/progress.md"

if [ ! -f "$PROG" ]; then
    echo "[$ts] cwd=$CWD progress.md 없음, 통과" >> "$LOG"
    exit 0
fi

# 2시간(7200초) 이내 갱신 여부
now=$(date +%s)
mtime=$(stat -c %Y "$PROG" 2>/dev/null || echo 0)
age=$(( now - mtime ))

if [ "$age" -gt 7200 ]; then
    echo "[$ts] cwd=$CWD progress.md stale (age=${age}s) → 압축 차단" >> "$LOG"
    echo "progress.md가 ${age}초 전 마지막 갱신. 압축 전에 progress.md 먼저 갱신해줘." >&2
    exit 2
fi

echo "[$ts] cwd=$CWD progress.md fresh (age=${age}s), 통과" >> "$LOG"
exit 0
