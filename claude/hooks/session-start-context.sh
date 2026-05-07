#!/bin/bash
# session-start-context: SessionStart 훅. 프로젝트 cwd의 progress.md + history.md 내용을
# claude에게 additionalContext로 주입해서 새 세션이 즉시 작업 맥락 파악.

set -uo pipefail

INPUT=$(cat 2>/dev/null || echo '{}')
CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
[ -z "$CWD" ] && CWD="$PWD"

PROG="$CWD/progress.md"
ACTIVE="$CWD/history/active.md"
HIST="$CWD/history.md"

parts=""
if [ -f "$PROG" ]; then
    # progress는 hard limit 120줄이라 통째 주입 가능
    pcontent=$(head -c 8000 "$PROG")
    parts+="## progress.md (현재 진행 상황)\n\n${pcontent}\n\n"
fi
# 우선순위: history/active.md (compact view) > history.md tail (fallback)
if [ -f "$ACTIVE" ]; then
    acontent=$(head -c 6000 "$ACTIVE")
    parts+="## history/active.md (현재 유효한 결정)\n\n${acontent}\n\n"
    parts+="(전체 결정 로그는 history.md / history/YYYY-MM.md 에서 lazy load)\n"
elif [ -f "$HIST" ]; then
    hcontent=$(tail -c 4000 "$HIST")
    parts+="## history.md (최근 결정 로그 — active.md 없음)\n\n${hcontent}\n"
fi

# 이전 세션 archived jsonl 가장 최근 1개를 hint로 주입.
# cs rotate가 ~/.claude/projects/<key>/archive/ 로 옮겨둠. key는 cwd의 / 와 _ 를 - 로.
PROJ_KEY=$(echo "$CWD" | sed -e 's|/|-|g' -e 's|_|-|g')
ARCHIVE_DIR="$HOME/.claude/projects/${PROJ_KEY}/archive"
LAST_ARCHIVED=""
if [ -d "$ARCHIVE_DIR" ]; then
    LAST_ARCHIVED=$(ls -t "$ARCHIVE_DIR"/*.jsonl 2>/dev/null | head -1)
fi
if [ -n "$LAST_ARCHIVED" ]; then
    asize=$(stat -c %s "$LAST_ARCHIVED" 2>/dev/null || echo 0)
    alines=$(wc -l < "$LAST_ARCHIVED" 2>/dev/null || echo 0)
    parts+="## 이전 세션 archive\n\n"
    parts+="이전 세션의 transcript jsonl이 아래 경로에 보존되어 있다. 필요하면 직접 read/grep 해서 최근 작업 맥락을 가져와라. progress.md 가 stale 하면 이걸 우선 참고.\n\n"
    parts+="- path: ${LAST_ARCHIVED}\n"
    parts+="- size: $((asize / 1024))KB, ${alines} lines\n\n"
    parts+="권장 절차:\n"
    parts+="1) tail -n 200 \"${LAST_ARCHIVED}\" | jq -r 'select(.type==\"assistant\" or .type==\"user\") | .message.content' 로 마지막 turn 확인\n"
    parts+="2) 필요시 grep으로 특정 키워드 (이전 결정/작업 단위) 추적\n"
    parts+="3) 오래되지 않은(<7일) 결정·작업·미해결 작업이 있으면 progress.md 머리에 한두 줄 요약 추가\n\n"
fi

[ -z "$parts" ] && exit 0

# JSON 출력으로 additionalContext 주입
python3 <<EOF
import json
ctx = """$(printf '%s' "$parts" | python3 -c "import sys; sys.stdout.write(sys.stdin.read().replace(chr(92)+chr(110), chr(10)))")"""
out = {
    "hookSpecificOutput": {
        "hookEventName": "SessionStart",
        "additionalContext": "[세션 시작 맥락 — progress.md/history.md]\n\n" + ctx
    }
}
print(json.dumps(out, ensure_ascii=False))
EOF

exit 0
