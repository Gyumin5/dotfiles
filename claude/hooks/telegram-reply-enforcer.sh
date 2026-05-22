#!/bin/bash
# telegram-reply-enforcer.sh: Stop hook.
# 현재 턴에 텔레그램 채널 메시지가 들어왔으면 종료 전에 mcp reply tool 호출 1회 이상이 있어야 함.
# 누락 시 exit 2 + decision feedback으로 종료를 차단해서 모델이 reply를 강제로 호출하게 만든다.

set -uo pipefail

# 자동 작업(claude -p 등)은 사용자 세션 아님 → reply 강제 스킵.
[ "${CLAUDE_AUTOMATED:-0}" = "1" ] && exit 0

EVENT=$(cat 2>/dev/null || echo '{}')

# Python 스크립트는 stdin 충돌 피하려고 환경변수로 EVENT 전달.
DECISION=$(EVENT_JSON="$EVENT" python3 <<'PYEOF' 2>/dev/null
import json, sys, os

try:
    e = json.loads(os.environ.get("EVENT_JSON", "{}"))
except Exception:
    print("PASS"); sys.exit(0)

if e.get("stop_hook_active"):
    print("PASS"); sys.exit(0)

tp = e.get("transcript_path")
if not tp or not os.path.exists(tp):
    print("PASS"); sys.exit(0)

try:
    with open(tp, "rb") as f:
        f.seek(0, 2)
        size = f.tell()
        f.seek(max(0, size - 1_000_000))
        raw = f.read().decode("utf-8", errors="ignore")
        lines = raw.splitlines()
except Exception:
    print("PASS"); sys.exit(0)

parsed = []
for line in lines:
    try: parsed.append(json.loads(line))
    except Exception: parsed.append(None)

def is_real_user(d):
    """type=user 중 tool_result(첫 항목에 tool_use_id 키) 제외하고 실제 입력만."""
    if not d or d.get("type") != "user":
        return False
    msg = d.get("message", {}) or {}
    c = msg.get("content")
    if isinstance(c, str):
        return True
    if isinstance(c, list):
        for it in c:
            if isinstance(it, dict):
                if it.get("type") == "tool_result" or "tool_use_id" in it:
                    return False
                if it.get("type") == "text" or "text" in it:
                    return True
        return True
    return False

last_user_idx = -1
for i in range(len(parsed) - 1, -1, -1):
    if is_real_user(parsed[i]):
        last_user_idx = i
        break

if last_user_idx < 0:
    print("PASS"); sys.exit(0)

current_turn = [d for d in parsed[last_user_idx:] if d]

has_channel = False
has_reply = False
for d in current_turn:
    t = d.get("type")
    msg = d.get("message", {}) or {}
    if t == "user":
        c = msg.get("content", "")
        if isinstance(c, str) and 'source="plugin:telegram:telegram"' in c:
            has_channel = True
        elif isinstance(c, list):
            for it in c:
                if isinstance(it, dict):
                    txt = it.get("text") or it.get("content") or ""
                    if isinstance(txt, str) and 'source="plugin:telegram:telegram"' in txt:
                        has_channel = True
                        break
    elif t == "assistant":
        c = msg.get("content", [])
        if isinstance(c, list):
            for it in c:
                if isinstance(it, dict) and it.get("type") == "tool_use":
                    name = it.get("name", "")
                    if name in ("mcp__plugin_telegram_telegram__reply",
                                "mcp__plugin_telegram_telegram__edit_message",
                                "mcp__plugin_telegram_telegram__react"):
                        has_reply = True

# 5xx (예: 529 Overloaded) 으로 끝난 턴은 BLOCK 금지 — retry dead loop 방지.
import re
api5xx = False
for d in reversed(current_turn):
    if d.get("type") != "assistant":
        continue
    c = (d.get("message", {}) or {}).get("content", [])
    if isinstance(c, list):
        for it in c:
            if isinstance(it, dict) and it.get("type") == "text":
                if re.search(r"API Error:\s*5\d\d", it.get("text", "")):
                    api5xx = True
                    break
    if api5xx:
        break
if api5xx:
    print("PASS"); sys.exit(0)

print("BLOCK" if (has_channel and not has_reply) else "PASS")
PYEOF
)

if [ "$DECISION" = "BLOCK" ]; then
    cat <<'EOF' >&2
[telegram-reply-enforcer] 텔레그램 채널 메시지에 답할 때는 mcp__plugin_telegram_telegram__reply 도구 호출이 반드시 필요합니다. 텍스트만 출력하면 사용자는 읽을 수 없습니다. 답변 내용을 reply 도구로 다시 보내고 종료하세요.
EOF
    exit 2
fi
exit 0
