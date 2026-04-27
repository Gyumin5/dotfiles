#!/bin/bash
# precompact-guard: 압축 직전 progress.md 상태 점검.
# 룰: CWD에 progress.md가 있고, 24시간 이내에 갱신되지 않았으면 압축 차단 (exit 2).
# 의도: 매우 stale한 progress.md 위에서 압축 = 맥락 손실. 24h는 일반적 작업 사이클을 넘는 임계값.
# 이전 2h 임계는 너무 빡빡해서 데드락 발생 → 24h로 완화 (2026-04-27 재도입).
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

# 24시간(86400초) 이내 갱신 여부
now=$(date +%s)
mtime=$(stat -c %Y "$PROG" 2>/dev/null || echo 0)
age=$(( now - mtime ))

if [ "$age" -gt 86400 ]; then
    echo "[$ts] cwd=$CWD progress.md stale (age=${age}s) → 압축 차단" >> "$LOG"
    echo "progress.md가 ${age}초 전 마지막 갱신. 압축 전에 progress.md 먼저 갱신해줘." >&2
    exit 2
fi

echo "[$ts] cwd=$CWD progress.md fresh (age=${age}s), 통과" >> "$LOG"
exit 0
