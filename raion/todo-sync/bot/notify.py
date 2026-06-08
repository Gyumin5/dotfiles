#!/usr/bin/env python3
"""마감 리마인더 — 지연/오늘/임박(3일내) todo 요약을 TODOBot 으로 발송.

- 읽기 전용: todoctl json 만 호출, DB 직접 write 안 함(단일 writer 원칙).
- 마감 임박/지연 항목이 없으면 조용히 종료(스팸 방지). --force 면 비어도 발송.
- due_at 은 날짜(YYYY-MM-DD) 단위 → 일(day) 기준 버킷.
- KST: 시스템 timezone(Asia/Seoul) 기준 datetime.now(). 테스트용 TODO_FAKE_TODAY 지원.
- systemd --user 타이머로 평일 아침 실행.
"""
import os
import sys
from datetime import date, datetime

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from botlib import (  # noqa: E402
    get_todos, send_message, WEBUI_URL, load_snooze, save_snooze,
)

SOON_DAYS = 3


def today():
    fake = os.environ.get("TODO_FAKE_TODAY")
    if fake:
        return date.fromisoformat(fake)
    return datetime.now().date()


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


def build_digest(todos, ref):
    overdue, due_today, soon = [], [], []
    snooze = load_snooze()
    # 만료된 스누즈 정리(과거 날짜).
    pruned = {k: v for k, v in snooze.items()
              if _safe_date(v) and _safe_date(v) > ref}
    if pruned != snooze:
        save_snooze(pruned)
        snooze = pruned
    for t in todos:
        if t.get("status") == "done":
            continue
        # 알림 스누즈: 지정 날짜 전까지는 리마인더 생략(마감일과 무관).
        su = snooze.get(str(t["task_id"]))
        if su and _safe_date(su) and _safe_date(su) > ref:
            continue
        dd = _due(t)
        if dd is None:
            continue
        delta = (dd - ref).days
        if delta < 0:
            overdue.append((t, delta))
        elif delta == 0:
            due_today.append((t, delta))
        elif delta <= SOON_DAYS:
            soon.append((t, delta))
    if not (overdue or due_today or soon):
        return None

    def fmt(t):
        star = "★ " if t.get("priority") == "high" else ""
        return "#%s %s%s" % (t["task_id"], star, t["title"])

    lines = ["🗓 업무 todo 리마인더 (%s)" % ref.isoformat()]
    if overdue:
        lines.append("")
        lines.append("⚠️ 지연")
        for t, dl in sorted(overdue, key=lambda x: x[1]):
            lines.append("  • %s — %d일 지남" % (fmt(t), -dl))
    if due_today:
        lines.append("")
        lines.append("🔴 오늘 마감")
        for t, _ in due_today:
            lines.append("  • %s" % fmt(t))
    if soon:
        lines.append("")
        lines.append("🟡 임박 (%d일 내)" % SOON_DAYS)
        for t, dl in sorted(soon, key=lambda x: x[1]):
            lines.append("  • %s — %d일 후" % (fmt(t), dl))
    return "\n".join(lines)


def main():
    force = "--force" in sys.argv
    todos = get_todos(all_=True)
    ref = today()
    text = build_digest(todos, ref)
    if text is None:
        if force:
            text = "🗓 업무 todo (%s)\n마감 임박/지연 항목 없음. 깔끔!" % ref.isoformat()
        else:
            print("nothing due/overdue/soon — silent")
            return
    buttons = [[{"text": "📋 사이트 열기", "url": WEBUI_URL}]]
    r = send_message(text, buttons)
    print("sent ok=%s" % r.get("ok"), r.get("error", ""))


if __name__ == "__main__":
    main()
