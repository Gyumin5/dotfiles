#!/usr/bin/env python3
"""TODOBot 공통 모듈 — 토큰/chat_id 로드, 텔레그램 API, todoctl 호출.

설계:
- 전용 봇(@sk6n_ks1m_bot) 전용. 토큰=todo-sync/bot.token, chat_id=todo-sync/bot.chat_id.
- 운영 봇(Claude 세션)과 토큰이 달라 getUpdates 충돌 없음.
- DB 쓰기는 절대 직접 안 함. 모든 상태변경은 todoctl 경유(단일 writer 원칙).
- stdlib 만 사용(urllib). 무거운 의존 없음.
"""
import json
import os
import subprocess
import sys
import urllib.parse
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))  # todo-sync
TODOCTL = os.path.join(ROOT, "todoctl.py")
WEBUI_URL = os.environ.get("TODO_WEBUI_URL", "http://100.80.47.22:8787")


def _read(name):
    with open(os.path.join(ROOT, name)) as f:
        return f.read().strip()


TOKEN = _read("bot.token")
CHAT_ID = _read("bot.chat_id")
API = "https://api.telegram.org/bot%s" % TOKEN


def api(method, params=None, timeout=35):
    params = dict(params or {})
    if "reply_markup" in params and not isinstance(params["reply_markup"], str):
        params["reply_markup"] = json.dumps(params["reply_markup"], ensure_ascii=False)
    data = urllib.parse.urlencode(params).encode()
    req = urllib.request.Request("%s/%s" % (API, method), data=data)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return json.load(r)
    except Exception as e:  # noqa: BLE001
        return {"ok": False, "error": str(e)}


def send_message(text, buttons=None, chat_id=None):
    """buttons = inline_keyboard 2차원 리스트(없으면 일반 메시지)."""
    p = {"chat_id": chat_id or CHAT_ID, "text": text, "disable_web_page_preview": True}
    if buttons:
        p["reply_markup"] = {"inline_keyboard": buttons}
    return api("sendMessage", p)


def edit_message(chat_id, message_id, text, buttons=None):
    p = {"chat_id": chat_id, "message_id": message_id, "text": text,
         "disable_web_page_preview": True}
    if buttons is not None:
        p["reply_markup"] = {"inline_keyboard": buttons}
    return api("editMessageText", p)


def answer_callback(callback_id, text=None):
    p = {"callback_query_id": callback_id}
    if text:
        p["text"] = text
    return api("answerCallbackQuery", p)


def todoctl(args):
    """todoctl 을 argv 배열로 호출(shell 미사용). (rc, stdout, stderr) 반환."""
    try:
        proc = subprocess.run(
            [sys.executable, TODOCTL, *args],
            capture_output=True, text=True, timeout=20,
            cwd=ROOT,  # todoctl 은 상대경로 todo.db 사용 → CWD 를 todo-sync 로 고정
        )
        return proc.returncode, proc.stdout, proc.stderr
    except subprocess.TimeoutExpired:
        return 1, "", "timeout"


def get_todos(all_=True):
    rc, out, err = todoctl(["json", "--all"] if all_ else ["json"])
    if rc != 0:
        raise RuntimeError("todoctl json failed: %s" % err)
    return json.loads(out)


# ── 알림 스누즈 상태 (리마인더만 미룸 — 마감일과 별개) ──────────────
# 마감일(due_at)은 todoctl/DB 가 진실원본. 스누즈는 '언제까지 리마인더를 끌지'
# 라는 운영 메타데이터일 뿐이라 DB 를 안 건드리고 사이드카 JSON 에 둔다.
# {task_id(str): "YYYY-MM-DD"} = 그 날짜 전까지 리마인더 생략.
SNOOZE_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "snooze.json")


def load_snooze():
    try:
        with open(SNOOZE_PATH) as f:
            return json.load(f)
    except Exception:  # noqa: BLE001
        return {}


def save_snooze(d):
    tmp = SNOOZE_PATH + ".tmp"
    with open(tmp, "w") as f:
        json.dump(d, f, ensure_ascii=False)
    os.replace(tmp, SNOOZE_PATH)


def set_snooze(tid, until_iso):
    d = load_snooze()
    d[str(tid)] = until_iso
    save_snooze(d)


def get_snooze_until(tid):
    return load_snooze().get(str(tid))


def clear_snooze(tid):
    d = load_snooze()
    if str(tid) in d:
        d.pop(str(tid), None)
        save_snooze(d)
