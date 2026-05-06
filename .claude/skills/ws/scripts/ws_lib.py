"""ws_lib — shared helpers for the workspace manager.

Pure stdlib. No process supervision, no CLI dispatch. Imported by ws.py
and ws_supervise.py. Lives next to ws.py so `Path(__file__).parent`
resolves to the `scripts/` dir and `.parent.parent` to the skill root.
"""

import concurrent.futures  # noqa: F401 — re-exported for callers that need it
import datetime
import json
import os
import pathlib
import re
import subprocess
import sys
import threading
import time


# ---------------------------------------------------------------- Constants

HOME = pathlib.Path.home()
SRC_ROOT = HOME / "src"
WS_ROOT = SRC_ROOT / "workspaces"
DISCOVERY_CACHE_PATH = WS_ROOT / "workspace-discovery-cache.json"
WS_PREFERENCES_PATH = WS_ROOT / "ws-preferences.json"
ROUTE_CONFIGS_DIR = HOME / ".hubspot" / "route-configs"
SERVE_LOG_NAME = ".serve.log"
PORTAL_ID = "103830646"
DEFAULT_ORG = "HubSpot"
DEFAULT_BRANCH_PREFIX = "brbrown/"
LOG_TAIL_BYTES = 50_000

BEND_REGISTRATION_TIMEOUT_S = 120.0
SERVE_STOP_GRACE_S = 15.0
DEFAULT_MAX_TOTAL_NODE_MEMORY_MB = 24576  # 24 GB; configurable via prefs set-max-memory

LB_DOMAIN_MAP = {
    "app": "app.hubspotqa.com",
    "privatehubteam": "private.hubteamqa.com",
    "tools": "tools.hubteamqa.com",
}
# Note: LB_DOMAIN_MAP values include the lb-prefix + base domain already
# (e.g. "app.hubspotqa.com"), so URL construction is:
#     https://<ws>.local.<mapped><basename>
# — NOT https://<ws>.local.<lb>.<mapped><basename>.

EXCLUDE_SUBDIR_SUBSTRS = (
    "node_modules", "target", "schemas",
    "hubspot.deploy", "docs", "acceptance-tests",
)

_THIS_DIR = pathlib.Path(__file__).resolve().parent  # .../skills/ws/scripts
WS_SKILL_ROOT = _THIS_DIR.parent  # .../skills/ws

BEND_MCP_TOOLS = [
    "mcp__devex-mcp-server__bend_compile",
    "mcp__devex-mcp-server__bend_file_ts_go_to_definition",
    "mcp__devex-mcp-server__bend_list_packages",
    "mcp__devex-mcp-server__bend_package_get_problems",
    "mcp__devex-mcp-server__bend_package_get_tests_logs",
    "mcp__devex-mcp-server__bend_package_get_tests_results",
    "mcp__devex-mcp-server__bend_package_ts_get_errors",
]


# ---------------------------------------------------------------- Logging / output

def log(msg):
    ts = time.strftime("%Y-%m-%d %H:%M:%S")
    print(f"[{ts}] {msg}", file=sys.stderr, flush=True)


def emit(obj):
    json.dump(obj, sys.stdout, indent=2, default=str)
    sys.stdout.write("\n")
    sys.stdout.flush()


def emit_error(error, recoverable=True, **extra):
    payload = {"ok": False, "error": error, "recoverable": recoverable}
    payload.update(extra)
    emit(payload)


# ---------------------------------------------------------------- Subprocess helpers

def run(cmd, **kwargs):
    kwargs.setdefault("capture_output", True)
    kwargs.setdefault("text", True)
    kwargs.setdefault("timeout", 60)
    return subprocess.run(cmd, **kwargs)


def tmux(*args):
    return run(["tmux", *args])


def tmux_has_session(name):
    return tmux("has-session", "-t", name).returncode == 0


def git(path, *args, timeout=120):
    return run(["git", "-C", str(path), *args], timeout=timeout)


# ---------------------------------------------------------------- Process identity helpers
#
# pid alone is not a stable identity across reboots (kernel recycles pids). To
# answer "is this the same process we spawned?", pair the pid with its start
# time (`ps -p <pid> -o lstart=`). Across reboots, every process is new, so
# every lstart comparison fails and we cleanly reset state. The marker env
# var is a secondary signal for manual debugging (ps -E).

def process_alive(pid):
    if not pid or pid <= 0:
        return False
    try:
        os.kill(int(pid), 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        # Process exists but we don't own it. Still counts as alive.
        return True


def process_start_time(pid):
    """Return the ps `lstart` string for pid, or None if the pid isn't alive.

    The lstart string is opaque — we only compare it for equality. That makes
    reboot reconciliation robust without needing psutil.
    """
    if not pid or pid <= 0:
        return None
    result = run(["ps", "-p", str(int(pid)), "-o", "lstart="], timeout=5)
    if result.returncode != 0:
        return None
    start = result.stdout.strip()
    return start or None


# ---------------------------------------------------------------- Path helpers

_NAME_RE = re.compile(r"^[A-Za-z0-9._-]+$")


def normalize(name):
    if not name:
        return ""
    normalized = name.replace(" ", "-")
    if not _NAME_RE.match(normalized):
        raise ValueError(
            f"invalid workspace name {name!r}: only [A-Za-z0-9._-] (and spaces) allowed"
        )
    return normalized


def ws_dir(name):
    return WS_ROOT / normalize(name)


def serve_log_path(name):
    return ws_dir(name) / SERVE_LOG_NAME


# ---------------------------------------------------------------- Discovery cache

_cache_lock = threading.Lock()


def load_discovery_cache():
    if not DISCOVERY_CACHE_PATH.exists():
        return {}
    try:
        return json.loads(DISCOVERY_CACHE_PATH.read_text())
    except json.JSONDecodeError:
        log("WARN: discovery cache malformed; starting fresh")
        return {}


def save_discovery_cache(cache):
    DISCOVERY_CACHE_PATH.parent.mkdir(parents=True, exist_ok=True)
    tmp = DISCOVERY_CACHE_PATH.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(cache, indent=2, sort_keys=True))
    tmp.replace(DISCOVERY_CACHE_PATH)


def update_discovery_cache(repo, fields):
    with _cache_lock:
        cache = load_discovery_cache()
        entry = cache.get(repo, {})
        entry.update(fields)
        entry["cachedAt"] = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        cache[repo] = entry
        save_discovery_cache(cache)


# ---------------------------------------------------------------- Preferences

def load_preferences():
    """Load ws-preferences.json. Returns {} if missing or malformed."""
    if not WS_PREFERENCES_PATH.exists():
        return {}
    try:
        return json.loads(WS_PREFERENCES_PATH.read_text())
    except json.JSONDecodeError:
        log("WARN: ws-preferences.json malformed; ignoring")
        return {}


def save_preferences(prefs):
    WS_PREFERENCES_PATH.parent.mkdir(parents=True, exist_ok=True)
    tmp = WS_PREFERENCES_PATH.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(prefs, indent=2, sort_keys=True))
    tmp.replace(WS_PREFERENCES_PATH)


def node_memory_for_repos(repo_names, prefs=None):
    """Return the highest nodeMemory (MB) required by any repo in repo_names.

    Falls back to 4096 if no preference is set. Callers can pass a
    pre-loaded prefs dict to avoid redundant file reads.
    """
    if prefs is None:
        prefs = load_preferences()
    repo_prefs = prefs.get("repos", {})
    return max(
        (repo_prefs.get(r, {}).get("nodeMemory", 4096) for r in repo_names),
        default=4096,
    )


def max_total_node_memory(prefs=None):
    """Return the configured total-Node-memory cap across all workspaces (MB)."""
    if prefs is None:
        prefs = load_preferences()
    return prefs.get("maxTotalNodeMemory", DEFAULT_MAX_TOTAL_NODE_MEMORY_MB)


def active_workspaces_memory():
    """Return [{name, nodeMemory, pid}] for every workspace with a live serve process."""
    if not WS_ROOT.exists():
        return []
    results = []
    for ws in sorted(WS_ROOT.iterdir()):
        state_path = ws / ".ws-serve.json"
        if not ws.is_dir() or ws.name.startswith(".") or not state_path.exists():
            continue
        try:
            state = json.loads(state_path.read_text())
        except (OSError, json.JSONDecodeError):
            continue
        pid = state.get("pid")
        lstart = state.get("lstart")
        if not pid or not process_alive(pid):
            continue
        have_lstart = process_start_time(pid)
        if not have_lstart or have_lstart != lstart:
            continue
        results.append({"name": ws.name, "nodeMemory": state.get("nodeMemory", 4096), "pid": pid})
    return results


# ---------------------------------------------------------------- Git / repo resolution

GITHUB_REMOTE_RE = re.compile(r"[:/]([^/]+)/([^/.]+?)(?:\.git)?$")


def resolve_remote(repo_name):
    """Resolve the remote URL for a repo from the discovery cache or git config."""
    cache = load_discovery_cache()
    entry = cache.get(repo_name)
    if entry and entry.get("remote"):
        return entry["remote"]
    src_path = SRC_ROOT / repo_name
    if src_path.exists():
        result = git(src_path, "config", "--get", "remote.origin.url")
        if result.returncode == 0:
            remote = result.stdout.strip()
            if remote:
                return remote
    return None


def parse_repo_arg(arg, default_branch):
    """Parse `repo` or `repo:branch` into (repo, branch)."""
    if ":" in arg:
        repo, branch = arg.split(":", 1)
    else:
        repo, branch = arg, default_branch
    return repo.strip(), branch.strip()


def current_branch(path):
    result = git(path, "rev-parse", "--abbrev-ref", "HEAD")
    return result.stdout.strip() if result.returncode == 0 else None


# ---------------------------------------------------------------- Deploy YAML parsing (regex-based)

# HubSpot deploy yamls have predictable shape. We only need:
#   - artifactBuildMetadata.module (string)
#   - loadBalancers (first list item)
#
# Avoid adding PyYAML: stdlib only.

MODULE_RE = re.compile(r"^\s*module:\s*([^\s#]+)", re.MULTILINE)
LB_BLOCK_RE = re.compile(
    r"^loadBalancers:\s*\n((?:\s+-\s+[^\n]+\n)+)",
    re.MULTILINE,
)


def parse_deploy_yaml(yaml_path):
    """Return {module, loadBalancer} or {}."""
    try:
        text = yaml_path.read_text()
    except (OSError, UnicodeDecodeError):
        return {}
    out = {}
    m = MODULE_RE.search(text)
    if m:
        out["module"] = m.group(1).strip().strip('"\'')
    m = LB_BLOCK_RE.search(text)
    if m:
        block = m.group(1)
        first = re.search(r"-\s+(\S+)", block)
        if first:
            out["loadBalancer"] = first.group(1).strip().strip('"\'')
    return out


# ---------------------------------------------------------------- Package discovery + URL resolution

def classify_repo(repo_clone):
    """'app' if <clone>/hubspot.deploy/<repo>.yaml exists, else 'library'."""
    deploy_dir = repo_clone / "hubspot.deploy"
    if not deploy_dir.exists():
        return "library"
    main_yaml = deploy_dir / f"{repo_clone.name}.yaml"
    if main_yaml.exists():
        return "app"
    yamls = list(deploy_dir.glob("*.yaml"))
    for y in yamls:
        stem = y.stem
        if stem.endswith(("-kitchen-sink", "-storybook", "-acceptance-tests")):
            continue
        return "app"
    return "library"


def list_package_dirs(repo_clone):
    """Return subdirectories that look like bend packages.

    Markers (any one is enough):
    - has `package.json` (traditional npm package)
    - has `static/quartz.config.ts` (bend frontend package; common in
      library-style repos like customer-data-table where sub-packages don't
      carry their own package.json)
    - has `static/static_conf.json` (canonical bend package marker — older
      library packages like crm-object-search-query-utilities may not yet
      have a quartz config but are still valid bend packages)
    """
    if not repo_clone.exists():
        return []
    pkg_dirs = []
    for child in sorted(repo_clone.iterdir()):
        if not child.is_dir():
            continue
        if any(s in child.name for s in EXCLUDE_SUBDIR_SUBSTRS):
            continue
        if (
            (child / "package.json").exists()
            or (child / "static" / "quartz.config.ts").exists()
            or (child / "static" / "static_conf.json").exists()
        ):
            pkg_dirs.append(child)
    return pkg_dirs


def is_default_package(pkg_name, repo_name, repo_type):
    # Never pre-select storybook / acceptance-tests / docs packages.
    if pkg_name.endswith(("-storybook", "-acceptance-tests", "-docs")):
        return False
    # Always pre-select the repo-named package (the "main" package).
    if pkg_name == repo_name:
        return True
    # For libraries, pre-select:
    #   - <anything>-kitchen-sink (the browser testing surface)
    #   - the un-suffixed base package (e.g. framework-data-table alongside
    #     framework-data-table-kitchen-sink in customer-data-table), since the
    #     repo name is often different from its package names.
    if repo_type == "library":
        return True
    return False


def find_deploy_yaml_for_package(repo_clone, pkg_name):
    """Find the yaml file whose filename or module == pkg_name."""
    deploy_dir = repo_clone / "hubspot.deploy"
    if not deploy_dir.exists():
        return None
    by_name = deploy_dir / f"{pkg_name}.yaml"
    if by_name.exists():
        return by_name
    for yaml_path in deploy_dir.glob("*.yaml"):
        parsed = parse_deploy_yaml(yaml_path)
        if parsed.get("module") == pkg_name:
            return yaml_path
    return None


def resolve_url_for_package(repo_clone, pkg_name, workspace_name):
    """Return {url, lb, basename, ready} for a package.

    - lb: the load balancer name from hubspot.deploy yaml (defaults to 'app')
    - basename: the historyBasename from quartz config (None if not yet compiled)
    - url: full URL if basename is known, else None
    - ready: whether quartz config was available
    """
    yaml_path = find_deploy_yaml_for_package(repo_clone, pkg_name)
    lb = "app"
    if yaml_path:
        parsed = parse_deploy_yaml(yaml_path)
        lb = parsed.get("loadBalancer", "app")

    quartz_path = repo_clone / pkg_name / "static" / "__generated__" / "quartz" / "quartz.config.json"
    basename = None
    ready = False
    pkg_type = None
    if quartz_path.exists():
        try:
            quartz = json.loads(quartz_path.read_text())
            config = quartz.get("config", {})
            pkg_type = config.get("type")
            hb = config.get("historyBasename")
            if isinstance(hb, list):
                hb = hb[0] if hb else None
            if isinstance(hb, str):
                basename = hb.replace(":portalId", PORTAL_ID)
                ready = True
        except (json.JSONDecodeError, OSError):
            pass

    if pkg_type and pkg_type != "application":
        return {"lb": lb, "basename": None, "url": None, "ready": ready, "browseable": False}

    domain = LB_DOMAIN_MAP.get(lb, f"{lb}.hubteamqa.com")
    if basename is None:
        return {"lb": lb, "basename": None, "url": None, "ready": False, "browseable": True}

    url = f"https://{workspace_name}.local.{domain}{basename}"
    return {"lb": lb, "basename": basename, "url": url, "ready": True, "browseable": True}


def discover_repo(repo_clone, workspace_name):
    """Discover packages + URLs for a repo clone. Returns the cache entry."""
    repo_name = repo_clone.name
    repo_type = classify_repo(repo_clone)
    pkg_dirs = list_package_dirs(repo_clone)

    if not pkg_dirs:
        packages = [{"name": repo_name, "isDefault": True}]
    else:
        packages = [
            {"name": p.name, "isDefault": is_default_package(p.name, repo_name, repo_type)}
            for p in pkg_dirs
        ]

    urls = {}
    for pkg in packages:
        info = resolve_url_for_package(repo_clone, pkg["name"], workspace_name)
        urls[pkg["name"]] = info

    remote_result = git(repo_clone, "config", "--get", "remote.origin.url")
    remote = remote_result.stdout.strip() if remote_result.returncode == 0 else None

    entry = {
        "remote": remote,
        "type": repo_type,
        "packages": packages,
        "urls": {k: {"lb": v["lb"], "basename": v["basename"]} for k, v in urls.items()},
    }
    update_discovery_cache(repo_name, entry)
    return {**entry, "resolved": urls, "name": repo_name}


# ---------------------------------------------------------------- Serve log parsing

PROGRESS_RE = re.compile(r"\[(\S+)\s+serve-rspack\]\s+(\d+)%\s+(\w+)")
COMPILED_RE = re.compile(r"\[(\S+)\s+serve-rspack\]\s+compiled successfully")
COMPILING_RE = re.compile(r"\[(\S+)\s+serve-rspack\]\s+compiling\.\.\.")
TEST_PROGRESS_RE = re.compile(
    r"\[(\S+)\s+run-tests\]\s+(\d+)%\s+of tests run\s+\((\d+)/(\d+)\)"
)
TEST_DONE_RE = re.compile(r"\[(\S+)\s+run-tests\]\s+Executed\s+(\d+)\s+of\s+(\d+)")
TESTS_STARTED_RE = re.compile(r"\[(\S+)\s+run-tests\]\s+Running tests\.\.\.")

FATAL_ERRORS = [
    ("EADDRINUSE", re.compile(r"EADDRINUSE")),
    ("FATAL", re.compile(r"FATAL")),
    ("ENOENT", re.compile(r"ENOENT")),
    ("COMMAND_NOT_FOUND", re.compile(r"command not found")),
]
WARN_ERRORS = [
    ("MODULE_NOT_FOUND", re.compile(r"Cannot find module")),
    ("ERR", re.compile(r"ERR!")),
]


def read_tail(path, nbytes=LOG_TAIL_BYTES):
    try:
        size = os.path.getsize(path)
    except OSError:
        return "", 0
    with open(path, "r", errors="replace") as f:
        if size > nbytes:
            f.seek(size - nbytes)
            f.readline()
        return f.read(), size


def parse_serve_log(text):
    lines = text.split("\n")
    packages = {}
    errors = []

    for line in lines:
        m = COMPILED_RE.search(line)
        if m:
            pkg = m.group(1)
            packages[pkg] = {"name": pkg, "progress": 100, "phase": "done", "compiled": True}
            continue
        m = COMPILING_RE.search(line)
        if m:
            pkg = m.group(1)
            packages[pkg] = {"name": pkg, "progress": 0, "phase": "compiling", "compiled": False}
            continue
        m = PROGRESS_RE.search(line)
        if m:
            pkg, pct, phase = m.group(1), int(m.group(2)), m.group(3)
            # Bend emits `<pkg> serve-rspack 100% emitting` as the final compile
            # signal — NOT `compiled successfully`. Treat progress=100 as done.
            packages[pkg] = {
                "name": pkg, "progress": pct, "phase": phase,
                "compiled": pct == 100,
            }
            continue
        m = TEST_PROGRESS_RE.search(line)
        if m:
            pkg = m.group(1)
            entry = packages.setdefault(pkg, {"name": pkg, "compiled": False})
            entry["testProgress"] = int(m.group(2))
            entry["testsRun"] = int(m.group(3))
            entry["testsTotal"] = int(m.group(4))
            continue
        m = TEST_DONE_RE.search(line)
        if m:
            pkg = m.group(1)
            entry = packages.setdefault(pkg, {"name": pkg, "compiled": False})
            entry["testProgress"] = 100
            entry["testsRun"] = int(m.group(2))
            entry["testsTotal"] = int(m.group(3))
            continue

        # "Running tests..." is strong evidence the package finished compiling
        # (tests only run after successful compile). Mark compiled as a safety
        # net in case the 100% emitting line already scrolled out of the tail.
        m = TESTS_STARTED_RE.search(line)
        if m:
            pkg = m.group(1)
            entry = packages.setdefault(
                pkg,
                {"name": pkg, "progress": 100, "phase": "done"},
            )
            entry["compiled"] = True
            continue

        matched_fatal = False
        for err_type, pattern in FATAL_ERRORS:
            if pattern.search(line):
                errors.append({"type": err_type, "fatal": True, "line": line.strip()[:300]})
                matched_fatal = True
                break
        if matched_fatal:
            continue
        for err_type, pattern in WARN_ERRORS:
            if pattern.search(line):
                errors.append({"type": err_type, "fatal": False, "line": line.strip()[:300]})
                break

    pkg_list = sorted(packages.values(), key=lambda p: p["name"])
    all_ready = len(pkg_list) > 0 and all(p.get("compiled") for p in pkg_list)
    has_fatal = any(e["fatal"] for e in errors)

    if has_fatal:
        state = "error"
    elif all_ready:
        state = "ready"
    elif pkg_list:
        state = "compiling"
    else:
        state = "starting"

    return {
        "state": state,
        "packages": pkg_list,
        "errors": errors[-10:],
        "allReady": all_ready,
    }


# ---------------------------------------------------------------- Workspace .claude/ provisioning
#
# Every workspace gets its own .claude/ directory with:
#   - skills/ws → symlink to this skill (so the workspace Claude loads it
#     natively instead of relying on a ~10 KB handoff prompt paste).
#   - settings.local.json → denies direct kill/bend-serve bash patterns so
#     workspace Claude can't stomp on the supervised serve process.
#   - CLAUDE.md → one-line first-action: warm the bend MCP tool schemas.

def _provision_workspace_claude_dir(wsdir):
    claude_dir = wsdir / ".claude"
    claude_dir.mkdir(parents=True, exist_ok=True)

    skills_dir = claude_dir / "skills"
    skills_dir.mkdir(parents=True, exist_ok=True)
    skill_link = skills_dir / "ws"
    if skill_link.is_symlink():
        try:
            if pathlib.Path(os.readlink(skill_link)) != WS_SKILL_ROOT:
                skill_link.unlink()
        except OSError:
            pass
    if not skill_link.exists() and not skill_link.is_symlink():
        try:
            skill_link.symlink_to(WS_SKILL_ROOT, target_is_directory=True)
        except OSError as exc:
            log(f"WARN: could not symlink ws skill into {skill_link}: {exc}")

    settings_path = claude_dir / "settings.local.json"
    if not settings_path.exists():
        settings = {
            "permissions": {
                "deny": [
                    "Bash(kill:*)",
                    "Bash(pkill:*)",
                    "Bash(killall:*)",
                    "Bash(bend reactor serve:*)",
                    "Bash(bend serve:*)",
                ],
                "allow": [
                    *BEND_MCP_TOOLS,
                    "Bash(ws.py status:*)",
                    "Bash(ws.py logs:*)",
                    "Bash(ws.py wait-ready:*)",
                    "Bash(ws.py urls:*)",
                ],
            }
        }
        try:
            settings_path.write_text(json.dumps(settings, indent=2))
        except OSError as exc:
            log(f"WARN: could not write {settings_path}: {exc}")

    claude_md = claude_dir / "CLAUDE.md"
    if not claude_md.exists():
        tool_list = ",".join(t.rsplit("__", 1)[-1] for t in BEND_MCP_TOOLS)
        claude_md.write_text(
            "# Workspace Claude bootstrap\n\n"
            "## First action: warm bend MCP tools\n"
            "Call ToolSearch with `select:" + tool_list + "` at the start of the\n"
            "session so the bend tool schemas are loaded up front instead of\n"
            "dehoisted lazily on first use.\n\n"
            "## Serve ownership\n"
            "The workspace's `bend reactor serve` is supervised by ws.py. Do not\n"
            "start or stop it directly — use `ws.py status/logs/wait-ready/urls`.\n"
        )


# ---------------------------------------------------------------- Clone + yarn helpers

def clone_repo(remote, dest, branch):
    """Clone remote into dest and checkout branch. Idempotent."""
    if dest.exists() and (dest / ".git").exists():
        log(f"[{dest.name}] clone exists, skipping")
        return {"repo": dest.name, "cloned": False, "branch": branch, "ok": True}

    if dest.exists():
        log(f"[{dest.name}] dest exists but no .git — refusing to clobber")
        return {"repo": dest.name, "cloned": False, "ok": False,
                "error": "destination exists without .git"}

    log(f"[{dest.name}] cloning {remote}")
    dest.parent.mkdir(parents=True, exist_ok=True)
    result = subprocess.run(
        ["git", "clone", remote, str(dest)],
        capture_output=True, text=True, timeout=600,
    )
    if result.returncode != 0:
        return {"repo": dest.name, "cloned": False, "ok": False,
                "error": f"clone failed: {result.stderr.strip()[:500]}"}
    return {"repo": dest.name, "cloned": True, "branch": branch, "ok": True}


def checkout_branch(repo_clone, branch):
    """Create-or-switch to branch. Matches SKILL.md: try -b first, fall back."""
    result = git(repo_clone, "checkout", "-b", branch, "origin/master")
    if result.returncode == 0:
        return {"branch": branch, "created": True, "ok": True}
    result = git(repo_clone, "checkout", branch)
    if result.returncode == 0:
        return {"branch": branch, "created": False, "ok": True}
    return {"branch": branch, "ok": False,
            "error": f"checkout failed: {result.stderr.strip()[:300]}"}


def bend_yarn(repo_clone):
    log(f"[{repo_clone.name}] bend yarn")
    result = subprocess.run(
        ["bend", "yarn"], cwd=repo_clone,
        capture_output=True, text=True, timeout=900,
    )
    if result.returncode != 0:
        return {"repo": repo_clone.name, "ok": False,
                "error": f"bend yarn failed: {result.stderr.strip()[:500]}"}
    # Returncode 0 can still mean a partial install (interrupted post-install
    # scripts, ENOSPC, etc.) — yarn emits node_modules/.yarn-integrity on a
    # clean run. Check it so we don't start serve against a half-installed tree.
    integrity_markers = [
        repo_clone / "node_modules" / ".yarn-integrity",
        repo_clone / "node_modules" / ".package-lock.json",
    ]
    if not any(p.exists() for p in integrity_markers):
        return {
            "repo": repo_clone.name,
            "ok": False,
            "error": "bend yarn exited 0 but no node_modules integrity marker was written",
            "hint": "re-run `ws.py setup <name>` to retry",
        }
    return {"repo": repo_clone.name, "ok": True}


def has_claude_md(repo_clone):
    return (repo_clone / "CLAUDE.md").exists()


def select_packages(discovery):
    return [p["name"] for p in discovery["packages"] if p["isDefault"]]
