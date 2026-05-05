"""ws_supervise — filesystem-backed bend-serve supervision, no daemon.

Replaces ws_daemon.py. The three things the daemon did:
  1. Process ownership of bend reactor serve
  2. Cross-process coordination for status/wait-ready/logs
  3. Streaming log tail through file rotation

...all have shell-shaped answers:
  1. `start_new_session=True` (setsid) makes bend a process group leader.
     Once spawned, it outlives the ws.py CLI invocation.
  2. The filesystem is the source of truth. Per-workspace state lives at
     `<ws_dir>/.ws-serve.json`: pid, lstart, marker uuid, pkg paths,
     bendRegistered. Every ws.py call re-reads it.
  3. `ws.py logs` reads the log file directly; if you want tail -F behavior,
     run `tail -F <ws_dir>/.serve.log` in your shell.

Reboot safety: the state file survives reboots on disk, but every stored pid
either becomes dead or recycled with a different lstart — so `process_alive`
+ `process_start_time` equality check fails cleanly, and we drop the stale
entry on the next `stop_serve` / `status` call.
"""

import json
import os
import pathlib
import signal
import subprocess
import time
import uuid

from ws_lib import (
    BEND_REGISTRATION_TIMEOUT_S,
    LOG_TAIL_BYTES,
    ROUTE_CONFIGS_DIR,
    SERVE_STOP_GRACE_S,
    load_discovery_cache,
    log,
    node_memory_for_repos,
    normalize,
    parse_serve_log,
    process_alive,
    process_start_time,
    serve_log_path,
    ws_dir,
)


# ---------------------------------------------------------------- State files

def _state_path(name):
    return ws_dir(name) / ".ws-serve.json"


def _load_state(name):
    p = _state_path(name)
    if not p.exists():
        return None
    try:
        return json.loads(p.read_text())
    except (OSError, json.JSONDecodeError):
        return None


def _save_state(name, state):
    p = _state_path(name)
    p.parent.mkdir(parents=True, exist_ok=True)
    tmp = p.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(state, indent=2, sort_keys=True, default=str))
    tmp.replace(p)


def _clear_state(name):
    try:
        _state_path(name).unlink()
    except FileNotFoundError:
        pass


# ---------------------------------------------------------------- Liveness

def _serve_alive(state):
    """Return (alive, pid) for a loaded state dict. False if the pid is
    dead OR alive-but-lstart-doesn't-match (pid recycled after reboot)."""
    if not state:
        return False, None
    pid = state.get("pid")
    want_lstart = state.get("lstart")
    if not pid or not process_alive(pid):
        return False, None
    have_lstart = process_start_time(pid)
    if not have_lstart or have_lstart != want_lstart:
        return False, None
    return True, pid


# ---------------------------------------------------------------- Spawn

def _snapshot_introspection_files():
    if not ROUTE_CONFIGS_DIR.exists():
        return set()
    try:
        return {
            f.name for f in ROUTE_CONFIGS_DIR.iterdir()
            if f.name.endswith("-introspection")
        }
    except OSError:
        return set()


def _spawn_bend_serve(name, pkg_paths, node_memory=4096):
    """Spawn `bend reactor serve` detached (new session, own pgid).

    Returns (pid, lstart, marker). The child's stdout/stderr go to
    <ws_dir>/.serve.log (truncated first, so every fresh start is clean).

    node_memory: MB for --max_old_space_size passed to webpack subprocesses.
    Defaults to 4096 (not inherited from shell) so concurrent workspaces don't
    each consume the shell-global 8192MB limit across many Node workers.
    Use 16384 for crm-index-ui and other memory-hungry repos.
    """
    wsdir = ws_dir(name)
    wsdir.mkdir(parents=True, exist_ok=True)
    log_file = serve_log_path(name)
    log_file.parent.mkdir(parents=True, exist_ok=True)
    log_file.write_bytes(b"")

    marker = uuid.uuid4().hex
    env = os.environ.copy()
    env["BEND_WORKTREE"] = name
    env["WS_SUPERVISE_MARKER"] = marker
    # Explicitly override NODE_ARGS rather than inheriting the shell's global
    # value. The shell sets 8192 for all Node procs, but with multiple workspaces
    # each running webpack + ts-watch + test-runner per package that multiplies
    # into 100GB+ of Node heap allowance. Use 4096 as a safe concurrent default.
    env["NODE_ARGS"] = f"--max_old_space_size={node_memory}"

    cmd = [
        "bend", "reactor", "serve",
        *[str(p) for p in pkg_paths],
        "--update", "--ts-watch", "--enable-tools", "--run-tests",
    ]

    with open(log_file, "ab") as logf:
        proc = subprocess.Popen(
            cmd,
            cwd=str(wsdir),
            env=env,
            stdin=subprocess.DEVNULL,
            stdout=logf,
            stderr=subprocess.STDOUT,
            start_new_session=True,
            close_fds=True,
        )

    lstart = process_start_time(proc.pid) or ""
    return proc.pid, lstart, marker


def _wait_for_bend_registration(pid, existing_snapshot, timeout):
    """Block until bend writes a NEW *-introspection file to route-configs,
    or the bend process dies, or we time out."""
    deadline = time.time() + timeout
    while time.time() < deadline:
        if not process_alive(pid):
            return False
        new_files = _snapshot_introspection_files() - existing_snapshot
        if new_files:
            return True
        time.sleep(1)
    return False


# ---------------------------------------------------------------- URLs

def _derive_urls_for(name):
    """Best-effort URL resolution from the discovery cache."""
    from ws_lib import LB_DOMAIN_MAP
    cache = load_discovery_cache()
    wsdir = ws_dir(name)
    urls = {}
    if not wsdir.exists():
        return urls
    for d in wsdir.iterdir():
        if not d.is_dir() or d.name.startswith("."):
            continue
        repo_entry = cache.get(d.name, {})
        for pkg_name, u in (repo_entry.get("urls") or {}).items():
            lb = u.get("lb", "app")
            basename = u.get("basename")
            if not basename:
                continue
            domain = LB_DOMAIN_MAP.get(lb, f"{lb}.hubteamqa.com")
            urls[pkg_name] = f"https://{name}.local.{domain}{basename}"
    return urls


# ---------------------------------------------------------------- Public API

def start_serve(name, pkg_paths, timeout=None, node_memory=None):
    """Start bend reactor serve for a workspace. Waits for bend to register
    with route-configs before returning (or until `timeout` seconds).

    node_memory: MB for Node heap per webpack subprocess. Defaults to 4096.
    Pass 16384 for crm-index-ui and other memory-hungry repos.
    """
    name = normalize(name)
    pkg_paths = [pathlib.Path(p) for p in pkg_paths]
    if not pkg_paths:
        return {"ok": False, "error": "pkgPaths is empty"}

    alive, existing_pid = _serve_alive(_load_state(name))
    if alive:
        return {
            "ok": False,
            "error": f"serve already running for {name}",
            "servePid": existing_pid,
        }

    if node_memory is not None:
        effective_memory = node_memory
    else:
        # Derive repo names from pkg_paths (first path component under ws_dir)
        # and look up per-repo nodeMemory from ws-preferences.json.
        wsdir = ws_dir(name)
        repo_names = set()
        for p in pkg_paths:
            try:
                repo_names.add(p.relative_to(wsdir).parts[0])
            except (ValueError, IndexError):
                pass
        effective_memory = node_memory_for_repos(repo_names)

    existing = _snapshot_introspection_files()
    log(f"[{name}] spawning bend reactor serve for {len(pkg_paths)} pkg(s) (node_memory={effective_memory}MB)")
    pid, lstart, marker = _spawn_bend_serve(name, pkg_paths, node_memory=effective_memory)
    log(f"[{name}] bend pid={pid} lstart={lstart!r}")

    timeout_s = timeout if timeout is not None else BEND_REGISTRATION_TIMEOUT_S
    registered = _wait_for_bend_registration(pid, existing, timeout_s)
    log(f"[{name}] bend registered={registered}")

    _save_state(name, {
        "pid": pid,
        "lstart": lstart,
        "marker": marker,
        "pkgPaths": [str(p) for p in pkg_paths],
        "nodeMemory": effective_memory,
        "bendRegistered": registered,
        "startedAt": time.time(),
    })

    return {
        "ok": True,
        "workspace": name,
        "servePid": pid,
        "bendRegistered": registered,
        "state": "running" if process_alive(pid) else "exited",
    }


def stop_serve(name, grace=SERVE_STOP_GRACE_S):
    """SIGTERM → wait → SIGKILL the bend process group for this workspace.
    No-op if nothing is running."""
    name = normalize(name)
    state = _load_state(name)
    alive, pid = _serve_alive(state)
    if not alive:
        # Nothing to stop; just make sure the state file is gone so the next
        # start_serve doesn't think a stale pid is still ours.
        if state is not None:
            _clear_state(name)
        return {"ok": True, "wasRunning": False, "workspace": name}

    log(f"[{name}] stopping bend (pid={pid}, SIGTERM)")
    try:
        os.killpg(os.getpgid(pid), signal.SIGTERM)
    except (ProcessLookupError, PermissionError):
        pass

    deadline = time.monotonic() + grace
    while time.monotonic() < deadline and process_alive(pid):
        time.sleep(0.25)

    if process_alive(pid):
        log(f"[{name}] bend did not exit after {grace}s; SIGKILL")
        try:
            os.killpg(os.getpgid(pid), signal.SIGKILL)
        except (ProcessLookupError, PermissionError):
            pass
        # Give it a second to actually die
        deadline = time.monotonic() + 5.0
        while time.monotonic() < deadline and process_alive(pid):
            time.sleep(0.25)

    _clear_state(name)
    return {"ok": True, "wasRunning": True, "workspace": name}


def restart_serve(name, pkg_paths=None, timeout=None, node_memory=None):
    """Stop (if running) + start. If pkg_paths is None, reuse the last set.
    If node_memory is None, reuse the value stored in state."""
    name = normalize(name)
    state = _load_state(name)
    if pkg_paths is None:
        if not state:
            return {"ok": False, "error": "no pkgPaths given and no prior state"}
        pkg_paths = state.get("pkgPaths", [])
    if not pkg_paths:
        return {"ok": False, "error": "no pkgPaths to restart with"}
    # Reuse stored node_memory if not explicitly overridden
    if node_memory is None and state:
        node_memory = state.get("nodeMemory")
    stop_serve(name)
    return start_serve(name, pkg_paths, timeout=timeout, node_memory=node_memory)


def status(name):
    """Snapshot of serve state. Always returns ok:true; serveUp=False when
    nothing is running or the stored state is stale."""
    name = normalize(name)
    state = _load_state(name)
    if state is None:
        return {
            "ok": True,
            "workspace": name,
            "state": "not_running",
            "serveUp": False,
            "claudeUp": False,
            "servePid": None,
            "packages": [],
            "errors": [],
            "urls": {},
            "pkgPaths": [],
            "bendRegistered": False,
        }

    alive, pid = _serve_alive(state)

    serve_state = "not_running"
    packages = []
    errors = []
    log_file = serve_log_path(name)
    if log_file.exists():
        try:
            size = log_file.stat().st_size
            with open(log_file, "rb") as f:
                if size > LOG_TAIL_BYTES:
                    f.seek(size - LOG_TAIL_BYTES)
                text = f.read().decode("utf-8", errors="replace")
            result = parse_serve_log(text)
            serve_state = result["state"]
            packages = result["packages"]
            errors = result["errors"]
        except OSError:
            pass

    if not alive:
        serve_state = "not_running"

    return {
        "ok": True,
        "workspace": name,
        "state": serve_state,
        "serveUp": alive,
        "claudeUp": False,
        "servePid": pid,
        "packages": packages,
        "errors": errors,
        "urls": _derive_urls_for(name),
        "pkgPaths": state.get("pkgPaths", []),
        "bendRegistered": bool(state.get("bendRegistered")),
        "allReady": serve_state == "ready",
    }
