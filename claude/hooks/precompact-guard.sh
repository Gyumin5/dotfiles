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
    echo "[$ts] cwd=$CWD progress.md stale (age=${age}s) → updater 동기 실행 (보험)" >> "$LOG"
    # progress-updater 동기 실행 (compact 직전 마지막 갱신)
    if command -v claude-progress-updater >/dev/null 2>&1; then
        timeout 300 /home/gmoh/.local/bin/claude-progress-updater "$CWD" >> "$LOG" 2>&1 || true
        # 갱신 후에도 여전히 stale이면 차단, 아니면 통과
        new_mtime=$(stat -c %Y "$PROG" 2>/dev/null || echo 0)
        if [ "$(( $(date +%s) - new_mtime ))" -gt 86400 ]; then
            echo "[$ts] updater 후에도 stale → 압축 차단" >> "$LOG"
            echo "progress.md updater 실행했지만 갱신 실패. 수동 점검 필요." >&2
            exit 2
        fi
        echo "[$ts] updater 갱신 성공, 압축 통과" >> "$LOG"
    else
        echo "progress.md가 ${age}초 전 마지막 갱신. updater 미설치 → 압축 차단." >&2
        exit 2
    fi
fi

echo "[$ts] cwd=$CWD progress.md fresh (age=${age}s), 통과" >> "$LOG"
exit 0
