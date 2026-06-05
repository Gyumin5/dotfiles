#!/usr/bin/env python3
"""
Microsoft Graph 토큰 발급/갱신 (device code flow, 비밀번호 저장 안 함).
- `python3 auth.py login` : 최초 1회. device code 출력 후 사용자가 브라우저에서 동의하면 토큰 캐시 저장.
- `python3 auth.py token` : 캐시된 refresh_token으로 access_token 갱신해 stdout 출력.
- import 해서 get_access_token() 사용.

토큰 캐시: token_cache.json (chmod 600). refresh_token + access_token + 만료시각.
"""
import json
import os
import sys
import time
import urllib.parse
import requests

HERE = os.path.dirname(os.path.abspath(__file__))
CONFIG = json.load(open(os.path.join(HERE, "config.json")))
CACHE_PATH = os.path.join(HERE, "token_cache.json")

TENANT = CONFIG["tenant_id"]
CLIENT_ID = CONFIG["client_id"]
SCOPES = CONFIG["scopes"]
BASE = f"https://login.microsoftonline.com/{TENANT}/oauth2/v2.0"


def _save_cache(tok):
    tok = dict(tok)
    if "expires_in" in tok:
        tok["expires_at"] = int(time.time()) + int(tok["expires_in"]) - 120
    with open(CACHE_PATH, "w") as f:
        json.dump(tok, f)
    os.chmod(CACHE_PATH, 0o600)


def _load_cache():
    if not os.path.exists(CACHE_PATH):
        return None
    return json.load(open(CACHE_PATH))


def device_login():
    r = requests.post(
        f"{BASE}/devicecode",
        data={"client_id": CLIENT_ID, "scope": SCOPES},
        timeout=30,
    )
    r.raise_for_status()
    flow = r.json()
    # 사용자에게 보여줄 정보 출력 (한 줄 JSON)
    print("DEVICECODE " + json.dumps({
        "verification_uri": flow["verification_uri"],
        "user_code": flow["user_code"],
        "message": flow.get("message", ""),
    }), flush=True)
    interval = int(flow.get("interval", 5))
    expires = int(flow.get("expires_in", 900))
    device_code = flow["device_code"]
    deadline = time.time() + expires
    while time.time() < deadline:
        time.sleep(interval)
        t = requests.post(
            f"{BASE}/token",
            data={
                "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
                "client_id": CLIENT_ID,
                "device_code": device_code,
            },
            timeout=30,
        )
        j = t.json()
        if "access_token" in j:
            _save_cache(j)
            print("LOGIN_OK", flush=True)
            return j
        err = j.get("error")
        if err in ("authorization_pending", "slow_down"):
            if err == "slow_down":
                interval += 5
            continue
        print("LOGIN_FAIL " + json.dumps(j), flush=True)
        sys.exit(1)
    print("LOGIN_TIMEOUT", flush=True)
    sys.exit(1)


def _refresh(refresh_token):
    r = requests.post(
        f"{BASE}/token",
        data={
            "grant_type": "refresh_token",
            "client_id": CLIENT_ID,
            "refresh_token": refresh_token,
            "scope": SCOPES,
        },
        timeout=30,
    )
    j = r.json()
    if "access_token" not in j:
        raise RuntimeError("refresh failed: " + json.dumps(j))
    # 새 refresh_token이 없으면 기존 것 유지
    if "refresh_token" not in j:
        j["refresh_token"] = refresh_token
    _save_cache(j)
    return j


def get_access_token():
    cache = _load_cache()
    if not cache:
        raise RuntimeError("no token cache; run `python3 auth.py login` first")
    if cache.get("expires_at", 0) > int(time.time()):
        return cache["access_token"]
    if "refresh_token" in cache:
        return _refresh(cache["refresh_token"])["access_token"]
    raise RuntimeError("token expired and no refresh_token; re-login")


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "token"
    if cmd == "login":
        device_login()
    elif cmd == "token":
        print(get_access_token())
    else:
        print("usage: auth.py [login|token]", file=sys.stderr)
        sys.exit(2)
