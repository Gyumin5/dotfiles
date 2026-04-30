#!/bin/bash
# rate-limit-prompt-guard.sh: UserPromptSubmit hook.
#
# 기능:
# 1. rate-limit이 차단 상태면 사용자 prompt를 큐에 저장하고 prompt 처리 자체를 차단(exit 2).
#    - 클로드 모델 호출 안 됨 → 토큰 0
#    - 텔레그램으로 "큐잉됨 (N번째)" 알림 1회 (cooldown 5분)
# 2. 차단 풀린 상태에서 큐 파일이 있으면 → additionalContext에 큐 내용 prepend → exit 0으로 정상 진행.
#    - 클로드가 큐된 메시지들 + 현재 prompt를 같이 받아서 차례로 답변.
#    - 큐 파일 비움.
# 3. 특수 trigger 메시지 ("trigger:queue-flush") 감지 시 큐만 flush하고 trigger 자체는 사용자에 노출 X.
#    - userbot이 보내는 깨우기 신호용. (userbot 미도입 상태에서는 사용자가 아무 메시지나 보내면 큐 flush됨.)

set -uo pipefail

THRESHOLD_5H=90
THRESHOLD_7D=99
CACHE=~/.claude/statusline_cache.json
QUEUE_DIR=~/.claude/state/rate-limit-queue
ALERT_FLAG_PREFIX=~/.claude/state/rate-limit-prompt-alert
COOLDOWN_SEC=300
FALLBACK_TELEGRAM_ENV=~/test_claude/.claude/telegram/.env

mkdir -p "$QUEUE_DIR"

# 1. event JSON 읽기
EVENT=$(cat 2>/dev/null || echo '{}')
USER_PROMPT=$(printf '%s' "$EVENT" | python3 -c 'import json,sys
try:
  d=json.loads(sys.stdin.read())
  print(d.get("prompt") or d.get("user_prompt") or "")
except: print("")' 2>/dev/null)
CWD=$(printf '%s' "$EVENT" | python3 -c 'import json,sys
try:
  d=json.loads(sys.stdin.read())
  print(d.get("cwd") or "")
except: print("")' 2>/dev/null)
[ -z "$CWD" ] && CWD="$PWD"
PROJ=$(basename "$CWD")
QUEUE_FILE="$QUEUE_DIR/${PROJ}.jsonl"
CWD_FILE="$QUEUE_DIR/${PROJ}.cwd"
# 프로젝트별 telegram bot로 라우팅. recovery script가 큐 비어도 cwd 알 수 있게 매번 갱신.
echo "$CWD" > "$CWD_FILE" 2>/dev/null
PROJECT_TELEGRAM_ENV="${CWD}/.claude/telegram/.env"
if [ -f "$PROJECT_TELEGRAM_ENV" ]; then
    TELEGRAM_ENV="$PROJECT_TELEGRAM_ENV"
else
    TELEGRAM_ENV="$FALLBACK_TELEGRAM_ENV"
fi

# 1.5. bypass flag — 사용자가 임시로 90% 가드 무시하고 싶을 때
BYPASS_GLOBAL=~/.claude/state/rate-limit-bypass.flag
BYPASS_PROJ=~/.claude/state/rate-limit-bypass-${PROJ}.flag

if [ -f "$BYPASS_GLOBAL" ] || [ -f "$BYPASS_PROJ" ]; then
    exit 0
fi

# 2. rate-limits 조회
[ -f "$CACHE" ] || exit 0
# used_percentage 외에 resets_at 으로 시간 fallback. now > resets_at 이면 이미 리셋.
INFO=$(python3 -c '
import json, time
try:
  d = json.load(open("'"$CACHE"'"))
  rl = d.get("rate_limits", {})
  fh = rl.get("five_hour", {}); sd = rl.get("seven_day", {})
  now = time.time()
  def effective(window):
    rt = window.get("resets_at")
    if rt and now > rt:
      return 0
    v = window.get("used_percentage")
    return int(v) if isinstance(v, (int, float)) else -1
  print("{}|{}".format(effective(fh), effective(sd)))
except: print("-1|-1")' 2>/dev/null)
PCT_5H=$(echo "$INFO" | cut -d'|' -f1)
PCT_7D=$(echo "$INFO" | cut -d'|' -f2)

BLOCKED=false
if [ "$PCT_5H" -ge "$THRESHOLD_5H" ] 2>/dev/null; then BLOCKED=true; fi
if [ "$PCT_7D" -ge "$THRESHOLD_7D" ] 2>/dev/null; then BLOCKED=true; fi

# 3. 차단 상태: 큐에 저장하고 prompt 차단
if [ "$BLOCKED" = true ]; then
    # trigger 메시지면 그냥 묵살 (큐 처리는 차단 풀린 다음 분기에서)
    if [ "$USER_PROMPT" = "trigger:queue-flush" ]; then
        echo "rate-limit-guard: trigger 무시 (아직 차단 중)" >&2
        exit 2
    fi

    # 큐에 append (jsonl: ts, prompt)
    python3 -c '
import json, sys, datetime
ts = datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=9))).isoformat(timespec="seconds")
rec = {"ts": ts, "prompt": sys.argv[1]}
with open(sys.argv[2], "a") as f:
    f.write(json.dumps(rec, ensure_ascii=False) + "\n")
' "$USER_PROMPT" "$QUEUE_FILE" 2>/dev/null

    # 큐 길이 계산
    QUEUE_LEN=$(wc -l < "$QUEUE_FILE" 2>/dev/null || echo 0)

    # 텔레그램 알림 (5분 쿨다운, 프로젝트별)
    ALERT_FLAG="${ALERT_FLAG_PREFIX}-${PROJ}.flag"
    need_alert=true
    if [ -f "$ALERT_FLAG" ]; then
        age=$(( $(date +%s) - $(stat -c %Y "$ALERT_FLAG" 2>/dev/null || echo 0) ))
        [ "$age" -lt "$COOLDOWN_SEC" ] && need_alert=false
    fi

    if [ "$need_alert" = true ] && [ -f "$TELEGRAM_ENV" ]; then
        . "$TELEGRAM_ENV"
        if [ -n "${TELEGRAM_BOT_TOKEN:-}" ]; then
            msg="rate-limit 차단 중. 메시지 큐잉됨 — 현재 큐 ${QUEUE_LEN}개. 풀리면 자동 처리."
            curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
                --data-urlencode "chat_id=8689118207" \
                --data-urlencode "text=${msg}" >/dev/null 2>&1
            touch "$ALERT_FLAG"
        fi
    fi

    echo "rate-limit-guard: 차단 중. 메시지 큐잉됨 (queue=${QUEUE_LEN}). 풀리면 처리됨." >&2
    exit 2
fi

# 4. 차단 해제 상태 + 큐 파일 존재: 큐 prepend + 큐 비우기
if [ -s "$QUEUE_FILE" ]; then
    QUEUE_LEN=$(wc -l < "$QUEUE_FILE" 2>/dev/null || echo 0)
    QUEUE_CONTENT=$(python3 -c '
import json, sys
items = []
for i, line in enumerate(open(sys.argv[1]), 1):
    try:
        d = json.loads(line)
        items.append("[큐{}] ({}) {}".format(i, d.get("ts", ""), d.get("prompt", "")))
    except: pass
print("\n".join(items))
' "$QUEUE_FILE" 2>/dev/null)

    # trigger 메시지면 noise 없이 큐만 처리 — 사용자에게 trigger 자체는 안 보이게
    if [ "$USER_PROMPT" = "trigger:queue-flush" ]; then
        cat <<EOF
[rate-limit 해제 — 큐 ${QUEUE_LEN}개 자동 flush]

다음 메시지들이 차단 중에 큐잉됐었음. 시간 순서대로 답변해라:

${QUEUE_CONTENT}

(이 trigger 메시지는 userbot이 깨우기 위해 보낸 것. 실제 사용자 새 입력은 없음.)
EOF
    else
        cat <<EOF
[rate-limit 해제 — 큐 ${QUEUE_LEN}개 자동 flush]

다음 메시지들이 차단 중에 큐잉됐었음:

${QUEUE_CONTENT}

위 큐된 메시지들에 먼저 답한 뒤, 사용자의 현재 메시지에도 답하라.
EOF
    fi

    # 큐 비우기 + alert flag 삭제
    > "$QUEUE_FILE"
    rm -f "${ALERT_FLAG_PREFIX}-${PROJ}.flag"
fi

exit 0
