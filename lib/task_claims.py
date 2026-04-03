#!/usr/bin/env python3
"""
SHTD Flow — Multi-tab task negotiation.

Atomic claim/release using OS file locks (msvcrt on Windows, fcntl on Unix).
Dead sessions auto-release via PID check. Claims persist across context resets.

Usage:
    python task_claims.py next    --session ID --project-dir /path
    python task_claims.py claim   TASK --session ID --project-dir /path
    python task_claims.py release TASK --session ID --project-dir /path
    python task_claims.py status  --project-dir /path
    python task_claims.py stats   --project-dir /path
"""

import argparse, json, os, re, sys, time
from datetime import datetime

IS_WIN = sys.platform == "win32"
FLOW_DIR = os.path.join(os.path.expanduser("~"), ".claude", "shtd-flow")
CLAIMS_DIR = os.path.join(FLOW_DIR, "claims")
AUDIT_LOG = os.path.join(FLOW_DIR, "audit.jsonl")


def _key(d): return os.path.abspath(d).replace(os.sep, "-").replace(":", "").strip("-")
def _cfile(d): os.makedirs(CLAIMS_DIR, exist_ok=True); return os.path.join(CLAIMS_DIR, f"{_key(d)}.json")


def _lock(d):
    lp = _cfile(d) + ".lock"
    fh = open(lp, "w")
    try:
        if IS_WIN:
            import msvcrt
            for _ in range(30):
                try: msvcrt.locking(fh.fileno(), msvcrt.LK_NBLCK, 1); return fh, lp
                except IOError: time.sleep(0.1)
            raise IOError("Lock timeout")
        else:
            import fcntl; fcntl.flock(fh, fcntl.LOCK_EX); return fh, lp
    except: fh.close(); raise


def _unlock(fh, lp):
    try:
        if IS_WIN:
            import msvcrt
            try: msvcrt.locking(fh.fileno(), msvcrt.LK_UNLCK, 1)
            except: pass
        fh.close()
    except: pass
    try: os.remove(lp)
    except: pass


def _read(d):
    p = _cfile(d)
    if not os.path.exists(p): return {}
    try:
        with open(p) as f: return json.load(f)
    except: return {}


def _write(d, c):
    with open(_cfile(d), "w") as f: json.dump(c, f, indent=2)


def _alive_pid(pid):
    try:
        if IS_WIN:
            import ctypes
            h = ctypes.windll.kernel32.OpenProcess(0x100000, False, pid)
            if h: ctypes.windll.kernel32.CloseHandle(h); return True
            return False
        else: os.kill(pid, 0); return True
    except: return False


def _alive(claim):
    if claim.get("pid") and _alive_pid(claim["pid"]): return True
    sid = claim.get("session", "")
    if sid:
        pd = os.path.join(os.path.expanduser("~"), ".claude", "projects")
        if os.path.isdir(pd):
            for f in os.listdir(pd):
                jp = os.path.join(pd, f, f"{sid}.jsonl")
                if os.path.exists(jp): return (time.time() - os.path.getmtime(jp)) < 600
    return False


def _gc(claims):
    dead = [t for t, c in claims.items() if not _alive(c)]
    for t in dead: claims.pop(t)
    return dead


def _audit(event, task, session, project, extra=None):
    os.makedirs(FLOW_DIR, exist_ok=True)
    e = {"ts": datetime.now().isoformat(), "event": event, "task": task,
         "session": session[:12] if session else None,
         "project": os.path.basename(project), "pid": os.getpid()}
    if extra: e.update(extra)
    try:
        with open(AUDIT_LOG, "a") as f: f.write(json.dumps(e) + "\n")
    except: pass


def _todos(d):
    p = os.path.join(d, "TODO.md")
    if not os.path.exists(p): return []
    with open(p) as f:
        return [m.group(1) for line in f if (m := re.match(r'\s*-\s*\[\s*\]\s*(T\d+)', line))]


def claim(tid, sid, d, pid=None):
    fh, lp = _lock(d)
    try:
        c = _read(d); dead = _gc(c)
        for t in dead: _audit("auto_release", t, "", d, {"reason": "dead_session"})
        if tid in c:
            print(json.dumps({"claimed": False, "owner": c[tid].get("session","?")[:12]})); return False
        c[tid] = {"session": sid, "pid": pid or os.getppid(), "claimed_at": datetime.now().isoformat()}
        _write(d, c); _audit("task_claimed", tid, sid, d)
        print(json.dumps({"claimed": True, "task": tid})); return True
    finally: _unlock(fh, lp)


def release(tid, sid, d, status="completed"):
    fh, lp = _lock(d)
    try:
        c = _read(d)
        if tid in c:
            c.pop(tid); _write(d, c); _audit("task_released", tid, sid, d, {"status": status})
            print(json.dumps({"released": True, "task": tid})); return True
        print(json.dumps({"released": False})); return False
    finally: _unlock(fh, lp)


def next_task(sid, d, pid=None):
    todos = _todos(d)
    if not todos: print(json.dumps({"next": None, "reason": "no_unchecked_tasks"})); return None
    fh, lp = _lock(d)
    try:
        c = _read(d); dead = _gc(c)
        for t in dead: _audit("auto_release", t, "", d, {"reason": "dead_session"})
        for tid in todos:
            if tid not in c:
                c[tid] = {"session": sid, "pid": pid or os.getppid(), "claimed_at": datetime.now().isoformat()}
                _write(d, c); _audit("task_claimed", tid, sid, d, {"via": "next"})
                print(json.dumps({"next": tid, "claimed": True})); return tid
            elif c[tid].get("session") == sid:
                print(json.dumps({"next": tid, "already_mine": True})); return tid
        print(json.dumps({"next": None, "reason": "all_claimed",
                           "claimed": {k: v.get("session","?")[:12] for k,v in c.items()}}))
        return None
    finally: _unlock(fh, lp)


def status(d):
    fh, lp = _lock(d)
    try:
        c = _read(d); dead = _gc(c)
        if dead: _write(d, c)
        todos = _todos(d)
    finally: _unlock(fh, lp)
    r = {"project": os.path.basename(d), "tasks": todos, "claims": {}, "available": []}
    for t in todos:
        if t in c: r["claims"][t] = {"session": c[t].get("session","?")[:12], "pid": c[t].get("pid"), "since": c[t].get("claimed_at")}
        else: r["available"].append(t)
    print(json.dumps(r, indent=2))


def stats(d):
    if not os.path.exists(AUDIT_LOG): print(json.dumps({"error": "no audit log"})); return
    pn = os.path.basename(d); sessions = {}; nc = nr = 0
    with open(AUDIT_LOG) as f:
        for line in f:
            try: e = json.loads(line.strip())
            except: continue
            if e.get("project") != pn: continue
            s = e.get("session", "?")
            if s not in sessions: sessions[s] = {"claimed": [], "released": []}
            if e["event"] == "task_claimed": sessions[s]["claimed"].append(e.get("task")); nc += 1
            elif e["event"] == "task_released": sessions[s]["released"].append(e.get("task")); nr += 1
    ts = {}
    for s, d2 in sessions.items():
        for t in d2["claimed"]: ts.setdefault(t, set()).add(s)
    dupes = {t: list(ss) for t, ss in ts.items() if len(ss) > 1}
    print(json.dumps({"project": pn, "claims": nc, "completions": nr,
                       "sessions": len(sessions), "duplicates": dupes or None}, indent=2))


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    sub = p.add_subparsers(dest="cmd", required=True)
    for name in ("claim", "release"):
        sp = sub.add_parser(name); sp.add_argument("task_id")
        sp.add_argument("--session", required=True); sp.add_argument("--pid", type=int, default=None)
        sp.add_argument("--project-dir", default=os.environ.get("CLAUDE_PROJECT_DIR", os.getcwd()))
        if name == "release": sp.add_argument("--status", default="completed")
    sp = sub.add_parser("next"); sp.add_argument("--session", required=True)
    sp.add_argument("--pid", type=int, default=None)
    sp.add_argument("--project-dir", default=os.environ.get("CLAUDE_PROJECT_DIR", os.getcwd()))
    for name in ("status", "stats"):
        sp = sub.add_parser(name)
        sp.add_argument("--project-dir", default=os.environ.get("CLAUDE_PROJECT_DIR", os.getcwd()))
    a = p.parse_args()
    {"claim": lambda: claim(a.task_id, a.session, a.project_dir, a.pid),
     "release": lambda: release(a.task_id, a.session, a.project_dir, getattr(a,'status','completed')),
     "next": lambda: next_task(a.session, a.project_dir, getattr(a,'pid',None)),
     "status": lambda: status(a.project_dir),
     "stats": lambda: stats(a.project_dir)}[a.cmd]()
