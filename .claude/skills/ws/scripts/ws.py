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


# ---------------------------------------------------------------- Command: plan

def cmd_plan(args):
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
    prompt_file = pathlib.Path(f"/tmp/ws-{name}-init-prompt.txt")
    wsdir = ws_dir(name)

    if not prompt_file.exists():
        emit_error(f"prompt file not found: {prompt_file}", recoverable=False)
        sys.exit(1)

    wsdir.mkdir(parents=True, exist_ok=True)
    _provision_workspace_claude_dir(wsdir)

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
        f'rm -f "{prompt_file}" "{launcher}"\n'
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


# ---------------------------------------------------------------- main

def main():
    parser = argparse.ArgumentParser(description="ws.py — workspace manager")
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("plan", help="Validate + preview a workspace plan")
    p.add_argument("name")
    p.add_argument("repos", nargs="+")

    p = sub.add_parser("init", help="Create tmux session + (optionally clone/yarn/serve) + launch workspace Claude")
    p.add_argument("name")
    p.add_argument(
        "--repos", nargs="+", default=None,
        help="Repo specs (repo[:branch]); when given, init runs the full setup "
             "(clone + yarn + serve) and waits for bend to register before "
             "launching the workspace Claude.",
    )
    p.add_argument(
        "--node-memory", type=int, default=None, dest="node_memory",
        help="Node heap limit in MB for webpack subprocesses (default: 4096). "
             "Use 16384 for crm-index-ui and other memory-hungry repos.",
    )

    p = sub.add_parser("setup", help="Clone + yarn + discover + serve for workspace")
    p.add_argument("name")
    p.add_argument(
        "--node-memory", type=int, default=None, dest="node_memory",
        help="Node heap limit in MB (default: 4096 or value from prior state).",
    )

    p = sub.add_parser("add", help="Add repos to an existing workspace")
    p.add_argument("name")
    p.add_argument("repos", nargs="+")
    p.add_argument(
        "--node-memory", type=int, default=None, dest="node_memory",
        help="Node heap limit in MB (default: reuse prior state or 4096).",
    )

    p = sub.add_parser("status", help="Workspace status snapshot (JSON)")
    p.add_argument("name")

    p = sub.add_parser("wait-ready", help="Poll until serve is ready")
    p.add_argument("name")
    p.add_argument("--timeout", type=int, default=600)

    p = sub.add_parser("urls", help="Resolved app + test URLs")
    p.add_argument("name")

    p = sub.add_parser("logs", help="Read/grep the serve log")
    p.add_argument("name")
    p.add_argument("--tail", type=int, default=200)
    p.add_argument("--grep", default=None)

    p = sub.add_parser("stop", help="Stop the bend serve for this workspace")
    p.add_argument("name")

    p = sub.add_parser("restart", help="Stop + start serve")
    p.add_argument("name")
    p.add_argument(
        "--node-memory", type=int, default=None, dest="node_memory",
        help="Override Node heap limit in MB for this restart (default: reuse prior state).",
    )

    p = sub.add_parser("nuke", help="Destroy workspace (serve, tmux, files)")
    p.add_argument("name")
    p.add_argument("--delete-branches", action="store_true")

    p = sub.add_parser("discover", help="Discover packages/URLs for one repo path")
    p.add_argument("repo_path")
    p.add_argument("--workspace", default=None)

    p = sub.add_parser("prefs", help="Read/write ws-preferences.json")
    prefs_sub = p.add_subparsers(dest="action", required=True)
    prefs_sub.add_parser("get", help="Print current preferences")
    p2 = prefs_sub.add_parser("set-repo-memory", help="Set per-repo nodeMemory override")
    p2.add_argument("repo", help="Repo name (e.g. crm-index-ui)")
    p2.add_argument("memory", type=int, help="Node heap limit in MB (e.g. 16384)")

    args = parser.parse_args()

    handlers = {
        "plan": cmd_plan,
        "init": cmd_init,
        "setup": cmd_setup,
        "add": cmd_add,
        "status": cmd_status,
        "wait-ready": cmd_wait_ready,
        "urls": cmd_urls,
        "logs": cmd_logs,
        "stop": cmd_stop,
        "restart": cmd_restart,
        "nuke": cmd_nuke,
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
