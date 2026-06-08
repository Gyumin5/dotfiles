#!/usr/bin/env python3
"""
todoctl — 개인 업무 todo 단일 writer CLI.
진실원본 = SQLite(todo.db, WAL). 모든 쓰기는 이 CLI를 통해서만.
todo.md 는 매 변경 후 DB에서 자동 재생성되는 읽기용 뷰(원본 아님).

명령:
  init                              스키마 생성
  add "제목" [--due YYYY-MM-DD] [--prio high|med|low] [--source ...] [--notes ...] [--tags ..]
  done <id> | reopen <id> | rm <id>
  update <id> [--title ..] [--due ..] [--prio ..] [--status todo|doing|done] [--notes ..] [--tags ..]
  note <id> "진행 로그 한 줄"        로그 append
  list [--all] [--tag NAME]         진행중(기본)/전체, 태그 필터
  show <id>                         상세
  search "검색어" [--all] [--json]   제목·메모·태그 전문검색(FTS5, LIKE 폴백)
  tags [--json]                     태그 목록 + 건수
  export                            todo.md 재생성
  json [--all] [--tag NAME]         기계용 JSON 출력

설계: ai-debate run-20260604T065446Z (단일 진실원본 SQLite + 단일 writer).
"""
import argparse
import json
import os
import re
import sqlite3
import sys
from datetime import datetime
from zoneinfo import ZoneInfo

HERE = os.path.dirname(os.path.abspath(__file__))
DB = os.path.join(HERE, "todo.db")
MD = "/home/gmoh/raion/todo.md"
KST = ZoneInfo("Asia/Seoul")
PRIO_ORDER = {"high": 0, "med": 1, "low": 2}  # 레거시(--prio 호환용). 정렬은 _urgency(태그)로 대체.
HAS_FTS = False  # init() 에서 FTS5 사용 가능 여부 탐지 후 설정

# 사전 정의 태그(통제 어휘) — config.json 에서 로드, 없으면 기본값.
_DEF_TAGS = ["개발", "회사", "인사", "회의", "개인", "기타"]


def _tag_config():
    try:
        with open(os.path.join(HERE, "config.json")) as f:
            cfg = json.load(f)
    except Exception:  # noqa: BLE001
        cfg = {}
    canon = cfg.get("tags") or _DEF_TAGS
    aliases = {k.lower(): v for k, v in (cfg.get("tag_aliases") or {}).items()}
    fallback = cfg.get("tag_fallback") or "기타"
    return canon, aliases, fallback


TAGS_CANON, TAG_ALIASES, TAG_FALLBACK = _tag_config()


def allowed_tags():
    return list(TAGS_CANON)


def _canon_tag(raw):
    """입력 토큰 → 통제 어휘로 매핑. 별칭 적용, 정의 밖이면 fallback(기타)."""
    t = raw.strip().lstrip("#").lower()
    if not t:
        return None
    t = TAG_ALIASES.get(t, t)
    # 통제 어휘 대조는 대소문자 무시(한글은 영향 없음).
    for c in TAGS_CANON:
        if t == c.lower():
            return c
    return TAG_FALLBACK


def _norm_tags(s):
    """'#회사, dev xyz' → '회사,개발,기타' (별칭→통제어휘, 정의 밖=기타, 중복 제거)."""
    if not s:
        return None
    seen = []
    for p in re.split(r"[,\s]+", s.strip()):
        c = _canon_tag(p)
        if c and c not in seen:
            seen.append(c)
    return ",".join(seen) if seen else None


def _task_tags(row):
    raw = row["tags"] if "tags" in row.keys() else None
    return [x for x in (raw or "").split(",") if x]


# 긴급도 정렬: 태그 '긴급'(0) > '중요'(1) > 그 외(2). 옛 priority 필드 대체.
URGENCY = {"긴급": 0, "중요": 1}


def _urgency(row):
    return min((URGENCY[t] for t in _task_tags(row) if t in URGENCY), default=2)


def _umark(row):
    tg = _task_tags(row)
    if "긴급" in tg:
        return "🔴"
    if "중요" in tg:
        return "⭐"
    return ""


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
          tags TEXT,                              -- 콤마결합 라벨(예: '회사,긴급')
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
    # 기존 DB 마이그레이션: tags 컬럼 없으면 추가.
    cols = [r[1] for r in c.execute("PRAGMA table_info(tasks)")]
    if "tags" not in cols:
        c.execute("ALTER TABLE tasks ADD COLUMN tags TEXT")
    c.commit()
    _init_fts(c)


def _init_fts(c):
    """FTS5 전문검색 인덱스(가상테이블 + 동기화 트리거). FTS5 미지원 빌드면 조용히 비활성."""
    global HAS_FTS
    existed = c.execute(
        "SELECT 1 FROM sqlite_master WHERE type='table' AND name='tasks_fts'"
    ).fetchone()
    try:
        c.executescript(
            """
            CREATE VIRTUAL TABLE IF NOT EXISTS tasks_fts USING fts5(
              title, notes, tags, content='tasks', content_rowid='task_id'
            );
            CREATE TRIGGER IF NOT EXISTS tasks_ai AFTER INSERT ON tasks BEGIN
              INSERT INTO tasks_fts(rowid,title,notes,tags)
                VALUES(new.task_id,new.title,new.notes,new.tags);
            END;
            CREATE TRIGGER IF NOT EXISTS tasks_ad AFTER DELETE ON tasks BEGIN
              INSERT INTO tasks_fts(tasks_fts,rowid,title,notes,tags)
                VALUES('delete',old.task_id,old.title,old.notes,old.tags);
            END;
            CREATE TRIGGER IF NOT EXISTS tasks_au AFTER UPDATE ON tasks BEGIN
              INSERT INTO tasks_fts(tasks_fts,rowid,title,notes,tags)
                VALUES('delete',old.task_id,old.title,old.notes,old.tags);
              INSERT INTO tasks_fts(rowid,title,notes,tags)
                VALUES(new.task_id,new.title,new.notes,new.tags);
            END;
            """
        )
        HAS_FTS = True
    except sqlite3.OperationalError:
        HAS_FTS = False
        return
    if not existed:  # 새로 만든 인덱스면 기존 행으로 1회 채움.
        c.execute("INSERT INTO tasks_fts(tasks_fts) VALUES('rebuild')")
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
    tags = _norm_tags(getattr(a, "tags", None))
    cur = c.execute(
        "INSERT INTO tasks(title,status,due_at,priority,source,notes,tags,created_at,updated_at)"
        " VALUES(?,?,?,?,?,?,?,?,?)",
        (a.title, "todo", a.due, a.prio, a.source, a.notes, tags, t, t),
    )
    tid = cur.lastrowid
    _event(c, tid, "created", a.title)
    c.commit()
    extra = f"  🏷 {tags}" if tags else ""
    print(f"added #{tid}: {a.title}{extra}")


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
    if getattr(a, "tags", None) is not None:
        fields["tags"] = _norm_tags(a.tags)  # 빈 문자열이면 None → 태그 제거
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


def _rows(c, all_, tag=None):
    q = "SELECT * FROM tasks"
    if not all_:
        q += " WHERE status!='done'"
    rows = c.execute(q).fetchall()
    if tag:
        tg = _norm_tags(tag)
        rows = [r for r in rows if tg in _task_tags(r)]
    return sorted(
        rows,
        key=lambda r: (
            r["status"] == "done",
            _urgency(r),
            r["due_at"] or "9999",
        ),
    )


def _events_for(c, tid):
    return c.execute(
        "SELECT event,detail,ts FROM task_events WHERE task_id=? ORDER BY id", (tid,)
    ).fetchall()


def list_(c, a):
    rows = _rows(c, a.all, getattr(a, "tag", None))
    if not rows:
        print("(없음)")
        return
    for r in rows:
        mark = {"done": "✅", "doing": "▶", "todo": "▢"}.get(r["status"], "▢")
        due = f" (기한 {r['due_at']})" if r["due_at"] else ""
        um = (_umark(r) + " ") if _umark(r) else ""
        tg = _task_tags(r)
        tags = f"  🏷 {','.join(tg)}" if tg else ""
        print(f"{mark} #{r['task_id']} {um}{r['title']}{due}{tags}")


def show(c, a):
    r = c.execute("SELECT * FROM tasks WHERE task_id=?", (a.id,)).fetchone()
    if not r:
        sys.exit(f"no such task #{a.id}")
    print(f"#{r['task_id']} [{r['status']}] {r['title']}")
    print(f"  기한: {r['due_at'] or '-'} / 우선순위: {r['priority']} / 출처: {r['source'] or '-'}")
    tg = _task_tags(r)
    if tg:
        print(f"  태그: {','.join(tg)}")
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
    rows = _rows(c, a.all, getattr(a, "tag", None))
    out = []
    for r in rows:
        d = dict(r)
        d["events"] = [dict(e) for e in _events_for(c, r["task_id"])]
        out.append(d)
    print(json.dumps(out, ensure_ascii=False, indent=2))


def _fts_match(q):
    """자유 입력 → FTS5 MATCH 식. 토큰별로 따옴표+접두(*) → 안전하고 부분일치 관대."""
    toks = [t for t in re.split(r"\s+", q.strip()) if t]
    if not toks:
        return None
    return " ".join('"%s"*' % t.replace('"', '""') for t in toks)


def search(c, a):
    """제목·메모·태그 전문검색. FTS5(있으면) → 없거나 0건이면 LIKE 부분일치 폴백."""
    q = (a.query or "").strip()
    rows = []
    if q and HAS_FTS:
        m = _fts_match(q)
        if m:
            try:
                rows = c.execute(
                    "SELECT t.* FROM tasks t JOIN tasks_fts f ON f.rowid=t.task_id "
                    "WHERE tasks_fts MATCH ? ORDER BY rank",
                    (m,),
                ).fetchall()
            except sqlite3.OperationalError:
                rows = []
    if not rows and q:  # FTS 미지원/무매치 → LIKE 부분일치(한글 음절 내부도 매칭).
        like = f"%{q}%"
        rows = c.execute(
            "SELECT * FROM tasks WHERE title LIKE ? OR IFNULL(notes,'') LIKE ? "
            "OR IFNULL(tags,'') LIKE ?",
            (like, like, like),
        ).fetchall()
    if not a.all:
        rows = [r for r in rows if r["status"] != "done"]
    if getattr(a, "json", False):
        out = []
        for r in rows:
            d = dict(r)
            d["events"] = [dict(e) for e in _events_for(c, r["task_id"])]
            out.append(d)
        print(json.dumps(out, ensure_ascii=False, indent=2))
        return
    if not rows:
        print(f"(검색 결과 없음: {q})")
        return
    for r in rows:
        mark = {"done": "✅", "doing": "▶", "todo": "▢"}.get(r["status"], "▢")
        due = f" (기한 {r['due_at']})" if r["due_at"] else ""
        um = (_umark(r) + " ") if _umark(r) else ""
        tg = _task_tags(r)
        tags = f"  🏷 {','.join(tg)}" if tg else ""
        print(f"{mark} #{r['task_id']} {um}{r['title']}{due}{tags}")


def tags_cmd(c, a):
    """전체 태그 목록 + 미완료 건수. --json 이면 [{tag,open,total}]."""
    rows = c.execute("SELECT status,tags FROM tasks").fetchall()
    counts = {}
    for r in rows:
        for t in _task_tags(r):
            d = counts.setdefault(t, {"tag": t, "open": 0, "total": 0})
            d["total"] += 1
            if r["status"] != "done":
                d["open"] += 1
    items = sorted(counts.values(), key=lambda d: (-d["open"], d["tag"]))
    if getattr(a, "json", False):
        print(json.dumps(items, ensure_ascii=False))
        return
    if not items:
        print("(태그 없음)")
        return
    for d in items:
        print(f"🏷 {d['tag']}  (진행 {d['open']} / 전체 {d['total']})")


def export(c, a=None):
    rows = c.execute("SELECT * FROM tasks").fetchall()
    active = [r for r in rows if r["status"] != "done"]
    done_ = [r for r in rows if r["status"] == "done"]
    active = sorted(
        active,
        key=lambda r: (_urgency(r), r["due_at"] or "9999"),
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
        um = (_umark(r) + " ") if _umark(r) else ""
        due = f" / 기한: {r['due_at']}" if r["due_at"] else ""
        lines.append(f"- #{r['task_id']} {um}{r['title']}")
        tg = _task_tags(r)
        tagstr = f" / 태그: {','.join(tg)}" if tg else ""
        lines.append(
            f"  · 상태: {r['status']}{due} / 출처: {r['source'] or '-'}{tagstr}"
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
    pa.add_argument("--tags", help="콤마/공백 구분 라벨(예: '회사,긴급')")

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
    pu.add_argument("--tags", help="라벨 교체(빈 문자열이면 태그 제거)")

    pn = sub.add_parser("note")
    pn.add_argument("id", type=int)
    pn.add_argument("text")

    pl = sub.add_parser("list")
    pl.add_argument("--all", action="store_true")
    pl.add_argument("--tag", help="해당 태그 달린 것만")
    pj = sub.add_parser("json")
    pj.add_argument("--all", action="store_true")
    pj.add_argument("--tag", help="해당 태그 달린 것만")

    ps = sub.add_parser("search")
    ps.add_argument("query")
    ps.add_argument("--all", action="store_true", help="완료 포함")
    ps.add_argument("--json", action="store_true")

    pt = sub.add_parser("tags")
    pt.add_argument("--json", action="store_true")

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
        "search": lambda: search(c, a),
        "tags": lambda: tags_cmd(c, a),
        "export": lambda: export(c, a),
    }
    dispatch[a.cmd]()
    if a.cmd in writes:
        export(c)  # 변경 시 todo.md 자동 갱신


if __name__ == "__main__":
    main()
