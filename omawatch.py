#!/usr/bin/env python3
"""omawatch — helper that talks to the public moodwatch api.

Subcommands (stdin carries a JSON request, stdout receives one JSON answer):
  recommend    -> mood quiz answers -> film picks
  surprise     -> fixed mood profile -> film picks
  sync-start   -> start letterboxd watchlist sync, returns sync token
  sync-status  -> poll sync status with the sync token
  recommend-wl -> mood answers + watchlist token -> picks from the watchlist

The helper never writes anything to disk and never stores the username.
"""
import base64
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request

API = "https://moodwatch-api.brmcl.workers.dev"
UA = "omawatch/1.0 (omarchy plugin)"
TIMEOUT = 20


def _request(path, params=None, method="GET", body=None, headers=None):
    url = API + path
    if params:
        url += "?" + urllib.parse.urlencode(params)
    data = json.dumps(body).encode() if body is not None else None
    head = {"User-Agent": UA, "Content-Type": "application/json"}
    if headers:
        head.update(headers)
    req = urllib.request.Request(url, data=data, headers=head, method=method)
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
            return resp.status, json.loads(resp.read().decode("utf-8", "replace"))
    except urllib.error.HTTPError as exc:
        try:
            return exc.code, json.loads(exc.read().decode("utf-8", "replace"))
        except Exception:
            return exc.code, {}
    except Exception as exc:
        return 0, {"error": "network", "detail": str(exc)}


def _ok(payload):
    print(json.dumps(payload, ensure_ascii=False))
    sys.exit(0)


def _fail(code):
    print(json.dumps({"ok": False, "error": code}, ensure_ascii=False))
    sys.exit(0)


def _read_request():
    """Read one QML request without waiting for stdin EOF."""
    chunks = []
    while True:
        chunk = os.read(sys.stdin.fileno(), 4096)
        if not chunk:
            break
        chunks.append(chunk)
        if b"\x1e" in chunk:
            break
    raw = b"".join(chunks).split(b"\x1e", 1)[0].decode("utf-8", "replace").strip()
    if not raw:
        return {}
    try:
        return json.loads(raw)
    except Exception:
        return {}


def _mood_from_answers(answers):
    """Map the compact quiz answers to the moodwatch mood axes.

    The quiz uses the five axes the api scores most directly:
    state (energy/risk), appetite (tone/trust), runtime, tone, depth.
    """
    a = answers if isinstance(answers, dict) else {}
    m = {}

    state = a.get("state")
    if state == "drained":
        m["energy"] = "unwind"
        m["risk"] = "safe"
    elif state == "restless":
        m["energy"] = "engage"
        m["risk"] = "discover"
    elif state == "pensive":
        m["energy"] = "engage"
        m["depth"] = m.get("depth") or "thoughtful"
    elif state == "good":
        m["risk"] = m.get("risk") or "discover"

    appetite = a.get("appetite")
    if appetite:
        m["appetite"] = appetite
    if appetite == "feel-deep":
        m["energy"] = "engage"
        m["depth"] = m.get("depth") or "thoughtful"
    elif appetite == "horror":
        m["tone"] = "dark"
        m["trust"] = "horror"
        m["first_act"] = m.get("first_act") or "thriller_horror"
    elif appetite == "weird":
        m["tone"] = "dark"
        m["trust"] = "weird"
        m["risk"] = "discover"
        m["popularity"] = m.get("popularity") or "low"
    elif appetite == "comfort":
        m["energy"] = m.get("energy") or "unwind"
        m["depth"] = m.get("depth") or "warm"
        m["risk"] = m.get("risk") or "safe"
    elif appetite == "transformative":
        m["energy"] = m.get("energy") or "engage"
        m["depth"] = m.get("depth") or "thoughtful"
        m["risk"] = m.get("risk") or "discover"

    runtime = a.get("runtime")
    if runtime in ("short", "medium", "long"):
        m["runtime"] = runtime

    tone = a.get("tone")
    if tone in ("dark", "light"):
        m["tone"] = tone

    depth = a.get("depth")
    if depth in ("fun", "warm", "thoughtful", "uneasy", "ruined"):
        m["depth"] = depth

    company = a.get("company")
    if company == "together":
        m["company"] = "shared"
    elif company == "solo":
        m["company"] = "solo"

    return m


def _recommend_params(request, with_watchlist):
    lang = request.get("lang") if request.get("lang") in ("es", "en") else "es"
    country = str(request.get("country") or "CL").upper()[:2]
    mood = _mood_from_answers(request.get("answers") or {})
    mood_b64 = base64.b64encode(json.dumps(mood).encode()).decode()
    params = {
        "lang": lang,
        "country": country,
        "mood": mood_b64,
        "count": "3",
        "media": "movie",
        "seed": str(int(request.get("seed") or 0) % 1000000007),
    }
    if with_watchlist:
        params["source_policy"] = "watchlist_only"
    return params


def cmd_recommend(request):
    params = _recommend_params(request, with_watchlist=False)
    status, data = _request("/recommend", params)
    if status != 200 or not data.get("ok"):
        _fail(data.get("error") or "recommend-unavailable")
    films = data.get("films") or []
    if not films:
        _fail("no-picks")
    _ok({"ok": True, "films": films[:3]})


def cmd_recommend_wl(request):
    token = str(request.get("watchlist_token") or "")
    if not token:
        _fail("watchlist-token-missing")
    params = _recommend_params(request, with_watchlist=True)
    status, data = _request(
        "/recommend", params, headers={"X-Moodwatch-Watchlist-Token": token}
    )
    if status != 200 or not data.get("ok"):
        _fail(data.get("error") or "recommend-unavailable")
    films = data.get("films") or []
    if not films:
        _fail("no-picks")
    _ok({"ok": True, "films": films[:3]})


def cmd_surprise(request):
    lang = request.get("lang") if request.get("lang") in ("es", "en") else "es"
    country = str(request.get("country") or "CL").upper()[:2]
    profile = str(request.get("profile") or "cozy")
    params = {
        "lang": lang,
        "country": country,
        "count": "3",
        "media": "movie",
        "profile": profile,
        "seed": str(int(request.get("seed") or 0) % 1000000007),
    }
    status, data = _request("/surprise", params)
    if status != 200 or not data.get("ok"):
        _fail(data.get("error") or "surprise-unavailable")
    films = data.get("films") or []
    if not films:
        _fail("no-picks")
    _ok({"ok": True, "films": films[:3]})


def cmd_sync_start(request):
    username = str(request.get("username") or "").strip().lower()
    if not (2 <= len(username) <= 40) or not all(
        c.isalnum() or c in "-_" for c in username
    ):
        _fail("invalid-username")
    status, data = _request(
        "/watchlist/sync", method="POST", body={"username": username}
    )
    if status != 200 or not data.get("ok"):
        _fail(data.get("error") or "sync-unavailable")
    # A cached watchlist returns ready immediately with its own token.
    payload = {
        "ok": True,
        "sync_token": data.get("sync_token"),
        "status": data.get("status"),
        "next_poll_after_ms": data.get("next_poll_after_ms") or 3000,
    }
    if data.get("status") in ("ready", "ready_partial") and data.get("watchlist_token"):
        payload["watchlist_token"] = data.get("watchlist_token")
    _ok(payload)


def cmd_sync_status(request):
    token = str(request.get("sync_token") or "")
    if not token:
        _fail("sync-token-missing")
    status, data = _request(
        "/watchlist/status", headers={"X-Moodwatch-Token": token}
    )
    if status != 200 or not data.get("ok"):
        _fail(data.get("error") or "sync-status-unavailable")
    _ok(
        {
            "ok": True,
            "status": data.get("status"),
            "error": data.get("error"),
            "watchlist_token": data.get("watchlist_token"),
            "progress": data.get("progress") or {},
            "next_poll_after_ms": data.get("next_poll_after_ms") or 3000,
        }
    )


COMMANDS = {
    "recommend": cmd_recommend,
    "recommend-wl": cmd_recommend_wl,
    "surprise": cmd_surprise,
    "sync-start": cmd_sync_start,
    "sync-status": cmd_sync_status,
}


def main():
    command = sys.argv[1] if len(sys.argv) > 1 else ""
    handler = COMMANDS.get(command)
    if handler is None:
        _fail("unknown-command")
    handler(_read_request())


if __name__ == "__main__":
    main()
