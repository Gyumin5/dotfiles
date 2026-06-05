#!/usr/bin/env python3
"""
todoctl — 개인 업무 todo 단일 writer CLI.
진실원본 = SQLite(todo.db, WAL). 모든 쓰기는 이 CLI를 통해서만.
todo.md 는 매 변경 후 DB에서 자동 재생성되는 읽기용 뷰(원본 아님).

명령:
  init                              스키마 생성
  add "제목" [--due YYYY-MM-DD] [--prio high|med|low] [--source ...] [--notes ...]
  done <id> | reopen <id> | rm <id>
  update <id> [--title ..] [--due ..] [--prio ..] [--status todo|doing|done] [--notes ..]
  note <id> "진행 로그 한 줄"        로그 append
  list [--all]                      진행중(기본) 또는 전체
  show <id>                         상세
  export                            todo.md 재생성
  json [--all]                      기계용 JSON 출력

설계: ai-debate run-20260604T065446Z (단일 진실원본 SQLite + 단일 writer).
"""
import argparse
import json
import os
import sqlite3
import sys
from datetime import datetime
from zoneinfo import ZoneInfo

HERE = os.path.dirname(os.path.abspath(__file__))
DB = os.path.join(HERE, "todo.db")
MD = "/home/gmoh/raion/todo.md"
KST = ZoneInfo("Asia/Seoul")
PRIO_ORDER = {"high": 0, "med": 1, "low": 2}


def now_kst():
    return datetime.now(KST).strftime("%Y-%m-%d %H:%M KST")


def conn():
    c = sqlite3.connect(DB, timeout=10)
    c.execute("PRAGMA journal_mode=WAL")
    c.execute("PRAGMA busy_timeout=5000")
    c.row_factory = sqlite3.Row
    return c


def init(c):
    c.executescript(
        """
        CREATE TABLE IF NOT EXISTS tasks(
          task_id INTEGER PRIMARY KEY AUTOINCREMENT,
          title TEXT NOT NULL,
          status TEXT NOT NULL DEFAULT 'todo',   -- todo|doing|done
          due_at TEXT,
          priority TEXT NOT NULL DEFAULT 'med',   -- high|med|low
          source TEXT,
          notes TEXT,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          completed_at TEXT,
          version INTEGER NOT NULL DEFAULT 1
        );
        CREATE TABLE IF NOT EXISTS task_events(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          task_id INTEGER NOT NULL,
          event TEXT NOT NULL,
          detail TEXT,
          ts TEXT NOT NULL
        );
        """
    )
    c.commit()


def _event(c, tid, event, detail=""):
    c.execute(
        "INSERT INTO task_events(task_id,event,detail,ts) VALUES(?,?,?,?)",
        (tid, event, detail, now_kst()),
    )


def _bump(c, tid):
    c.execute(
        "UPDATE tasks SET updated_at=?, version=version+1 WHERE task_id=?",
        (now_kst(), tid),
    )


def add(c, a):
    t = now_kst()
    cur = c.execute(
        "INSERT INTO tasks(title,status,due_at,priority,source,notes,created_at,updated_at)"
        " VALUES(?,?,?,?,?,?,?,?)",
        (a.title, "todo", a.due, a.prio, a.source, a.notes, t, t),
    )
    tid = cur.lastrowid
    _event(c, tid, "created", a.title)
    c.commit()
    print(f"added #{tid}: {a.title}")


def _set_status(c, tid, status):
    row = c.execute("SELECT status FROM tasks WHERE task_id=?", (tid,)).fetchone()
    if not row:
        sys.exit(f"no such task #{tid}")
    comp = now_kst() if status == "done" else None
    c.execute(
        "UPDATE tasks SET status=?, completed_at=? WHERE task_id=?",
        (status, comp, tid),
    )
    _event(c, tid, status)
    _bump(c, tid)
    c.commit()


def done(c, a):
    _set_status(c, a.id, "done")
    print(f"done #{a.id}")


def reopen(c, a):
    _set_status(c, a.id, "todo")
    print(f"reopened #{a.id}")


def rm(c, a):
    c.execute("DELETE FROM tasks WHERE task_id=?", (a.id,))
    _event(c, a.id, "deleted")
    c.commit()
    print(f"removed #{a.id}")


def update(c, a):
    row = c.execute("SELECT * FROM tasks WHERE task_id=?", (a.id,)).fetchone()
    if not row:
        sys.exit(f"no such task #{a.id}")
    fields = {}
    if a.title is not None:
        fields["title"] = a.title
    if a.due is not None:
        fields["due_at"] = a.due
    if a.prio is not None:
        fields["priority"] = a.prio
    if a.status is not None:
        fields["status"] = a.status
        fields["completed_at"] = now_kst() if a.status == "done" else None
    if a.notes is not None:
        fields["notes"] = a.notes
    if not fields:
        sys.exit("nothing to update")
    sets = ",".join(f"{k}=?" for k in fields)
    c.execute(f"UPDATE tasks SET {sets} WHERE task_id=?", (*fields.values(), a.id))
    _event(c, a.id, "updated", ",".join(fields))
    _bump(c, a.id)
    c.commit()
    print(f"updated #{a.id}: {','.join(fields)}")


def note(c, a):
    row = c.execute("SELECT task_id FROM tasks WHERE task_id=?", (a.id,)).fetchone()
    if not row:
        sys.exit(f"no such task #{a.id}")
    _event(c, a.id, "note", a.text)
    _bump(c, a.id)
    c.commit()
    print(f"logged #{a.id}: {a.text}")


def _rows(c, all_):
    q = "SELECT * FROM tasks"
    if not all_:
        q += " WHERE status!='done'"
    rows = c.execute(q).fetchall()
    return sorted(
        rows,
        key=lambda r: (
            r["status"] == "done",
            PRIO_ORDER.get(r["priority"], 1),
            r["due_at"] or "9999",
        ),
    )


def _events_for(c, tid):
    return c.execute(
        "SELECT event,detail,ts FROM task_events WHERE task_id=? ORDER BY id", (tid,)
    ).fetchall()


def list_(c, a):
    rows = _rows(c, a.all)
    if not rows:
        print("(없음)")
        return
    for r in rows:
        mark = {"done": "✅", "doing": "▶", "todo": "▢"}.get(r["status"], "▢")
        due = f" (기한 {r['due_at']})" if r["due_at"] else ""
        prio = {"high": "★", "med": "", "low": "↓"}.get(r["priority"], "")
        print(f"{mark} #{r['task_id']} {prio}{r['title']}{due}")


def show(c, a):
    r = c.execute("SELECT * FROM tasks WHERE task_id=?", (a.id,)).fetchone()
    if not r:
        sys.exit(f"no such task #{a.id}")
    print(f"#{r['task_id']} [{r['status']}] {r['title']}")
    print(f"  기한: {r['due_at'] or '-'} / 우선순위: {r['priority']} / 출처: {r['source'] or '-'}")
    if r["notes"]:
        print(f"  메모: {r['notes']}")
    print(f"  생성: {r['created_at']} / 갱신: {r['updated_at']}")
    evs = _events_for(c, r["task_id"])
    if evs:
        print("  로그:")
        for e in evs:
            d = f" {e['detail']}" if e["detail"] else ""
            print(f"    - {e['ts']} {e['event']}{d}")


def to_json(c, a):
    rows = _rows(c, a.all)
    out = []
    for r in rows:
        d = dict(r)
        d["events"] = [dict(e) for e in _events_for(c, r["task_id"])]
        out.append(d)
    print(json.dumps(out, ensure_ascii=False, indent=2))


def export(c, a=None):
    rows = c.execute("SELECT * FROM tasks").fetchall()
    active = [r for r in rows if r["status"] != "done"]
    done_ = [r for r in rows if r["status"] == "done"]
    active = sorted(
        active,
        key=lambda r: (PRIO_ORDER.get(r["priority"], 1), r["due_at"] or "9999"),
    )
    done_ = sorted(done_, key=lambda r: r["completed_at"] or "", reverse=True)
    lines = [
        "# 업무 할 일 (오규민 / raionrobotics)",
        f"updated: {now_kst()}",
        "source: SQLite todo.db (단일 진실원본). 이 파일은 자동 생성 뷰 — 직접 편집 금지.",
        "",
        "## 진행 중",
    ]
    if not active:
        lines.append("(없음)")
    for r in active:
        prio = {"high": "★", "med": "", "low": "↓"}.get(r["priority"], "")
        due = f" / 기한: {r['due_at']}" if r["due_at"] else ""
        lines.append(f"- #{r['task_id']} {prio}{r['title']}")
        lines.append(
            f"  · 상태: {r['status']}{due} / 출처: {r['source'] or '-'}"
        )
        if r["notes"]:
            lines.append(f"  · 메모: {r['notes']}")
        evs = _events_for(c, r["task_id"])
        notelog = [e for e in evs if e["event"] == "note"]
        if notelog:
            lines.append("  · 로그: " + " / ".join(f"{e['ts'][:10]} {e['detail']}" for e in notelog))
    lines += ["", "## 완료"]
    if not done_:
        lines.append("(없음)")
    for r in done_:
        lines.append(f"- #{r['task_id']} {r['title']}  (done {r['completed_at'] or ''})")
    lines += [
        "",
        "## 운영",
        "- 진실원본=todo.db. 변경은 todoctl(또는 추후 전용 봇)로만. 이 .md 수동편집은 반영 안 됨.",
        "- 텔레그램으로 '목록' '1번 done' 'OO 추가' 'N번 진행 로그' 하면 Claude가 todoctl로 반영.",
    ]
    with open(MD, "w") as f:
        f.write("\n".join(lines) + "\n")
    print(f"exported -> {MD}")


def main():
    p = argparse.ArgumentParser()
    sub = p.add_subparsers(dest="cmd", required=True)

    sub.add_parser("init")

    pa = sub.add_parser("add")
    pa.add_argument("title")
    pa.add_argument("--due")
    pa.add_argument("--prio", default="med", choices=["high", "med", "low"])
    pa.add_argument("--source")
    pa.add_argument("--notes")

    for name in ("done", "reopen", "rm", "show"):
        sp = sub.add_parser(name)
        sp.add_argument("id", type=int)

    pu = sub.add_parser("update")
    pu.add_argument("id", type=int)
    pu.add_argument("--title")
    pu.add_argument("--due")
    pu.add_argument("--prio", choices=["high", "med", "low"])
    pu.add_argument("--status", choices=["todo", "doing", "done"])
    pu.add_argument("--notes")

    pn = sub.add_parser("note")
    pn.add_argument("id", type=int)
    pn.add_argument("text")

    pl = sub.add_parser("list")
    pl.add_argument("--all", action="store_true")
    pj = sub.add_parser("json")
    pj.add_argument("--all", action="store_true")
    sub.add_parser("export")

    a = p.parse_args()
    c = conn()
    init(c)  # idempotent

    writes = {"add", "done", "reopen", "rm", "update", "note"}
    dispatch = {
        "init": lambda: print("ok"),
        "add": lambda: add(c, a),
        "done": lambda: done(c, a),
        "reopen": lambda: reopen(c, a),
        "rm": lambda: rm(c, a),
        "update": lambda: update(c, a),
        "note": lambda: note(c, a),
        "list": lambda: list_(c, a),
        "show": lambda: show(c, a),
        "json": lambda: to_json(c, a),
        "export": lambda: export(c, a),
    }
    dispatch[a.cmd]()
    if a.cmd in writes:
        export(c)  # 변경 시 todo.md 자동 갱신


if __name__ == "__main__":
    main()
