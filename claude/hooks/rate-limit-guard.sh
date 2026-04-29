#!/bin/bash
# rate-limit-guard.sh: PreToolUse hook. 5h 토큰 사용량 ≥ 90% 도달 시 거의 모든 tool 차단.
#
# 사용자 결정 (2026-04-29):
# - 단순 정책 (option A): 5h 사용량 ≥ 90%면 차단
# - 모든 tool 차단 — 예측 못 한 폭증으로 세션 lockup 방지
# - 예외 (claude가 응답 못 하면 안 되므로): telegram reply/edit/react 만 허용
#
# 데이터 소스: ~/.claude/statusline_cache.json
# - statusline 렌더링할 때마다 갱신. 글로벌 계정 수치라 신선함.
#
# 차단 시:
# - exit 2 (PreToolUse decision: block)
# - 첫 차단 시 텔레그램으로 1회 알림 (cooldown 30분)
#
# 비차단 시 exit 0 (정상 진행)

set -uo pipefail

THRESHOLD=90
CACHE=~/.claude/statusline_cache.json
ALERT_FLAG=~/.claude/state/rate-limit-alerted.flag
COOLDOWN_SEC=$((30 * 60))
TELEGRAM_ENV=~/test_claude/.claude/telegram/.env

# 1. event JSON 읽기 (tool_name 추출용). 못 읽으면 안전하게 통과.
EVENT=$(cat 2>/dev/null || echo '{}')
TOOL=$(printf '%s' "$EVENT" | python3 -c 'import json,sys
try:
  d=json.loads(sys.stdin.read())
  print(d.get("tool_name") or d.get("tool") or "")
except: print("")' 2>/dev/null)

# 2. 허용 목록 — 차단 중에도 통과시킬 tools (claude가 텔레그램 응답 못 하면 사용자 무시 상태됨)
case "$TOOL" in
    mcp__plugin_telegram_telegram__reply|\
    mcp__plugin_telegram_telegram__edit_message|\
    mcp__plugin_telegram_telegram__react|\
    mcp__plugin_telegram_telegram__download_attachment)
        exit 0
        ;;
esac

# 3. 5h 사용량 체크
[ -f "$CACHE" ] || exit 0
PCT=$(python3 -c 'import json,sys
try:
  d=json.load(open("'"$CACHE"'"))
  rl=d.get("rate_limits",{}).get("five_hour",{})
  v=rl.get("used_percentage")
  if isinstance(v,(int,float)): print(int(v))
except: pass' 2>/dev/null)

[ -z "$PCT" ] && exit 0

if [ "$PCT" -lt "$THRESHOLD" ]; then
    exit 0
fi

# 4. 차단 — 텔레그램 1회 알림 (cooldown 30분)
mkdir -p "$(dirname "$ALERT_FLAG")"
need_alert=true
if [ -f "$ALERT_FLAG" ]; then
    age=$(( $(date +%s) - $(stat -c %Y "$ALERT_FLAG" 2>/dev/null || echo 0) ))
    [ "$age" -lt "$COOLDOWN_SEC" ] && need_alert=false
fi

if [ "$need_alert" = true ] && [ -f "$TELEGRAM_ENV" ]; then
    . "$TELEGRAM_ENV"
    if [ -n "${TELEGRAM_BOT_TOKEN:-}" ]; then
        msg="5h 토큰 사용량 ${PCT}% 도달. THRESHOLD=${THRESHOLD}% 가드 작동 — 모든 tool 차단 (telegram reply/edit/react/download만 허용). 5h 리셋까지 대기."
        curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
            --data-urlencode "chat_id=8689118207" \
            --data-urlencode "text=${msg}" >/dev/null 2>&1
        touch "$ALERT_FLAG"
    fi
fi

# 5. PreToolUse decision: block
echo "5h 토큰 사용량 ${PCT}% (>= ${THRESHOLD}%). 세션 lockup 방지를 위해 tool 차단 중. tool=${TOOL}" >&2
exit 2
