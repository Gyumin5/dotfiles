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

# test_claude 세션에서만: 매일 브리핑 cron이 6일 이상 안 갱신됐으면 재등록 요청
if [ "$CWD" = "/home/gmoh/test_claude" ]; then
    MARK="$HOME/.claude/state/cron-briefing-test_claude.flag"
    need_register=0
    if [ ! -f "$MARK" ]; then
        need_register=1
    else
        age=$(( $(date +%s) - $(stat -c %Y "$MARK" 2>/dev/null || echo 0) ))
        # 6일 = 518400초. 7일 자동 만료 전에 재등록
        [ "$age" -gt 518400 ] && need_register=1
    fi
    if [ "$need_register" = "1" ]; then
        parts+="\n## 작업 요청\n\n매일 아침 Claude Code 개선 리서치 cron이 만료됐거나 등록되지 않음. CronCreate 도구로 다음 작업 등록해줘:\n- cron: 3 2 * * * (매일 02:03 KST)\n- recurring: true, durable: true\n- prompt: (0) ~/.local/share/claude/versions 최신 vs ~/.local/bin/claude 심링크 비교 → 신규 버전 있으면 알림 한 줄 (1) WebSearch 최근 7일 Claude Code/Agent SDK 신기능 3-5개 (2) codex-ask + gemini-ask --new --topic 병렬 평가 (3) 도입/보류/스킵 + 난이도 (4) 한국어 평문, 0번 알림은 맨앞 (5) mcp__plugin_telegram_telegram__reply로 chat_id 8689118207에 전송\n등록 완료 후 'touch $MARK' 실행해서 다음 6일간 재요청 안 뜨도록 표시.\n"
    fi
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
