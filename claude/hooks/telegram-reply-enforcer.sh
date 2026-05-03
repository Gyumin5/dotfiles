#!/bin/bash
# telegram-reply-enforcer.sh: Stop hook.
# 현재 턴에 텔레그램 채널 메시지가 들어왔으면 종료 전에 mcp reply tool 호출 1회 이상이 있어야 함.
# 누락 시 exit 2 + decision feedback으로 종료를 차단해서 모델이 reply를 강제로 호출하게 만든다.
#
# 동작:
#   - Stop hook event JSON 읽기 (stop_hook_active 체크해서 무한루프 방지)
#   - transcript jsonl 파싱: 마지막 assistant turn 시작 이후 메시지들 검사
#   - user 메시지 중 <channel source="plugin:telegram:telegram"> 포함 여부
#   - assistant 메시지 중 mcp__plugin_telegram_telegram__reply tool_use 여부
#   - 채널 있는데 reply 없으면 차단

set -uo pipefail

EVENT=$(cat 2>/dev/null || echo '{}')

DECISION=$(printf '%s' "$EVENT" | python3 - <<'PYEOF' 2>/dev/null
import json, sys, os

try:
    e = json.loads(sys.stdin.read())
except Exception:
    print("PASS")
    sys.exit(0)

# 무한루프 방지: 이미 한 번 차단당했으면 통과
if e.get("stop_hook_active"):
    print("PASS")
    sys.exit(0)

tp = e.get("transcript_path")
if not tp or not os.path.exists(tp):
    print("PASS")
    sys.exit(0)

# transcript 끝에서부터 거슬러: 마지막 assistant turn의 시작점 찾고 (= 직전 user 이후)
# 그 user~end 구간 안에 channel 마커 / reply tool_use 카운트.
lines = []
try:
    with open(tp, "rb") as f:
        # 파일 너무 크면 끝 1MB만
        f.seek(0, 2)
        size = f.tell()
        f.seek(max(0, size - 1_000_000))
        raw = f.read().decode("utf-8", errors="ignore")
        lines = raw.splitlines()
except Exception:
    print("PASS")
    sys.exit(0)

# 끝에서부터 가장 최근 user 메시지 인덱스 찾기. 그 인덱스 이후를 "현재 턴"으로 간주.
last_user_idx = -1
parsed = []
for line in lines:
    try:
        parsed.append(json.loads(line))
    except Exception:
        parsed.append(None)

for i in range(len(parsed) - 1, -1, -1):
    d = parsed[i]
    if not d: continue
    if d.get("type") == "user":
        last_user_idx = i
        break

if last_user_idx < 0:
    print("PASS")
    sys.exit(0)

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
                    if name == "mcp__plugin_telegram_telegram__reply":
                        has_reply = True
                    elif name in ("mcp__plugin_telegram_telegram__edit_message",
                                   "mcp__plugin_telegram_telegram__react"):
                        # edit/react만으로는 알림 안 가지만 사용자 의도 표시는 됨 → 통과 허용
                        has_reply = True

if has_channel and not has_reply:
    print("BLOCK")
else:
    print("PASS")
PYEOF
)

if [ "$DECISION" = "BLOCK" ]; then
    cat <<'EOF' >&2
[telegram-reply-enforcer] 텔레그램 채널 메시지에 답할 때는 mcp__plugin_telegram_telegram__reply 도구 호출이 반드시 필요합니다. 텍스트만 출력하면 사용자는 읽을 수 없습니다. 답변 내용을 reply 도구로 다시 보내고 종료하세요.
EOF
    exit 2
fi
exit 0
