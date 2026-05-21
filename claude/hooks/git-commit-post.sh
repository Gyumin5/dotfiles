#!/bin/bash
# git-commit-post: PostToolUse Bash 훅. `git commit` 성공 시:
#   1) cwd 의 progress.md 강제 갱신 (claude-progress-updater 백그라운드 실행, 임계 우회)
#   2) commit message 에 [DECISION] 마커 있으면 history.md 에 ADR 라인 append
# 실패한 commit / commit 아닌 git 명령 / git 없는 디렉토리 → no-op, 빠르게 exit.

set -uo pipefail

INPUT=$(cat 2>/dev/null || echo '{}')
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
[ "$TOOL" = "Bash" ] || exit 0

CMD=$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null)
# `git commit` 토큰 단독 매칭 (echo "git commit" 같은 거 무시 위해 단순 substring)
echo "$CMD" | grep -qE '(^|[;&|]| )git +(commit|-c\s+\S+\s+commit)' || exit 0

# 결과 확인: tool_response 에 성공 신호 있어야 함
RESP=$(echo "$INPUT" | jq -r '.tool_response.stdout // .tool_response.output // ""' 2>/dev/null)
EXIT=$(echo "$INPUT" | jq -r '.tool_response.exit_code // .tool_response.returncode // 0' 2>/dev/null)
# pre-commit hook fail 등은 exit !=0
if [ "$EXIT" != "0" ] && [ "$EXIT" != "null" ]; then
    exit 0
fi
# 일반 git commit 성공 메시지 한 줄 ("[branch hash] subject")
echo "$RESP" | grep -qE '\[[^]]+ [0-9a-f]{6,}\]' || exit 0

CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
[ -z "$CWD" ] && CWD="$PWD"
[ -d "$CWD/.git" ] || exit 0

# 최근 commit info
HASH=$(git -C "$CWD" rev-parse --short HEAD 2>/dev/null)
SUBJ=$(git -C "$CWD" log -1 --format='%s' 2>/dev/null)
BODY=$(git -C "$CWD" log -1 --format='%b' 2>/dev/null)
DATE=$(date '+%Y-%m-%d %H:%M KST')

# 1) progress.md 강제 갱신 (백그라운드, 사용자 응답 지연 방지)
if [ -f "$CWD/progress.md" ] && command -v claude-progress-updater >/dev/null 2>&1; then
    CLAUDE_PROGRESS_FORCE=1 nohup /home/gmoh/.local/bin/claude-progress-updater "$CWD" \
        >> /home/gmoh/.claude/logs/progress-updater.log 2>&1 &
fi

# 2) [DECISION] 마커 → history.md append
if echo "$SUBJ$BODY" | grep -qE '\[DECISION\]|^DECISION:'; then
    HIST="$CWD/history.md"
    # 본문에서 마커 다음 줄들 추출 (없으면 subject 만 사용)
    REASON=$(echo "$BODY" | grep -iE '^근거:|^reason:|^why:' | head -1 | sed 's/^[^:]*: *//')
    [ -z "$REASON" ] && REASON="$SUBJ"
    # 번호 자동 (당일 #NN)
    NN=$(grep -cE "^## \[$(date '+%Y-%m-%d')\]" "$HIST" 2>/dev/null || echo 0)
    NN=$((NN + 1))
    {
        echo ""
        echo "## [$(date '+%Y-%m-%d')] #$(printf '%02d' $NN) $SUBJ"
        echo "tags: commit"
        echo "- 결정: $SUBJ"
        echo "- 근거: $REASON"
        echo "- hash: $HASH"
        echo "- updated: $DATE"
    } >> "$HIST"
fi

exit 0
