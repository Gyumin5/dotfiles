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

THRESHOLD_5H=90
THRESHOLD_7D=99
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

# 3. 5h / 7d 사용량 체크 (둘 중 하나라도 임계 초과면 차단)
[ -f "$CACHE" ] || exit 0
INFO=$(python3 -c '
import json, datetime
def fmt_reset(ts):
  tz_kst = datetime.timezone(datetime.timedelta(hours=9))
  reset = datetime.datetime.fromtimestamp(ts, datetime.timezone.utc).astimezone(tz_kst)
  now = datetime.datetime.now(tz_kst)
  remain = int((reset - now).total_seconds() // 60)
  h, m = divmod(max(remain, 0), 60)
  ts_str = reset.strftime("%Y-%m-%d %H:%M KST")
  rem_str = "{}h{:02d}m".format(h, m)
  return ts_str + "|" + rem_str
try:
  d = json.load(open("'"$CACHE"'"))
  rl = d.get("rate_limits", {})
  fh = rl.get("five_hour", {}); sd = rl.get("seven_day", {})
  fh_pct = fh.get("used_percentage"); sd_pct = sd.get("used_percentage")
  fh_pct = int(fh_pct) if isinstance(fh_pct, (int, float)) else -1
  sd_pct = int(sd_pct) if isinstance(sd_pct, (int, float)) else -1
  fh_reset = fmt_reset(fh.get("resets_at")) if fh.get("resets_at") else "|"
  sd_reset = fmt_reset(sd.get("resets_at")) if sd.get("resets_at") else "|"
  print("{}|{}|{}|{}".format(fh_pct, sd_pct, fh_reset, sd_reset))
except: print("-1|-1|||")' 2>/dev/null)

PCT_5H=$(echo "$INFO" | cut -d'|' -f1)
PCT_7D=$(echo "$INFO" | cut -d'|' -f2)
RESET_5H_AT=$(echo "$INFO" | cut -d'|' -f3)
RESET_5H_REMAIN=$(echo "$INFO" | cut -d'|' -f4)
RESET_7D_AT=$(echo "$INFO" | cut -d'|' -f5)
RESET_7D_REMAIN=$(echo "$INFO" | cut -d'|' -f6)

# 차단 사유 결정
TRIGGER=""
if [ "$PCT_5H" -ge "$THRESHOLD_5H" ] 2>/dev/null; then
    TRIGGER="5h ${PCT_5H}% (>= ${THRESHOLD_5H}%) — 풀리는 시각 ${RESET_5H_AT} (앞으로 ${RESET_5H_REMAIN})"
fi
if [ "$PCT_7D" -ge "$THRESHOLD_7D" ] 2>/dev/null; then
    if [ -n "$TRIGGER" ]; then
        TRIGGER="$TRIGGER + 7d ${PCT_7D}% (>= ${THRESHOLD_7D}%) — 풀리는 시각 ${RESET_7D_AT} (앞으로 ${RESET_7D_REMAIN})"
    else
        TRIGGER="7d ${PCT_7D}% (>= ${THRESHOLD_7D}%) — 풀리는 시각 ${RESET_7D_AT} (앞으로 ${RESET_7D_REMAIN})"
    fi
fi

[ -z "$TRIGGER" ] && exit 0

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
        msg="rate-limit-guard 작동. 모든 tool 차단 중 (telegram reply/edit/react/download만 허용).
사유: ${TRIGGER}
첫 차단 tool: ${TOOL:-?}"
        curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
            --data-urlencode "chat_id=8689118207" \
            --data-urlencode "text=${msg}" >/dev/null 2>&1
        touch "$ALERT_FLAG"
    fi
fi

# 5. PreToolUse decision: block
echo "rate-limit-guard: ${TRIGGER}. tool=${TOOL} 차단" >&2
exit 2
