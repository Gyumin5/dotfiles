#!/usr/bin/env python3
"""TODOBot 리스너 데몬 — 명령/버튼 처리.

- 전용 봇 토큰으로 long-poll getUpdates(운영 봇과 토큰 달라 충돌 없음).
- 명령: /start /today /list /help → 열린 todo 목록(항목 탭).
- 항목 탭(open:<id>) → 그 항목 메뉴: ✅완료 / 📝메모 / 💤+1일 / ←목록.
  · 완료는 '한 번 더 누르는' 2단계라 실수 방지(바로 사라지지 않음).
  · 메모는 force_reply 로 다음 입력 한 줄을 받아 todoctl note 로 기록.
  · 스누즈(💤+1일)는 마감을 하루 미룸(현재 마감 또는 오늘 기준 +1일).
- 모든 상태변경은 todoctl 경유(DB 직접 write 금지).
- 보안: 설정된 CHAT_ID 외 발신자는 무시.
- raion systemd --user 서비스(Restart=always)로 상주.
"""
import os
import sys
import time
import traceback
from datetime import date, datetime, timedelta

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from botlib import (  # noqa: E402
    CHAT_ID, WEBUI_URL, api, answer_callback, clear_snooze, edit_message,
    get_snooze_until, get_tags, get_todos, search_todos, send_message,
    set_snooze, todoctl,
)

PRIO_ORDER = {"high": 0, "med": 1, "low": 2}
PRIO_KO = {"high": "높음", "med": "보통", "low": "낮음"}
# 입력 대기 상태(in-memory, 재시작 시 소실 — 허용).
PENDING_MEMO = {}     # {chat_id: task_id} — 다음 텍스트를 메모로
PENDING_RESCHED = {}  # {chat_id: task_id} — 다음 텍스트를 새 마감일(YYYY-MM-DD)로


def _due(t):
    d = t.get("due_at")
    if not d:
        return None
    try:
        return date.fromisoformat(str(d)[:10])
    except ValueError:
        return None


def _safe_date(s):
    try:
        return date.fromisoformat(str(s)[:10])
    except (ValueError, TypeError):
        return None


def _parse_due_input(s):
    """'260609' 같은 yymmdd 숫자 입력 → '2026-06-09'. 이미 YYYY-MM-DD 면 그대로."""
    digits = "".join(ch for ch in (s or "") if ch.isdigit())
    if len(digits) == 6:
        return "20%s-%s-%s" % (digits[0:2], digits[2:4], digits[4:6])
    return (s or "").strip()[:10]


def _due_label(dd, today):
    if not dd:
        return ""
    delta = (dd - today).days
    if delta < 0:
        return " · ⚠️%d일지남" % (-delta)
    if delta == 0:
        return " · 🔴오늘"
    return " · %d일후" % delta


def _todo_map():
    return {str(t["task_id"]): t for t in get_todos(all_=True)}


def _tags_of(t):
    return [x for x in (t.get("tags") or "").split(",") if x]


# 긴급도(태그 기반): 긴급(0) > 중요(1) > 그 외(2). 옛 priority 대체.
URGENCY = {"긴급": 0, "중요": 1}


def _urg(t):
    return min((URGENCY[x] for x in _tags_of(t) if x in URGENCY), default=2)


def _umark(t):
    tg = _tags_of(t)
    return "🔴 " if "긴급" in tg else ("⭐ " if "중요" in tg else "")


def open_todos(tag=None):
    todos = [t for t in get_todos(all_=True) if t.get("status") != "done"]
    if tag:
        todos = [t for t in todos if tag in _tags_of(t)]
    todos.sort(key=lambda t: (_urg(t), _due(t) or date(9999, 1, 1)))
    return todos


def _list_buttons(t):
    return [{"text": "#%s %s" % (t["task_id"], t["title"][:24]),
             "callback_data": "open:%s" % t["task_id"]}]


def render_list(tag=None):
    todos = open_todos(tag)
    today = datetime.now().date()
    if not todos:
        msg = ("📋 🏷%s 진행 항목 없음." % tag) if tag else "📋 진행 중인 할 일 없음. 깔끔!"
        return (msg, [[{"text": "🏷 태그", "callback_data": "tagmenu"}],
                      [{"text": "🔄 새로고침", "callback_data": "list"},
                       {"text": "📋 사이트", "url": WEBUI_URL}]])
    head = (" · 🏷%s" % tag) if tag else ""
    lines = ["📋 진행 중 (%d건)%s — 항목 탭=완료/메모/미루기, 검색은 단어 입력" % (len(todos), head)]
    kb = [_list_buttons(t) for t in todos]
    for t in todos:
        ds = _due_label(_due(t), today)
        lines.append("• #%s %s%s%s" % (t["task_id"], _umark(t), t["title"], ds))
    foot = [{"text": "🏷 태그", "callback_data": "tagmenu"}]
    if tag:
        foot.append({"text": "✕ 필터 해제", "callback_data": "list"})
    kb.append(foot)
    kb.append([{"text": "🔄 새로고침", "callback_data": "list"},
               {"text": "📋 사이트", "url": WEBUI_URL}])
    return "\n".join(lines), kb


def render_search(query):
    """진행 중 항목에서 제목·메모·태그 전문검색 결과(탭하면 항목 상세)."""
    res = search_todos(query, all_=False)
    today = datetime.now().date()
    if not res:
        return ("🔍 '%s' 검색 결과 없음(진행 중).\n완료까지 보려면 사이트에서." % query,
                [[{"text": "← 목록", "callback_data": "list"},
                  {"text": "📋 사이트", "url": WEBUI_URL}]])
    lines = ["🔍 '%s' — %d건" % (query, len(res))]
    kb = []
    for t in res:
        ds = _due_label(_due(t), today)
        tg = _tags_of(t)
        tgs = (" 🏷%s" % ",".join(tg)) if tg else ""
        lines.append("• #%s %s%s%s%s" % (t["task_id"], _umark(t), t["title"], ds, tgs))
        kb.append(_list_buttons(t))
    kb.append([{"text": "← 목록", "callback_data": "list"},
               {"text": "📋 사이트", "url": WEBUI_URL}])
    return "\n".join(lines), kb


def render_tagmenu():
    """진행 중 항목 기준 태그 목록(누르면 그 태그로 필터)."""
    tags = [d for d in get_tags() if d.get("open", 0) > 0]
    if not tags:
        return ("🏷 진행 중 항목에 태그 없음.",
                [[{"text": "← 목록", "callback_data": "list"}]])
    lines = ["🏷 태그 — 누르면 그 태그만 보기"]
    kb, row = [], []
    for d in tags:
        row.append({"text": "#%s %d" % (d["tag"], d["open"]),
                    "callback_data": "tag:%s" % d["tag"]})
        if len(row) == 2:
            kb.append(row)
            row = []
    if row:
        kb.append(row)
    kb.append([{"text": "← 목록", "callback_data": "list"}])
    return "\n".join(lines), kb


def render_item(tid):
    """항목 상세 — 마감/우선순위/스누즈상태/메모(전체)/진행로그 + 액션 버튼."""
    t = _todo_map().get(str(tid))
    today = datetime.now().date()
    if not t or t.get("status") == "done":
        return None, None
    lines = ["📌 #%s %s%s" % (t["task_id"], _umark(t), t["title"])]
    dd = _due(t)
    lines.append("마감: %s" % (dd.isoformat() + _due_label(dd, today) if dd else "없음"))
    tg = _tags_of(t)
    lines.append("태그: %s" % (",".join(tg) if tg else "-"))
    lines.append("출처: %s" % (t.get("source") or "-"))
    su = get_snooze_until(tid)
    if su:
        sd = _safe_date(su)
        if sd and sd > today:
            lines.append("🔕 알림 미룸 → %s 부터 다시" % su)
    if t.get("notes"):
        lines.append("")
        lines.append("📄 설명:")
        lines.append(t["notes"])
    log = [e for e in (t.get("events") or []) if e.get("event") == "note"]
    if log:
        lines.append("")
        lines.append("🧷 진행 로그:")
        for e in log[-8:]:
            lines.append("  · %s %s" % (str(e.get("ts", ""))[5:10], e.get("detail", "")))
    kb = [
        [{"text": "✅ 완료 처리", "callback_data": "done:%s" % tid}],
        [{"text": "🔕 알림 미루기", "callback_data": "snoozemenu:%s" % tid},
         {"text": "📅 일정 조정", "callback_data": "reschedmenu:%s" % tid}],
        [{"text": "📝 메모 추가", "callback_data": "memo:%s" % tid}],
        [{"text": "← 목록", "callback_data": "list"}],
    ]
    return "\n".join(lines), kb


def render_snooze_menu(tid):
    """알림만 미룸 — 마감일은 그대로, 지정 기간 동안 리마인더만 끔."""
    t = _todo_map().get(str(tid))
    if not t or t.get("status") == "done":
        return None, None
    text = ("🔕 #%s 알림 미루기\n마감일은 그대로 두고 리마인더만 잠시 끔.\n\n"
            "언제 다시 알릴까?") % tid
    kb = [
        [{"text": "내일 다시", "callback_data": "snz:%s:1" % tid},
         {"text": "3일 뒤", "callback_data": "snz:%s:3" % tid},
         {"text": "다음주", "callback_data": "snz:%s:7" % tid}],
        [{"text": "알림 미룸 해제", "callback_data": "snzoff:%s" % tid}],
        [{"text": "← 항목", "callback_data": "open:%s" % tid}],
    ]
    return text, kb


def render_resched_menu(tid):
    """일정 조정 — 실제 마감일(due_at)을 변경(todoctl update --due)."""
    t = _todo_map().get(str(tid))
    if not t or t.get("status") == "done":
        return None, None
    today = datetime.now().date()
    dd = _due(t)
    cur = "없음" if not dd else "%s%s" % (dd.isoformat(), _due_label(dd, today))
    text = ("📅 #%s 일정 조정\n현재 마감: %s\n\n"
            "새 마감을 고르거나 직접 입력:") % (tid, cur)
    kb = [
        [{"text": "+1일", "callback_data": "resch:%s:1" % tid},
         {"text": "+3일", "callback_data": "resch:%s:3" % tid},
         {"text": "+1주", "callback_data": "resch:%s:7" % tid}],
        [{"text": "날짜 직접입력", "callback_data": "reschdate:%s" % tid}],
        [{"text": "← 항목", "callback_data": "open:%s" % tid}],
    ]
    return text, kb


def _edit_or_list(chat_id, msg_id, text, kb):
    if text:
        edit_message(chat_id, msg_id, text, kb)
    else:
        t_out, k_out = render_list()
        edit_message(chat_id, msg_id, t_out, k_out)


def do_done(tid):
    rc, _, err = todoctl(["done", str(tid)])
    return rc == 0, err


def do_snooze_alarm(tid, days):
    # 알림만 미룸: snooze_until = 오늘 + days. 마감일(due_at) 불변.
    until = (datetime.now().date() + timedelta(days=int(days))).isoformat()
    set_snooze(tid, until)
    return True, until


def do_reschedule(tid, days=None, new_due=None):
    # 실제 마감일 변경. days(상대) 또는 new_due(YYYY-MM-DD) 중 하나.
    if new_due is None:
        t = _todo_map().get(str(tid))
        base = datetime.now().date()
        if t:
            dd = _due(t)
            if dd and dd > base:
                base = dd
        new_due = (base + timedelta(days=int(days))).isoformat()
    if not _safe_date(new_due):
        return False, "날짜 형식 오류(YYYY-MM-DD)"
    rc, _, err = todoctl(["update", str(tid), "--due", new_due])
    return (rc == 0, new_due if rc == 0 else err)


def do_note(tid, text):
    rc, _, err = todoctl(["note", str(tid), text])
    return rc == 0, err


def handle_message(msg):
    chat_id = str(msg.get("chat", {}).get("id"))
    if chat_id != str(CHAT_ID):
        return
    text = (msg.get("text") or "").strip()
    cmd = text.split()[0].lower() if text else ""

    # 일정 조정 날짜 입력 대기.
    if chat_id in PENDING_RESCHED and not cmd.startswith("/"):
        tid = PENDING_RESCHED.pop(chat_id)
        if text:
            ok, info = do_reschedule(tid, new_due=_parse_due_input(text))
            if ok:
                send_message("📅 #%s 마감 → %s 로 변경됨" % (tid, info))
                it_text, it_kb = render_item(tid)
                send_message(*( (it_text, it_kb) if it_text else render_list()))
            else:
                send_message("일정 변경 실패: %s" % info)
        return

    # 메모 입력 대기 중이면(명령이 아니면) 그 텍스트를 메모로 기록.
    if chat_id in PENDING_MEMO and not cmd.startswith("/"):
        tid = PENDING_MEMO.pop(chat_id)
        if text:
            ok, err = do_note(tid, text)
            if ok:
                send_message("📝 #%s 메모 추가됨:\n%s" % (tid, text))
                it_text, it_kb = render_item(tid)
                send_message(*( (it_text, it_kb) if it_text else render_list()))
            else:
                send_message("메모 실패: %s" % err)
        return

    if cmd in ("/start", "/help"):
        send_message(
            "TODOBot — 업무 todo 조작.\n\n"
            "/today 또는 /list — 진행 중 목록\n"
            "🔍 검색: 그냥 단어를 보내면 제목·메모·태그에서 찾아줌(예: 라이센스)\n"
            "🏷 태그: 목록의 '태그' 버튼 → 태그별 보기\n"
            "   (사전 정의: 긴급·중요·개발·회사·인사·회의·개인, 그 외는 기타)\n"
            "목록에서 항목을 누르면 그 항목 메뉴가 열림:\n"
            "  ✅ 완료 처리 (목록에서 한 번에 안 사라지게 2단계)\n"
            "  📝 메모 추가 (누르면 입력칸 → 한 줄 적어 보내면 기록)\n"
            "  🔕 알림 미루기 / 📅 일정 조정\n\n"
            "마감 리마인더는 평일 09:00·13:30 자동 발송.",
            [[{"text": "📋 사이트 열기", "url": WEBUI_URL}]],
        )
        return
    if cmd.startswith("/"):
        PENDING_MEMO.pop(chat_id, None)  # 명령 들어오면 대기 취소
        PENDING_RESCHED.pop(chat_id, None)
        t_out, kb = render_list()
        send_message(t_out, kb)
        return
    # 명령이 아닌 일반 텍스트: 2글자 이상이면 검색, 아니면 목록.
    if text and len(text) >= 2:
        t_out, kb = render_search(text)
    else:
        t_out, kb = render_list()
    send_message(t_out, kb)


def handle_callback(cb):
    chat = cb.get("message", {}).get("chat", {})
    chat_id = str(chat.get("id"))
    if chat_id != str(CHAT_ID):
        api("answerCallbackQuery", {"callback_query_id": cb["id"]})
        return
    data = cb.get("data", "")
    cb_id = cb["id"]
    msg_id = cb["message"]["message_id"]

    if data == "list":
        answer_callback(cb_id, "목록")
        t_out, kb = render_list()
        edit_message(chat_id, msg_id, t_out, kb)
        return

    if data == "tagmenu":
        answer_callback(cb_id)
        t_out, kb = render_tagmenu()
        edit_message(chat_id, msg_id, t_out, kb)
        return

    if data.startswith("tag:"):
        tag = data.split(":", 1)[1]
        answer_callback(cb_id, "🏷 %s" % tag)
        t_out, kb = render_list(tag)
        edit_message(chat_id, msg_id, t_out, kb)
        return

    if data.startswith("open:"):
        tid = data.split(":", 1)[1]
        answer_callback(cb_id)
        it_text, it_kb = render_item(tid)
        if it_text:
            edit_message(chat_id, msg_id, it_text, it_kb)
        else:
            t_out, kb = render_list()
            edit_message(chat_id, msg_id, t_out, kb)
        return

    if data.startswith("done:"):
        tid = data.split(":", 1)[1]
        ok, err = do_done(tid)
        answer_callback(cb_id, "완료 처리됨 ✅" if ok else ("실패: %s" % err))
        t_out, kb = render_list()  # 완료 후 목록으로
        edit_message(chat_id, msg_id, t_out, kb)
        return

    if data.startswith("snoozemenu:"):
        tid = data.split(":", 1)[1]
        answer_callback(cb_id)
        s_text, s_kb = render_snooze_menu(tid)
        _edit_or_list(chat_id, msg_id, s_text, s_kb)
        return

    if data.startswith("snz:"):
        _, tid, days = data.split(":", 2)
        ok, info = do_snooze_alarm(tid, days)
        answer_callback(cb_id, "🔕 %s 부터 다시 알림" % info if ok else "실패")
        it_text, it_kb = render_item(tid)
        _edit_or_list(chat_id, msg_id, it_text, it_kb)
        return

    if data.startswith("snzoff:"):
        tid = data.split(":", 1)[1]
        clear_snooze(tid)
        answer_callback(cb_id, "알림 미룸 해제")
        it_text, it_kb = render_item(tid)
        _edit_or_list(chat_id, msg_id, it_text, it_kb)
        return

    if data.startswith("reschedmenu:"):
        tid = data.split(":", 1)[1]
        answer_callback(cb_id)
        r_text, r_kb = render_resched_menu(tid)
        _edit_or_list(chat_id, msg_id, r_text, r_kb)
        return

    if data.startswith("resch:"):
        _, tid, days = data.split(":", 2)
        ok, info = do_reschedule(tid, days=days)
        answer_callback(cb_id, "📅 마감 → %s" % info if ok else ("실패: %s" % info))
        it_text, it_kb = render_item(tid)
        _edit_or_list(chat_id, msg_id, it_text, it_kb)
        return

    if data.startswith("reschdate:"):
        tid = data.split(":", 1)[1]
        PENDING_RESCHED[chat_id] = tid
        answer_callback(cb_id, "날짜 입력 대기")
        api("sendMessage", {
            "chat_id": chat_id,
            "text": "📅 #%s 새 마감일을 yymmdd 숫자로 보내세요 (예: 260620). (취소: /today)" % tid,
            "reply_markup": {"force_reply": True,
                             "input_field_placeholder": "예: 260620"},
        })
        return

    if data.startswith("memo:"):
        tid = data.split(":", 1)[1]
        PENDING_MEMO[chat_id] = tid
        answer_callback(cb_id, "메모 입력 대기")
        api("sendMessage", {
            "chat_id": chat_id,
            "text": "📝 #%s 에 추가할 메모를 한 줄로 보내세요. (취소: /today)" % tid,
            "reply_markup": {"force_reply": True,
                             "input_field_placeholder": "진행 메모 한 줄"},
        })
        return

    answer_callback(cb_id)


def main():
    offset = None
    sys.stderr.write("todobot listener start (chat_id=%s)\n" % CHAT_ID)
    while True:
        try:
            params = {"timeout": 50}
            if offset is not None:
                params["offset"] = offset
            r = api("getUpdates", params, timeout=60)
            if not r.get("ok"):
                time.sleep(3)
                continue
            for u in r.get("result", []):
                offset = u["update_id"] + 1
                if "message" in u:
                    handle_message(u["message"])
                elif "callback_query" in u:
                    handle_callback(u["callback_query"])
        except Exception:  # noqa: BLE001
            sys.stderr.write(traceback.format_exc())
            time.sleep(3)


if __name__ == "__main__":
    main()
