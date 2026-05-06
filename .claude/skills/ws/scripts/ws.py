#!/usr/bin/env python3
# /// script
# requires-python = ">=3.9"
# dependencies = []
# ///
"""ws.py — workspace manager CLI entry point.

Single command-dispatch + argparse module. The heavy logic lives in
`ws_lib.py` (pure helpers) and `ws_supervise.py` (bend-serve supervision,
filesystem-backed, no daemon).

Conventions:
- All subcommands emit JSON to stdout. Human-readable progress → stderr.
- Recoverable errors return {"ok": false, "error": ...}. Only argparse
  errors exit non-zero.
- Stdlib only — no PyYAML, no psutil, no requests.

Usage:
    uv run ws.py plan <name> <repo[:branch]>...
    uv run ws.py init <name>
    uv run ws.py setup <name>
    uv run ws.py add <name> <repo[:branch]>...
    uv run ws.py status <name>
    uv run ws.py wait-ready <name> [--timeout 600]
    uv run ws.py urls <name>
    uv run ws.py logs <name> [--tail N] [--grep P]
    uv run ws.py stop <name>
    uv run ws.py restart <name>
    uv run ws.py nuke <name> [--delete-branches]
    uv run ws.py discover <repo-path>
    uv run ws.py prefs get
    uv run ws.py prefs set-repo-memory <repo> <MB>
"""

import argparse
import concurrent.futures
import os
import pathlib
import re
import shutil
import sys
import time

from ws_lib import (
    BEND_REGISTRATION_TIMEOUT_S,
    DEFAULT_BRANCH_PREFIX,
    LOG_TAIL_BYTES,
    SRC_ROOT,
    WS_ROOT,
    WS_PREFERENCES_PATH,
    active_workspaces_memory,
    bend_yarn,
    checkout_branch,
    clone_repo,
    current_branch,
    discover_repo,
    emit,
    emit_error,
    git,
    has_claude_md,
    list_package_dirs,
    load_discovery_cache,
    load_preferences,
    log,
    max_total_node_memory,
    normalize,
    parse_repo_arg,
    resolve_remote,
    save_preferences,
    select_packages,
    serve_log_path,
    tmux,
    tmux_has_session,
    ws_dir,
    _provision_workspace_claude_dir,
)
import ws_supervise


# ---------------------------------------------------------------- Command: gc

def _gc_stale_states():
    """Clear state files for workspaces whose serve process is no longer alive.
    Returns names of workspaces whose stale state was cleared."""
    if not WS_ROOT.exists():
        return []
    cleaned = []
    for ws in sorted(WS_ROOT.iterdir()):
        if not ws.is_dir() or ws.name.startswith("."):
            continue
        if not (ws / ".ws-serve.json").exists():
            continue
        resp = ws_supervise.stop_serve(ws.name)
        if resp.get("ok") and not resp.get("wasRunning"):
            cleaned.append(ws.name)
    return cleaned


def cmd_gc(args):
    cleaned = _gc_stale_states()
    emit({"ok": True, "cleaned": cleaned, "count": len(cleaned)})


# ---------------------------------------------------------------- Command: plan

def cmd_plan(args):
    cleaned = _gc_stale_states()
    if cleaned:
        log(f"gc: cleared stale state for: {', '.join(cleaned)}")

    name = normalize(args.name)
    repos = []
    for arg in args.repos:
        repo, branch = parse_repo_arg(arg, default_branch=f"{DEFAULT_BRANCH_PREFIX}{name}")
        remote = resolve_remote(repo)
        repos.append({
            "repo": repo,
            "branch": branch,
            "remote": remote,
            "remoteResolved": remote is not None,
            "srcExists": (SRC_ROOT / repo).exists(),
        })

    existing = ws_dir(name).exists()

    missing = [r for r in repos if not r["remoteResolved"]]
    ok = len(missing) == 0

    emit({
        "ok": ok,
        "workspace": name,
        "tmuxSession": name,
        "repos": repos,
        "existing": existing,
        "gcCleaned": cleaned or None,
        "error": "unresolved-remotes" if missing else None,
        "missingRepos": [r["repo"] for r in missing] or None,
    })


# ---------------------------------------------------------------- Command: init

def _compute_pkg_paths(name, setup_results):
    wsdir = ws_dir(name)
    pkg_paths = []
    for r in setup_results:
        if not r.get("ok"):
            continue
        discovery = r.get("discovery") or {}
        defaults = select_packages(discovery)
        repo_path = wsdir / r["repo"]
        if list_package_dirs(repo_path):
            for pkg in defaults:
                pkg_paths.append(repo_path / pkg)
        else:
            pkg_paths.append(repo_path)
    return pkg_paths


def cmd_init(args):
    name = normalize(args.name)
    tmux_session = name
    wsdir = ws_dir(name)
    prompt_file = wsdir / "INIT-PROMPT.txt"

    wsdir.mkdir(parents=True, exist_ok=True)
    _provision_workspace_claude_dir(wsdir)

    if args.prompt:
        prompt_file.write_text(args.prompt)
    elif not prompt_file.exists():
        emit_error(
            f"no --prompt provided and no existing prompt at {prompt_file}. "
            "Pass --prompt, or re-run after writing INIT-PROMPT.txt manually.",
            recoverable=False,
        )
        sys.exit(1)

    # If repos were specified, do the full setup BEFORE launching the workspace
    # Claude. This ensures bend reactor serve has registered with route-configs
    # by the time the workspace Claude spawns its devex-mcp-server, so the
    # bend_* MCP tools are actually available to it.
    setup_results = None
    if args.repos:
        repo_specs = []
        for arg in args.repos:
            repo, branch = parse_repo_arg(arg, default_branch=f"{DEFAULT_BRANCH_PREFIX}{name}")
            remote = resolve_remote(repo)
            if not remote:
                emit_error(f"could not resolve remote for {repo}", recoverable=False)
                return
            repo_specs.append({"repo": repo, "remote": remote, "branch": branch})

        log(f"init: setting up {len(repo_specs)} repos (clone + yarn + discover)...")
        setup_results = _setup_repos(name, repo_specs)

        pkg_paths = _compute_pkg_paths(name, setup_results)
        if pkg_paths:
            log(f"init: starting serve for {len(pkg_paths)} packages...")
            resp = ws_supervise.start_serve(
                name,
                [str(p) for p in pkg_paths],
                timeout=BEND_REGISTRATION_TIMEOUT_S,
                node_memory=args.node_memory,
            )
            if not resp.get("ok"):
                emit_error(f"start_serve failed: {resp.get('error')}")
                return
        else:
            log("init: no packages to serve; skipping serve launch")

    # Write launcher and launch workspace Claude via hsclaude (dvx wrapper)
    # so its MCP servers (devex-mcp-server) are wired up correctly.
    launcher = pathlib.Path(f"/tmp/ws-{name}-launch.sh")
    launcher.write_text(
        "#!/bin/bash\n"
        f'PROMPT=$(cat "{prompt_file}")\n'
        f'rm -f "{launcher}"\n'
        f'if command -v hsclaude >/dev/null 2>&1; then\n'
        f'  exec hsclaude --name "{name}" "$PROMPT"\n'
        f'else\n'
        f'  exec claude --name "{name}" "$PROMPT"\n'
        f'fi\n'
    )
    launcher.chmod(0o755)

    if tmux_has_session(tmux_session):
        emit({
            "ok": True,
            "workspace": name,
            "tmuxSession": tmux_session,
            "note": "tmux session already existed; launcher not re-run",
            "setup": setup_results,
        })
        return

    tmux("new-session", "-d", "-s", tmux_session, "-n", name, "-c", str(wsdir))
    tmux("send-keys", "-t", f"{tmux_session}:{name}", f"bash {launcher}", "Enter")

    emit({
        "ok": True,
        "workspace": name,
        "tmuxSession": tmux_session,
        "workspaceDir": str(wsdir),
        "setup": setup_results,
    })


# ---------------------------------------------------------------- Command: setup

def _setup_repos(name, repo_specs, existing_only=False):
    """Shared logic for setup/add. Returns per-repo results."""
    wsdir = ws_dir(name)
    results = []

    # Clone in parallel
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as ex:
        clone_futures = {}
        for spec in repo_specs:
            dest = wsdir / spec["repo"]
            fut = ex.submit(clone_repo, spec["remote"], dest, spec["branch"])
            clone_futures[spec["repo"]] = fut
        clone_results = {repo: fut.result() for repo, fut in clone_futures.items()}

    # Checkout in parallel
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as ex:
        co_futures = {}
        for spec in repo_specs:
            cr = clone_results[spec["repo"]]
            if not cr.get("ok"):
                continue
            dest = wsdir / spec["repo"]
            co_futures[spec["repo"]] = ex.submit(checkout_branch, dest, spec["branch"])
        checkout_results = {repo: fut.result() for repo, fut in co_futures.items()}

    # bend yarn in parallel
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as ex:
        yarn_futures = {}
        for spec in repo_specs:
            cr = clone_results[spec["repo"]]
            if not cr.get("ok"):
                continue
            dest = wsdir / spec["repo"]
            yarn_futures[spec["repo"]] = ex.submit(bend_yarn, dest)
        yarn_results = {repo: fut.result() for repo, fut in yarn_futures.items()}

    # Discovery (serial — shared cache file, cheap anyway)
    for spec in repo_specs:
        repo = spec["repo"]
        cr = clone_results[repo]
        if not cr.get("ok"):
            results.append({
                "repo": repo, "ok": False,
                "clone": cr, "checkout": None, "yarn": None, "discovery": None,
            })
            continue
        dest = wsdir / repo
        discovery = discover_repo(dest, name)
        results.append({
            "repo": repo,
            "ok": yarn_results.get(repo, {}).get("ok", False),
            "clone": cr,
            "checkout": checkout_results.get(repo),
            "yarn": yarn_results.get(repo),
            "discovery": discovery,
            "claudeMd": has_claude_md(dest),
        })
    return results


def cmd_setup(args):
    name = normalize(args.name)
    wsdir = ws_dir(name)
    if not wsdir.exists():
        emit_error(f"workspace dir does not exist: {wsdir}", recoverable=False)
        sys.exit(1)

    # Derive repo specs from the handoff prompt's repos — but we don't see the prompt.
    # Instead: treat every direct child dir of wsdir as a repo to set up.
    # This makes setup idempotent: re-running picks up any repos added since.
    repo_dirs = [p for p in wsdir.iterdir() if p.is_dir() and not p.name.startswith(".")]
    if not repo_dirs:
        emit_error(f"no repos found in {wsdir}", recoverable=True,
                   hint="call 'ws.py add <name> <repo[:branch]>...' instead")
        return

    repo_specs = []
    skipped = []
    for d in repo_dirs:
        repo = d.name
        remote = resolve_remote(repo)
        if not remote:
            log(f"WARN: no remote found for {repo}")
            skipped.append({"repo": repo, "reason": "no-remote"})
            continue
        branch = current_branch(d) or f"{DEFAULT_BRANCH_PREFIX}{name}"
        repo_specs.append({"repo": repo, "remote": remote, "branch": branch})

    results = _setup_repos(name, repo_specs)
    pkg_paths = _compute_pkg_paths(name, results)

    serve_started = False
    serve_error = None
    if pkg_paths:
        log(f"setup: starting serve for {len(pkg_paths)} packages...")
        resp = ws_supervise.start_serve(
            name,
            [str(p) for p in pkg_paths],
            timeout=BEND_REGISTRATION_TIMEOUT_S,
            node_memory=getattr(args, "node_memory", None),
        )
        serve_started = bool(resp.get("ok"))
        if not serve_started:
            serve_error = resp.get("error")

    emit({
        "ok": all(r.get("ok") for r in results) and (not pkg_paths or serve_started),
        "workspace": name,
        "workspaceDir": str(wsdir),
        "repos": results,
        "skippedRepos": skipped,
        "servePackages": [str(p) for p in pkg_paths],
        "serveStarted": serve_started,
        "serveError": serve_error,
    })


# ---------------------------------------------------------------- Command: add

def cmd_add(args):
    name = normalize(args.name)
    wsdir = ws_dir(name)
    if not wsdir.exists():
        emit_error(f"workspace dir does not exist: {wsdir}", recoverable=False)
        sys.exit(1)

    repo_specs = []
    for arg in args.repos:
        repo, branch = parse_repo_arg(arg, default_branch=f"{DEFAULT_BRANCH_PREFIX}{name}")
        remote = resolve_remote(repo)
        if not remote:
            emit_error(f"could not resolve remote for {repo}", recoverable=False)
            return
        repo_specs.append({"repo": repo, "remote": remote, "branch": branch})

    results = _setup_repos(name, repo_specs)

    # Restart serve with ALL packages (existing + new).
    # Build repo-like entries from every dir in the workspace so
    # _compute_pkg_paths covers both old and new repos.
    all_repo_dirs = [p for p in wsdir.iterdir() if p.is_dir() and not p.name.startswith(".")]
    cache = load_discovery_cache()
    all_results = [
        {"repo": d.name, "ok": True, "discovery": cache.get(d.name, {})}
        for d in all_repo_dirs
    ]
    pkg_paths = _compute_pkg_paths(name, all_results)

    serve_restarted = False
    serve_error = None
    if pkg_paths:
        log(f"add: restarting serve for {len(pkg_paths)} packages...")
        resp = ws_supervise.restart_serve(
            name,
            [str(p) for p in pkg_paths],
            timeout=BEND_REGISTRATION_TIMEOUT_S,
            node_memory=getattr(args, "node_memory", None),
        )
        serve_restarted = bool(resp.get("ok"))
        if not serve_restarted:
            serve_error = resp.get("error")

    emit({
        "ok": all(r.get("ok") for r in results) and (not pkg_paths or serve_restarted),
        "workspace": name,
        "added": [r["repo"] for r in results],
        "repos": results,
        "servePackages": [str(p) for p in pkg_paths],
        "serveRestarted": serve_restarted,
        "serveError": serve_error,
    })


# ---------------------------------------------------------------- Command: list

def cmd_list(args):
    if not WS_ROOT.exists():
        emit({"ok": True, "workspaces": [], "activeTotalNodeMemoryMB": 0})
        return

    import json as _json
    active_map = {w["name"]: w for w in active_workspaces_memory()}
    workspaces = []
    for ws in sorted(WS_ROOT.iterdir()):
        if not ws.is_dir() or ws.name.startswith("."):
            continue
        state_path = ws / ".ws-serve.json"
        state = None
        if state_path.exists():
            try:
                state = _json.loads(state_path.read_text())
            except (OSError, _json.JSONDecodeError):
                pass
        active = active_map.get(ws.name)
        repos = sorted(
            d.name for d in ws.iterdir()
            if d.is_dir() and not d.name.startswith(".")
        )
        workspaces.append({
            "name": ws.name,
            "alive": active is not None,
            "pid": active["pid"] if active else (state.get("pid") if state else None),
            "nodeMemoryMB": active["nodeMemory"] if active else (state.get("nodeMemory") if state else None),
            "staleStateFile": state is not None and active is None,
            "repos": repos,
        })

    active_total = sum(w["nodeMemory"] for w in active_map.values())
    limit = max_total_node_memory()
    emit({
        "ok": True,
        "workspaces": workspaces,
        "activeTotalNodeMemoryMB": active_total,
        "limitMB": limit,
        "headroomMB": limit - active_total,
    })


# ---------------------------------------------------------------- Command: status

def cmd_status(args):
    name = normalize(args.name)
    resp = ws_supervise.status(name)
    resp.setdefault("allReady", resp.get("state") == "ready")
    emit(resp)


# ---------------------------------------------------------------- Command: wait-ready

def cmd_wait_ready(args):
    name = normalize(args.name)
    started = time.time()
    deadline = started + args.timeout
    last_state = None
    poll_interval = 5
    heartbeat_interval = 15
    last_heartbeat = started
    log(f"[{name}] wait-ready started (timeout={args.timeout}s, poll={poll_interval}s)")

    while time.time() < deadline:
        resp = ws_supervise.status(name)
        state = resp.get("state", "not_running")
        if state == "ready":
            elapsed = int(time.time() - started)
            log(f"[{name}] ready after {elapsed}s")
            cmd_status(args)
            return
        if state == "error":
            log(f"[{name}] reached error state; aborting wait")
            cmd_status(args)
            return
        if state != last_state:
            log(f"[{name}] state={state}")
            last_state = state
        now = time.time()
        if now - last_heartbeat >= heartbeat_interval:
            elapsed = int(now - started)
            remaining = int(deadline - now)
            pkgs = resp.get("packages") or []
            pkgs_done = sum(1 for p in pkgs if p.get("compiled"))
            pkgs_total = len(pkgs)
            log(
                f"[{name}] still waiting: elapsed={elapsed}s remaining={remaining}s "
                f"state={state} packages={pkgs_done}/{pkgs_total}"
            )
            last_heartbeat = now
        time.sleep(poll_interval)

    log(f"[{name}] timeout after {args.timeout}s")
    cmd_status(args)


# ---------------------------------------------------------------- Command: urls

def cmd_urls(args):
    name = normalize(args.name)
    wsdir = ws_dir(name)
    out = {"workspace": name, "urls": [], "testUrls": []}
    if not wsdir.exists():
        emit_error(f"workspace dir does not exist: {wsdir}", recoverable=False)
        return

    for d in sorted(wsdir.iterdir()):
        if not d.is_dir() or d.name.startswith("."):
            continue
        # Re-resolve on demand so URLs refresh when quartz finally compiles
        discovery = discover_repo(d, name)
        for pkg in discovery["packages"]:
            info = discovery["resolved"].get(pkg["name"], {})
            if info.get("browseable", True):
                out["urls"].append({
                    "package": pkg["name"],
                    "repo": d.name,
                    "url": info.get("url"),
                    "ready": info.get("ready", False),
                    "lb": info.get("lb"),
                    "basename": info.get("basename"),
                })
            out["testUrls"].append({
                "package": pkg["name"],
                "repo": d.name,
                "url": f"https://{name}.local.hsappstatic.net/{pkg['name']}/static/test/test.html",
            })
    out["ok"] = True
    emit(out)


# ---------------------------------------------------------------- Command: discover

def cmd_discover(args):
    path = pathlib.Path(args.repo_path).expanduser().resolve()
    if not path.exists():
        emit_error(f"repo path does not exist: {path}", recoverable=False)
        return
    # Workspace name for URL construction: try to infer from path
    try:
        rel = path.relative_to(WS_ROOT)
        workspace_name = rel.parts[0] if rel.parts else "unknown"
    except ValueError:
        workspace_name = args.workspace or "unknown"
    result = discover_repo(path, workspace_name)
    emit({"ok": True, **result})


# ---------------------------------------------------------------- Command: logs

def cmd_logs(args):
    name = normalize(args.name)
    log_path = serve_log_path(name)
    if not log_path.exists():
        emit_error(f"no serve log at {log_path}", recoverable=True)
        return

    tail_n = args.tail or 200
    grep = args.grep

    total_bytes = os.path.getsize(log_path)
    # Read more than tail_n to have enough lines after grep
    with open(log_path, "r", errors="replace") as f:
        if total_bytes > LOG_TAIL_BYTES:
            f.seek(total_bytes - LOG_TAIL_BYTES)
            f.readline()
        all_lines = f.read().split("\n")
    tail_only = total_bytes > LOG_TAIL_BYTES

    if grep:
        try:
            pat = re.compile(grep, re.IGNORECASE)
        except re.error as e:
            emit_error(f"bad regex: {e}", recoverable=False)
            return
        matched = [l for l in all_lines if pat.search(l)]
        result_lines = matched[-tail_n:]
        truncated = len(matched) > tail_n
        total_matches = len(matched)
    else:
        result_lines = all_lines[-tail_n:]
        truncated = len(all_lines) > tail_n
        total_matches = None

    emit({
        "ok": True,
        "workspace": name,
        "logPath": str(log_path),
        "logBytes": total_bytes,
        "lines": result_lines,
        "tailOnly": tail_only,
        "truncated": truncated,
        "totalMatches": total_matches,
    })


# ---------------------------------------------------------------- Command: stop

def cmd_stop(args):
    name = normalize(args.name)
    resp = ws_supervise.stop_serve(name)
    if not resp.get("ok"):
        emit_error(f"stop_serve failed: {resp.get('error')}")
        return
    emit(resp)


# ---------------------------------------------------------------- Command: restart

def cmd_restart(args):
    name = normalize(args.name)
    wsdir = ws_dir(name)
    if not wsdir.exists():
        emit_error(f"workspace dir does not exist: {wsdir}", recoverable=False)
        return

    cache = load_discovery_cache()
    pkg_paths = []
    for d in sorted(wsdir.iterdir()):
        if not d.is_dir() or d.name.startswith("."):
            continue
        entry = cache.get(d.name, {})
        defaults = [p["name"] for p in entry.get("packages", []) if p.get("isDefault")]
        if list_package_dirs(d):
            for pkg in defaults:
                pkg_paths.append(d / pkg)
        else:
            pkg_paths.append(d)

    if not pkg_paths:
        emit_error(f"no packages found in {wsdir} to serve", recoverable=True)
        return

    log(f"restart: restarting serve for {len(pkg_paths)} packages...")
    resp = ws_supervise.restart_serve(
        name,
        [str(p) for p in pkg_paths],
        timeout=BEND_REGISTRATION_TIMEOUT_S,
        node_memory=getattr(args, "node_memory", None),
    )
    if not resp.get("ok"):
        emit_error(f"restart_serve failed: {resp.get('error')}")
        return

    emit({
        "ok": True,
        "workspace": name,
        "servePackages": [str(p) for p in pkg_paths],
        "servePid": resp.get("servePid"),
        "bendRegistered": resp.get("bendRegistered"),
    })


# ---------------------------------------------------------------- Command: prefs

def cmd_prefs(args):
    prefs = load_preferences()

    if args.action == "get":
        emit({"ok": True, "path": str(WS_PREFERENCES_PATH), "prefs": prefs})
        return

    if args.action == "set-repo-memory":
        repo = args.repo
        memory = args.memory
        repos = prefs.setdefault("repos", {})
        repos.setdefault(repo, {})["nodeMemory"] = memory
        save_preferences(prefs)
        emit({"ok": True, "repo": repo, "nodeMemory": memory, "path": str(WS_PREFERENCES_PATH)})
        return

    if args.action == "set-max-memory":
        memory = args.memory
        prefs["maxTotalNodeMemory"] = memory
        save_preferences(prefs)
        emit({"ok": True, "maxTotalNodeMemory": memory, "path": str(WS_PREFERENCES_PATH)})
        return

    emit_error(f"unknown prefs action: {args.action}", recoverable=False)


# ---------------------------------------------------------------- Command: nuke

def cmd_nuke(args):
    name = normalize(args.name)
    wsdir = ws_dir(name)
    actions = []

    stop_resp = ws_supervise.stop_serve(name)
    if stop_resp.get("ok"):
        actions.append(f"stop_serve: wasRunning={stop_resp.get('wasRunning')}")
    else:
        actions.append(f"stop_serve failed: {stop_resp.get('error')}")

    if tmux_has_session(name):
        tmux("kill-session", "-t", name)
        actions.append(f"killed session {name}")

    branches_deleted = []
    if args.delete_branches and wsdir.exists():
        for d in wsdir.iterdir():
            if not d.is_dir() or d.name.startswith("."):
                continue
            branch = current_branch(d)
            if branch and branch.startswith(DEFAULT_BRANCH_PREFIX):
                src_clone = SRC_ROOT / d.name
                if src_clone.exists():
                    result = git(src_clone, "branch", "-D", branch)
                    if result.returncode == 0:
                        branches_deleted.append(f"{d.name}:{branch}")

    if wsdir.exists():
        shutil.rmtree(wsdir)
        actions.append(f"removed {wsdir}")

    emit({
        "ok": True,
        "workspace": name,
        "actions": actions,
        "branchesDeleted": branches_deleted,
    })


# ---------------------------------------------------------------- Command: help

HELP_TOPICS = {
    "monitor": """\
AI AGENT: BACKGROUND MONITOR SPEC
===================================
When the user asks to monitor a workspace, launch a background agent with:

  Monitor workspace <NAME>. Every 60s run `ws.py status <NAME>`.
  - state: error + EADDRINUSE  → ws.py restart <NAME>; cap at 3 restarts, then escalate.
  - state: error (other)       → stop monitoring; report unhealthy (use `ws.py help templates`).
  - state: stale               → ws.py stop <NAME> and alert; do NOT auto-restart.
  - new fatal errors mid-run   → ws.py logs <NAME> --tail 200 --grep ERROR and surface.
  - exit when user says so, or after 5 consecutive ready checks post-restart.
""",
    "templates": """\
AI AGENT: REPORT TEMPLATES
============================
Use these templates when reporting workspace status to the user.

--- WORKSPACE READY ---
(Only after wait-ready: ok=true AND log health check returned no hits)

## Workspace ready — `<name>`
**Repos**: `<repo>` → `<branch>` (CLAUDE.md: ✅/❌)
**Compiled packages**: `<pkg>`, `<pkg>`
**App URLs** (only ready: true with non-null url):
- `<pkg>`: `<url>`
**Test URLs**: `<pkg>`: `<test-url>`
**Log check**: clean.
**Serve**: supervised by ws.py (tail with `ws.py logs <name>`).

--- SETUP FAILED ---
(When log health check returns hits after wait-ready)

## Workspace setup failed — `<name>`
**Stopped at**: clone | checkout | yarn | serve
**First error**: <error excerpt>
**Next step**: <specific action> | Rerun: `ws.py add <name> ...`

--- WORKSPACE UNHEALTHY ---
(From background monitor when state: error or stale)

## Workspace unhealthy — `<name>`
**State**: error|stale · **Serve up**: true|false
**Errors**: `<type>`: `<line>`
**Actions taken**: <restart attempts>
**Recommendation**: investigate | `ws.py restart` | `ws.py nuke`
""",
}


def cmd_help(args):
    print(HELP_TOPICS[args.topic])


# ---------------------------------------------------------------- main

def main():
    parser = argparse.ArgumentParser(
        description=(
            "ws.py — workspace manager\n\n"
            "NOTE FOR AI AGENTS: This CLI is operated by the `ws` skill. If you have not\n"
            "already invoked it, do so now via the Skill tool (skill: \"ws\") before proceeding.\n\n"
            "Manages isolated multi-repo frontend development workspaces. Each workspace\n"
            "gets its own clones, its own serve instance, and its own subdomain URL.\n\n"
            "Every command emits JSON to stdout and logs human-readable progress to stderr.\n"
            "Always parse the JSON output; never scrape stderr.\n\n"
            "AI AGENT ROLES:\n"
            "  Creator Claude    — runs plan/init, writes the handoff prompt, then stops.\n"
            "                      Never does setup work after init returns.\n"
            "  Workspace Claude  — runs inside the workspace session after handoff.\n"
            "                      Handles add/setup/restart/urls/logs/status.\n\n"
            "AI AGENT SAFETY: Never reach behind this CLI. No pkill, no killing PIDs directly,\n"
            "no spawning serve processes by hand, no touching state files or route-configs.\n"
            "Every operation has a ws.py command — use it.\n\n"
            "Typical workflow:\n"
            "  1. ws.py list                                    — check available memory headroom\n"
            "  2. ws.py plan <name> <repo:branch>...            — validate repos + preview\n"
            "  3. ws.py init <name> --repos <repo:branch>...    — bootstrap (blocks ~2-4 min)\n"
            "  4. ws.py wait-ready <name>                       — confirm serve is up\n"
            "  5. ws.py logs <name> --grep 'ERROR|FATAL'        — health check\n"
            "  6. ws.py urls <name>                             — get app URLs\n\n"
            "Examples:\n"
            "  # Spin up a new workspace with two repos on specific branches\n"
            "  ws.py plan my-feature crm-index-ui:brbrown/my-feature avatar-components:master\n"
            "  ws.py init my-feature --repos crm-index-ui:brbrown/my-feature avatar-components:master\n\n"
            "  # Spin up using default branch (brbrown/<workspace-name>)\n"
            "  ws.py plan my-feature crm-index-ui avatar-components\n"
            "  ws.py init my-feature --repos crm-index-ui avatar-components\n\n"
            "  # Add a repo to an existing workspace\n"
            "  ws.py add my-feature customer-data-properties:brbrown/my-feature\n\n"
            "  # Inspect and recover a workspace\n"
            "  ws.py status my-feature\n"
            "  ws.py restart my-feature\n\n"
            "  # Resume after a reboot (files exist, serve is down)\n"
            "  ws.py setup my-feature\n\n"
            "  # Memory is tight — free a workspace or raise the cap\n"
            "  ws.py nuke old-workspace          # confirm with user first\n"
            "  ws.py prefs set-max-memory 32768\n\n"
            "Run `ws.py <cmd> --help` for full details on any command."
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    sub = parser.add_subparsers(dest="command", required=True)

    RD = argparse.RawDescriptionHelpFormatter

    p = sub.add_parser(
        "plan",
        help="Validate + preview a workspace plan without creating anything.",
        description=(
            "Resolves repo names to remotes and branches, validates that all repos exist under ~/src/,\n"
            "and prints a preview plan as JSON. Does NOT clone, yarn, or start serve.\n\n"
            "PREREQUISITE: each repo must already be cloned into ~/src/<repo>/ before plan can\n"
            "resolve it. plan does not clone — it validates against existing checkouts.\n\n"
            "Note: repos are positional args here (ws.py plan <name> <repo:branch> ...),\n"
            "but init takes them as --repos (ws.py init <name> --repos <repo:branch> ...).\n\n"
            "Run this before `init` to catch typos in repo/branch names early.\n"
            "Also runs `gc` automatically to clear stale state.\n\n"
            "JSON output fields:\n"
            "  ok            — false if any repos couldn't be resolved (see missingRepos)\n"
            "  workspace     — normalized workspace name (spaces → hyphens)\n"
            "  existing      — true if a workspace with this name already exists\n"
            "  repos         — list of {repo, branch, remote} resolved entries\n"
            "  missingRepos  — repos that couldn't be matched to ~/src/<repo>/"
        ),
        formatter_class=RD,
    )
    p.add_argument("name")
    p.add_argument("repos", nargs="+", metavar="repo[:branch]")

    p = sub.add_parser(
        "init",
        help="Clone + yarn + start serve + launch workspace Claude in a new tmux session.",
        description=(
            "Full workspace bootstrap. Blocks for ~2-4 min while it:\n"
            "  1. Clones each repo to ~/src/workspaces/<name>/<repo>/\n"
            "  2. Runs yarn install\n"
            "  3. Starts bend reactor serve (supervised, with BEND_WORKTREE=<name>)\n"
            "  4. Waits for bend to register in ~/.hubspot/route-configs/\n"
            "  5. Launches workspace Claude inside a new tmux session named <name>\n\n"
            "The prompt is written to <workspace>/INIT-PROMPT.txt and persists there.\n"
            "If --prompt is omitted and INIT-PROMPT.txt already exists, init reuses it (re-init).\n"
            "After init returns, the CREATOR is done — do not do any further setup work.\n\n"
            "AI AGENTS (CREATOR): Run 'ws.py list' first and check headroomMB — if insufficient,\n"
            "nuke an old workspace or raise the cap with 'ws.py prefs set-max-memory'.\n"
            "After init returns, creator is done — do not do further setup work.\n\n"
            "Note: init takes repos as --repos (ws.py init <name> --repos <repo:branch> ...),\n"
            "unlike plan which takes them as positional args.\n\n"
            "After init returns, switch to the workspace and run these in sequence:\n"
            "  ws.py wait-ready <name>\n"
            "  ws.py logs <name> --tail 200 --grep 'ERROR|FATAL|EADDRINUSE|Cannot find module'\n"
            "  ws.py urls <name>\n\n"
            "JSON output fields:\n"
            "  ok            — false if clone/yarn/serve failed\n"
            "  tmuxSession   — name of the tmux session to switch to\n"
            "  urls          — {app, test} URLs once serve registers"
        ),
        formatter_class=RD,
    )
    p.add_argument("name")
    p.add_argument(
        "--prompt", default=None,
        help="Handoff prompt text for workspace Claude. Written to <workspace>/INIT-PROMPT.txt "
             "and persists there. If omitted, reuses an existing INIT-PROMPT.txt (re-init).",
    )
    p.add_argument(
        "--repos", nargs="+", default=None, metavar="repo:branch",
        help="Repo specs (repo[:branch]). Required for full setup.",
    )
    p.add_argument(
        "--node-memory", type=int, default=None, dest="node_memory",
        help="Node heap limit in MB for webpack (default: from ws-preferences.json or 4096). "
             "Use 16384 for crm-index-ui and other memory-hungry repos.",
    )

    p = sub.add_parser(
        "setup",
        help="Re-run clone + yarn + discover + serve for an existing workspace directory.",
        description=(
            "Recovers a workspace whose files still exist but serve is down.\n"
            "Runs clone (idempotent), yarn, package discovery, and starts serve.\n"
            "Does NOT relaunch workspace Claude.\n\n"
            "Use this when:\n"
            "  - Serve crashed and `restart` isn't recovering it\n"
            "  - You manually stopped serve and want to bring it back\n"
            "  - You're resuming work after a reboot\n\n"
            "AI AGENTS: If the JSON output contains a non-empty 'skippedRepos' field,\n"
            "surface it to the user and ask for confirmation before continuing.\n\n"
            "JSON output fields:\n"
            "  ok            — false if any step failed\n"
            "  skippedRepos  — [{repo, reason}] repos that couldn't be resolved; surface and confirm before continuing"
        ),
        formatter_class=RD,
    )
    p.add_argument("name")
    p.add_argument(
        "--node-memory", type=int, default=None, dest="node_memory",
        help="Node heap limit in MB (default: from prior state or 4096).",
    )

    p = sub.add_parser(
        "add",
        help="Add one or more repos to an existing workspace.",
        description=(
            "Clones, yarns, discovers packages for each new repo, then restarts serve\n"
            "with the combined package list. Idempotent — skips repos already cloned.\n\n"
            "AI AGENTS (CREATOR): Do not run this from the creator context. Tell the user\n"
            "to switch to the workspace session and ask workspace Claude to run it.\n\n"
            "AI AGENTS: If the JSON output contains a non-empty 'skippedRepos' field,\n"
            "surface it to the user and ask for confirmation before continuing.\n\n"
            "JSON output fields:\n"
            "  ok            — false if any step failed\n"
            "  added         — repos that were newly cloned\n"
            "  skipped       — repos already present (idempotent skip)\n"
            "  skippedRepos  — repos that couldn't be resolved; surface these and confirm before continuing"
        ),
        formatter_class=RD,
    )
    p.add_argument("name")
    p.add_argument("repos", nargs="+", metavar="repo[:branch]")
    p.add_argument(
        "--node-memory", type=int, default=None, dest="node_memory",
        help="Node heap limit in MB (default: reuse prior state or 4096).",
    )

    sub.add_parser(
        "gc",
        help="Clear stale state files for workspaces whose serve process is dead.",
        description=(
            "Scans ~/src/workspaces/ for .ws-serve.json state files whose recorded serve PID\n"
            "is no longer running, and removes them. Safe to run at any time.\n"
            "Also runs automatically at the start of `plan`.\n\n"
            "Use this if `list` shows workspaces as alive when they aren't."
        ),
        formatter_class=RD,
    )

    sub.add_parser(
        "list",
        help="List all workspaces with memory usage and serve state.",
        description=(
            "Prints a JSON array of all known workspaces.\n\n"
            "Per-workspace fields:\n"
            "  name          — workspace name\n"
            "  alive         — true if serve PID is still running\n"
            "  nodeMemoryMB  — Node heap limit for this workspace's serve\n"
            "  staleStateFile — true if state file exists but PID is dead (run `gc` to clean)\n"
            "  repos         — list of {repo, branch} cloned into this workspace\n\n"
            "Summary fields:\n"
            "  totalMemoryMB — sum of nodeMemoryMB across all alive workspaces\n"
            "  limitMB       — configured max (from ws-preferences.json, default 24576)\n"
            "  headroomMB    — limitMB minus totalMemoryMB; must be >= new workspace's memory\n\n"
            "Default per-workspace memory is 4096 MB unless overridden via `prefs set-repo-memory`.\n"
            "Memory-hungry repos (e.g. crm-index-ui) typically need 16384 MB."
        ),
        formatter_class=RD,
    )

    p = sub.add_parser(
        "status",
        help="Workspace status snapshot (JSON).",
        description=(
            "Returns a point-in-time JSON snapshot of one workspace.\n\n"
            "Key fields:\n"
            "  state         — 'ready' | 'starting' | 'error' | 'stale'\n"
            "  serveUp       — true if bend's HTTP server is accepting connections\n"
            "  packages      — list of compiled packages\n"
            "  errors        — recent error lines from the serve log\n"
            "  urls          — {app, test} URL map\n\n"
            "Use before `restart` or `nuke` to understand what's actually wrong.\n"
            "If state is 'error', read `errors` and try `restart` before escalating.\n\n"
            "AI AGENTS: Bend MCP tools require state: 'ready'. If Bend tools are unavailable,\n"
            "check this output before assuming an environment problem."
        ),
        formatter_class=RD,
    )
    p.add_argument("name")

    p = sub.add_parser(
        "wait-ready",
        help="Block until serve reaches 'ready' state (or timeout).",
        description=(
            "Polls ws.py status every ~5s until state is 'ready' or the timeout expires.\n"
            "Logs progress to stderr every ~15s — silence does NOT mean it's stuck.\n\n"
            "IMPORTANT:\n"
            "  - Do NOT run multiple wait-ready calls in parallel for the same workspace.\n"
            "  - Do NOT run logs or urls in parallel with wait-ready.\n"
            "  - Run sequentially: wait-ready → logs → urls.\n\n"
            "If timeout expires (ok: false), check `ws.py logs <name> --grep ERROR` and\n"
            "`ws.py status <name>` to diagnose. Then try `ws.py restart <name>`.\n\n"
            "AI AGENTS: After this returns ok: true, always run the log health check before\n"
            "reporting the workspace as ready:\n"
            "  ws.py logs <name> --tail 200 --grep 'ERROR|FATAL|EADDRINUSE|Cannot find module'\n"
            "A non-empty result means setup failed — do not report the workspace as ready.\n\n"
            "JSON output fields:\n"
            "  ok      — true if state reached 'ready' within timeout\n"
            "  state   — final state seen\n"
            "  elapsed — seconds waited"
        ),
        formatter_class=RD,
    )
    p.add_argument("name")
    p.add_argument("--timeout", type=int, default=600, help="Max seconds to wait (default: 600).")

    p = sub.add_parser(
        "urls",
        help="Resolved app + test URLs for a workspace.",
        description=(
            "Returns the app and test URLs for each package in the workspace.\n"
            "Only entries with ready: true and a non-null url field are usable.\n\n"
            "Use the `url` field verbatim as the base URL for QA testing.\n"
            "Run only after wait-ready returns successfully."
        ),
        formatter_class=RD,
    )
    p.add_argument("name")

    p = sub.add_parser(
        "logs",
        help="Read or grep the bend serve log.",
        description=(
            "Reads the last N lines of the serve log, optionally filtered by a regex.\n\n"
            "Recommended health-check pattern:\n"
            "  ws.py logs <name> --tail 200 --grep 'ERROR|FATAL|EADDRINUSE|Cannot find module'\n\n"
            "--grep accepts Python regex syntax. Run after wait-ready to confirm clean startup.\n\n"
            "JSON output fields:\n"
            "  lines     — matched (or all) log lines\n"
            "  tailOnly  — true if the file was large and only the tail was read\n"
            "  truncated — true if matched lines exceeded the output limit"
        ),
        formatter_class=RD,
    )
    p.add_argument("name")
    p.add_argument("--tail", type=int, default=200, help="Number of lines to read from the end (default: 200).")
    p.add_argument("--grep", default=None, help="Python regex to filter lines.")

    p = sub.add_parser(
        "stop",
        help="Stop the bend serve for this workspace.",
        description=(
            "Sends SIGTERM to the bend serve process group. Escalates to SIGKILL after 15s\n"
            "if serve does not exit cleanly. Updates the state file.\n\n"
            "Does NOT delete workspace files. Does NOT kill the tmux session.\n\n"
            "Use stop + restart (or just `restart`) rather than hand-killing the PID —\n"
            "direct kills leave route-configs/ stale and drop the BEND_WORKTREE env var."
        ),
        formatter_class=RD,
    )
    p.add_argument("name")

    p = sub.add_parser(
        "restart",
        help="Stop + re-launch bend serve (reuses prior nodeMemory unless overridden).",
        description=(
            "Runs `stop` then re-launches serve with the same packages and node memory.\n"
            "Reuses prior nodeMemoryMB from the state file unless --node-memory is passed.\n\n"
            "Prefer restart over nuke for:\n"
            "  - Serve stuck in 'starting' or 'error' state\n"
            "  - EADDRINUSE port conflicts\n"
            "  - Recovering after a crash\n"
            "  - Memory changes (use --node-memory to adjust)\n\n"
            "Only escalate to nuke if the user explicitly asks to tear down the workspace."
        ),
        formatter_class=RD,
    )
    p.add_argument("name")
    p.add_argument(
        "--node-memory", type=int, default=None, dest="node_memory",
        help="Override Node heap limit in MB for this restart (default: reuse prior state).",
    )

    p = sub.add_parser(
        "nuke",
        help="Permanently destroy a workspace (serve, tmux session, all files). REQUIRES explicit user confirmation.",
        description=(
            "Permanently destroys a workspace:\n"
            "  1. Stops bend serve (SIGTERM → SIGKILL)\n"
            "  2. Kills the workspace tmux session\n"
            "  3. Deletes ~/src/workspaces/<name>/ and all its contents\n\n"
            "THIS IS IRREVERSIBLE. Any uncommitted work in the workspace is lost.\n\n"
            "ALWAYS confirm with the user before running. Do not infer intent — the user\n"
            "must explicitly say they want to tear down or delete the workspace.\n\n"
            "DO NOT use nuke to:\n"
            "  - Remove a single repo from a workspace (unsupported; recreate with desired repos)\n"
            "  - Switch a repo to a different branch (use git checkout inside the workspace)\n"
            "  - Update a workspace to use fewer/different repos (nuke + recreate is a last resort,\n"
            "    not the default answer — confirm with the user first)\n"
            "  - Free memory when restart would suffice (use ws.py restart)\n"
            "  - Resolve a stuck or errored serve (try ws.py restart first)\n"
            "  - 'Refresh' a workspace because a repo is on the wrong branch\n\n"
            "Nuke is appropriate ONLY when the user explicitly wants to discard the workspace entirely."
        ),
        formatter_class=RD,
    )
    p.add_argument("name")
    p.add_argument(
        "--delete-branches", action="store_true",
        help="Also delete the workspace git branches from their source repos. Confirm with user before using.",
    )

    p = sub.add_parser(
        "help",
        help="Extended help topics for AI agents: monitor, templates.",
        description=(
            "Prints extended guidance on specific topics.\n\n"
            "Topics:\n"
            "  monitor    — background monitoring spec for AI agents\n"
            "  templates  — report templates for workspace ready/failed/unhealthy states"
        ),
        formatter_class=RD,
    )
    p.add_argument("topic", choices=["monitor", "templates"])

    p = sub.add_parser("discover", help="Discover packages/URLs for one repo path")
    p.add_argument("repo_path")
    p.add_argument("--workspace", default=None)

    p = sub.add_parser(
        "prefs",
        help="Read/write workspace memory preferences.",
        description=(
            "Manages persistent memory preferences for workspaces.\n\n"
            "ws.py enforces a total Node memory cap across all active workspaces (default: 24576 MB).\n"
            "Each workspace has a per-repo Node heap limit (default: 4096 MB). Memory-hungry repos\n"
            "like crm-index-ui typically need 16384 MB.\n\n"
            "Preferences are stored on disk and applied automatically — no flags needed at runtime\n"
            "once a repo is configured.\n\n"
            "Subcommands:\n"
            "  get                              — print all current preferences\n"
            "  set-repo-memory <repo> <MB>      — set per-repo Node heap limit\n"
            "  set-max-memory <MB>              — set global cap across all workspaces\n\n"
            "Examples:\n"
            "  ws.py prefs set-repo-memory crm-index-ui 16384\n"
            "  ws.py prefs set-max-memory 32768\n"
            "  ws.py prefs get\n\n"
            "If init fails with memory-budget-exceeded, either nuke an old workspace to free\n"
            "headroom, or raise the cap with set-max-memory."
        ),
        formatter_class=RD,
    )
    prefs_sub = p.add_subparsers(dest="action", required=True)
    prefs_sub.add_parser("get", help="Print current preferences")
    p2 = prefs_sub.add_parser("set-repo-memory", help="Set per-repo Node heap limit")
    p2.add_argument("repo", help="Repo name (e.g. crm-index-ui)")
    p2.add_argument("memory", type=int, help="Node heap limit in MB (e.g. 16384)")
    p2 = prefs_sub.add_parser("set-max-memory", help="Set total Node memory cap across all workspaces")
    p2.add_argument("memory", type=int, help="Max total Node heap in MB (default: 24576)")

    args = parser.parse_args()

    handlers = {
        "plan": cmd_plan,
        "init": cmd_init,
        "setup": cmd_setup,
        "add": cmd_add,
        "gc": cmd_gc,
        "list": cmd_list,
        "status": cmd_status,
        "wait-ready": cmd_wait_ready,
        "urls": cmd_urls,
        "logs": cmd_logs,
        "stop": cmd_stop,
        "restart": cmd_restart,
        "nuke": cmd_nuke,
        "help": cmd_help,
        "discover": cmd_discover,
        "prefs": cmd_prefs,
    }
    try:
        handlers[args.command](args)
    except ValueError as exc:
        emit_error(str(exc), recoverable=False)
        sys.exit(1)


if __name__ == "__main__":
    main()
