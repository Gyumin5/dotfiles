#!/bin/bash
# session-start-context: SessionStart 훅. 프로젝트 cwd의 progress.md + history.md 내용을
# claude에게 additionalContext로 주입해서 새 세션이 즉시 작업 맥락 파악.

set -uo pipefail

INPUT=$(cat 2>/dev/null || echo '{}')
CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
[ -z "$CWD" ] && CWD="$PWD"

PROG="$CWD/progress.md"
HIST="$CWD/history.md"

parts=""
if [ -f "$PROG" ]; then
    # 너무 길면 자름 (최대 8000 chars)
    pcontent=$(head -c 8000 "$PROG")
    parts+="## progress.md (현재 진행 상황)\n\n${pcontent}\n\n"
fi
if [ -f "$HIST" ]; then
    hcontent=$(tail -c 8000 "$HIST")
    parts+="## history.md (최근 결정 로그)\n\n${hcontent}\n"
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
