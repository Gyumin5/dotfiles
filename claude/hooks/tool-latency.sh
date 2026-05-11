#!/bin/bash
# tool-latency: PostToolUse 훅. tool_name + duration_ms를 로그.
# 5초 이상 오래 걸린 호출은 stderr로 경고 (Claude transcript에 표시).

INPUT=$(cat 2>/dev/null || echo '{}')
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
DUR=$(echo "$INPUT" | jq -r '.duration_ms // empty' 2>/dev/null)
[ -z "$TOOL" ] && exit 0
[ -z "$DUR" ] && exit 0

LOG="$HOME/.claude/logs/tool-latency.log"
mkdir -p "$(dirname "$LOG")"

# Bash인 경우 명령 첫 토큰도 기록
EXTRA=""
if [ "$TOOL" = "Bash" ]; then
    cmd=$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null | head -c 80 | tr '\n' ' ')
    EXTRA=" cmd=\"$cmd\""
fi

echo "[$(date -Iseconds)] tool=$TOOL dur_ms=$DUR$EXTRA" >> "$LOG"

# 5000ms 이상이면 transcript 경고
if [ "$DUR" -gt 5000 ] 2>/dev/null; then
    echo "[tool-latency] $TOOL took ${DUR}ms (>5s)" >&2
fi

# Bash foreground 60s+ 누적 telemetry + 3회 누적 시 컨트롤봇 1회 알림
# (자율루프 자식이 long foreground tool 점유하는 사고 조기 경고).
# run_in_background=true 호출은 즉시 반환이라 60s 임계 안 걸림 → 자연스럽게 제외.
if [ "$TOOL" = "Bash" ] && [ "$DUR" -gt 60000 ] 2>/dev/null; then
    SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null)
    CWD=$(echo "$INPUT" | jq -r '.cwd // ""' 2>/dev/null)
    JSONL="$HOME/.claude/telemetry/bash-latency.jsonl"
    mkdir -p "$(dirname "$JSONL")"
    cmd_hash=$(echo -n "$cmd" | sha1sum | cut -c1-12)
    jq -nc \
        --arg ts "$(date -Iseconds)" \
        --arg sid "$SESSION_ID" \
        --arg cwd "$CWD" \
        --arg cmd "$cmd" \
        --arg ch "$cmd_hash" \
        --argjson dur "$DUR" \
        '{ts:$ts, session_id:$sid, cwd:$cwd, cmd_prefix:$cmd, cmd_hash:$ch, duration_ms:$dur}' \
        >> "$JSONL" 2>/dev/null

    # 동일 session_id 누적 카운트 (7일 이내). 3회 누적 시 컨트롤봇 1회 알림.
    STATE_DIR="$HOME/.claude/state/bash-latency"
    mkdir -p "$STATE_DIR"
    COUNT_FILE="$STATE_DIR/count-${SESSION_ID}"
    ALERT_FLAG="$STATE_DIR/alert-${SESSION_ID}"
    count=$(cat "$COUNT_FILE" 2>/dev/null || echo 0)
    count=$((count + 1))
    echo "$count" > "$COUNT_FILE"
    if [ "$count" -ge 3 ] && [ ! -f "$ALERT_FLAG" ]; then
        ENV_FILE="$HOME/.claude/control-bot/.env"
        if [ -f "$ENV_FILE" ]; then
            TOKEN=$(grep '^CONTROL_BOT_TOKEN=' "$ENV_FILE" | head -1 | cut -d= -f2- | tr -d '"'"'"' ')
            CHAT_ID="8689118207"
            if [ -n "$TOKEN" ]; then
                # systemd cgroup 에서 claude-<name>.service 추출 (cwd basename 보다 정확).
                unit=$(grep -oE 'claude-[a-z0-9_-]+\.service' /proc/self/cgroup 2>/dev/null | head -1)
                if [ -n "$unit" ]; then
                    name="${unit#claude-}"; name="${name%.service}"
                else
                    name=$(basename "$CWD" 2>/dev/null)
                fi
                text="[bash-latency] ${name:-unknown} 세션에서 foreground bash 60s+ 호출 ${count}회 누적. 자율루프 안이면 run_in_background=true 점검. cwd=$CWD 마지막 명령: ${cmd:0:80}"
                curl -sS --max-time 5 \
                    -d "chat_id=$CHAT_ID" \
                    --data-urlencode "text=$text" \
                    "https://api.telegram.org/bot$TOKEN/sendMessage" >/dev/null 2>&1
                touch "$ALERT_FLAG"
            fi
        fi
    fi
fi
exit 0
