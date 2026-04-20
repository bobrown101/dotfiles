#!/usr/bin/env python3
# /// script
# requires-python = ">=3.9"
# dependencies = []
# ///
"""ws.py — workspace manager.

Single-file CLI that orchestrates multi-repo dev workspaces: git clones,
bend yarn, tmux, `bend reactor serve`, status monitoring. Replaces the
former ws-init (bash), ws-serve (fish), and ws-status (Python) helpers.

Conventions:
- All subcommands emit JSON to stdout. Human-readable progress → stderr.
- Recoverable errors return {"ok": false, "error": ...}. Only argparse
  errors exit non-zero.
- Stdlib only — no PyYAML, no psutil, no requests.

Usage:
    uv run ws.py plan <name> <repo[:branch]>...
    uv run ws.py init <name> [--parent P]
    uv run ws.py setup <name>
    uv run ws.py add <name> <repo[:branch]>...
    uv run ws.py status <name>
    uv run ws.py wait-ready <name> [--timeout 600]
    uv run ws.py urls <name>
    uv run ws.py logs <name> [--tail N] [--grep P]
    uv run ws.py stop <name> [--teardown]
    uv run ws.py restart <name>
    uv run ws.py nuke <name> [--delete-branches]
    uv run ws.py discover <repo-path>
    uv run ws.py serve-daemon <name> <pkg-path>...  # internal
"""

import argparse
import asyncio
import concurrent.futures
import dataclasses
import datetime
import json
import os
import pathlib
import re
import shlex
import shutil
import signal
import socket
import subprocess
import sys
import threading
import time
import urllib.parse

# ---------------------------------------------------------------- Constants

HOME = pathlib.Path.home()
SRC_ROOT = HOME / "src"
WS_ROOT = SRC_ROOT / "workspaces"
DISCOVERY_CACHE_PATH = WS_ROOT / "workspace-discovery-cache.json"
ROUTE_CONFIGS_DIR = HOME / ".hubspot" / "route-configs"
SERVE_LOG_NAME = ".serve.log"
DAEMON_LOG_FILE = HOME / ".ws-serve.log"
PORTAL_ID = "103830646"
DEFAULT_ORG = "HubSpot"
DEFAULT_BRANCH_PREFIX = "brbrown/"
SHARED_SERVE_SESSION = "workspaces-serve-commands"
LOG_TAIL_BYTES = 50_000

# ws-daemon (single long-lived process; owns workspace state in memory).
WS_DAEMON_SOCKET = HOME / ".ws-daemon.sock"
WS_DAEMON_LOG = HOME / ".ws-daemon.log"
WS_DAEMON_START_TIMEOUT_S = 10.0
WS_DAEMON_STOP_TIMEOUT_S = 30.0
SERVE_RING_BYTES = 256 * 1024
BEND_REGISTRATION_TIMEOUT_S = 120.0
SERVE_STOP_GRACE_S = 15.0

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

THIS_FILE = pathlib.Path(__file__).resolve()


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


def tmux_list_windows(session):
    result = tmux("list-windows", "-t", session, "-F", "#{window_name}")
    if result.returncode != 0:
        return []
    return [w for w in result.stdout.split() if w]


def git(path, *args, timeout=120):
    return run(["git", "-C", str(path), *args], timeout=timeout)


def pgrep_f(pattern):
    result = run(["pgrep", "-f", pattern])
    if result.returncode != 0:
        return []
    return [int(p) for p in result.stdout.split() if p.strip()]


def pgrep_children(pid):
    result = run(["pgrep", "-P", str(pid)])
    if result.returncode != 0:
        return []
    return [int(p) for p in result.stdout.split() if p.strip()]


def kill_tree(pid, sig=signal.SIGTERM):
    for child in pgrep_children(pid):
        kill_tree(child, sig)
    try:
        os.kill(pid, sig)
    except (ProcessLookupError, PermissionError):
        pass


def pid_alive(pid):
    try:
        os.kill(pid, 0)
        return True
    except (ProcessLookupError, PermissionError):
        return False


# ---------------------------------------------------------------- Path helpers

def normalize(name):
    return name.replace(" ", "-")


def ws_dir(name):
    return WS_ROOT / normalize(name)


def serve_log_path(name):
    return ws_dir(name) / SERVE_LOG_NAME


def daemon_marker(name):
    """Unique substring to find the serve-daemon process with pgrep -f."""
    return f"ws.py serve-daemon {normalize(name)}"


# ---------------------------------------------------------------- Discovery cache

_cache_lock = threading.Lock()


def load_discovery_cache():
    if not DISCOVERY_CACHE_PATH.exists():
        return {}
    try:
        return json.loads(DISCOVERY_CACHE_PATH.read_text())
    except json.JSONDecodeError:
        log(f"WARN: discovery cache malformed; starting fresh")
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


def detect_parent_workspace():
    """Detect if we're inside another workspace (cwd under ~/src/workspaces/X/)."""
    cwd = pathlib.Path.cwd().resolve()
    try:
        rel = cwd.relative_to(WS_ROOT)
    except ValueError:
        return None
    parts = rel.parts
    if not parts:
        return None
    return parts[0]


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


# ---------------------------------------------------------------- Serve log parsing (from ws-status, verbatim)

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


# ---------------------------------------------------------------- serve-daemon (signal-trapping bend wrapper)

class ServeDaemon:
    def __init__(self, name, pkg_paths):
        self.name = normalize(name)
        self.pkg_paths = pkg_paths
        self.bend_proc = None
        self.orphan_thread = None
        self._stopping = threading.Event()
        self.original_ppid = os.getppid()
        self.serve_log = serve_log_path(self.name)

    def _daemon_log(self, msg):
        try:
            with open(DAEMON_LOG_FILE, "a") as f:
                ts = time.strftime("%Y-%m-%d %H:%M:%S")
                f.write(f"[{ts}] [ws-serve/{self.name}] (pid={os.getpid()}) {msg}\n")
        except OSError:
            pass

    def _cleanup(self, reason):
        self._daemon_log(f"cleanup: reason={reason}")
        if self._stopping.is_set():
            return
        self._stopping.set()
        if not self.bend_proc:
            return
        bend_pid = self.bend_proc.pid
        if not pid_alive(bend_pid):
            self._daemon_log(f"cleanup: bend pid={bend_pid} already dead")
            return
        self._daemon_log(f"cleanup: SIGTERM bend tree (root={bend_pid})")
        kill_tree(bend_pid, signal.SIGTERM)
        for _ in range(15):
            if not pid_alive(bend_pid):
                break
            time.sleep(0.2)
        if pid_alive(bend_pid):
            self._daemon_log(f"cleanup: SIGKILL bend tree")
            kill_tree(bend_pid, signal.SIGKILL)
        self._daemon_log(f"cleanup: done")

    def _install_signal_traps(self):
        def handler(signum, _frame):
            sig_name = signal.Signals(signum).name
            self._daemon_log(f"signal: caught {sig_name}")
            self._cleanup(f"signal {sig_name}")
            sys.exit(0)
        for sig in (signal.SIGTERM, signal.SIGHUP, signal.SIGINT):
            signal.signal(sig, handler)

    def _orphan_monitor(self):
        while not self._stopping.is_set():
            time.sleep(5)
            if self._stopping.is_set():
                return
            if self.bend_proc and self.bend_proc.poll() is not None:
                return
            try:
                ppid = os.getppid()
            except OSError:
                continue
            if ppid == 1 and self.original_ppid != 1:
                self._daemon_log(f"orphan-monitor: PPID became 1 — cleaning up")
                self._cleanup("orphaned")
                os._exit(0)

    def run(self):
        self._daemon_log(f"--- ws-serve starting for {self.name} ---")
        self._daemon_log(f"pkgs: {self.pkg_paths}")
        self._daemon_log(f"original PPID: {self.original_ppid}")
        self.serve_log.parent.mkdir(parents=True, exist_ok=True)
        # Truncate so parse_serve_log sees fresh output
        self.serve_log.write_text("")

        self._install_signal_traps()

        cmd = [
            "bend", "reactor", "serve",
            *self.pkg_paths,
            "--update", "--ts-watch", "--enable-tools", "--run-tests",
        ]
        env = os.environ.copy()
        env["BEND_WORKTREE"] = self.name
        env["NODE_ARGS"] = env.get("NODE_ARGS", "--max_old_space_size=16384")

        self._daemon_log(f"launching: {' '.join(cmd)}")
        # Line-buffered, merge stderr, tee to log file + stdout.
        self.bend_proc = subprocess.Popen(
            cmd,
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            bufsize=1,
            text=True,
        )
        self._daemon_log(f"bend pid={self.bend_proc.pid}")

        self.orphan_thread = threading.Thread(target=self._orphan_monitor, daemon=True)
        self.orphan_thread.start()

        try:
            with open(self.serve_log, "a") as logf:
                for line in self.bend_proc.stdout:
                    sys.stdout.write(line)
                    sys.stdout.flush()
                    logf.write(line)
                    logf.flush()
        except KeyboardInterrupt:
            self._cleanup("KeyboardInterrupt")
        finally:
            rc = self.bend_proc.wait() if self.bend_proc else 1
            self._daemon_log(f"bend exited code={rc}")
            self._stopping.set()
            sys.exit(rc)


# ---------------------------------------------------------------- ws-daemon (singleton, in-memory registry)
#
# Long-lived process that will own every workspace's serve + Claude PTY once
# Phases 2 and 3 land. This file currently has the skeleton only: event loop,
# Unix-socket RPC server, newline-JSON framing, and ping/shutdown methods.
# All workspace state lives here in memory — intentionally; machine reboot
# means every workspace is gone and `ws.py init` re-creates it.

class DaemonNotRunning(Exception):
    """Raised by client helpers when the daemon socket isn't answering."""


class RingBuffer:
    """Bounded byte buffer. Append-only until it fills, then oldest bytes drop.

    We don't need random access; callers only read the whole tail. Keeping this
    as a single bytearray is simpler than a chunk list and fast enough for
    ~256 KB sizes at bend's output rates.
    """

    def __init__(self, capacity):
        self.capacity = capacity
        self._buf = bytearray()

    def append(self, chunk):
        if not chunk:
            return
        self._buf.extend(chunk)
        overflow = len(self._buf) - self.capacity
        if overflow > 0:
            del self._buf[:overflow]

    def snapshot(self):
        return bytes(self._buf)

    def text(self):
        return self._buf.decode("utf-8", errors="replace")

    def __len__(self):
        return len(self._buf)


@dataclasses.dataclass
class Workspace:
    """In-memory workspace state owned by the daemon.

    Phase 2 populates only the serve side. Phase 3 adds claude_* fields.
    """
    name: str
    wsdir: pathlib.Path
    serve_proc: "asyncio.subprocess.Process | None" = None
    serve_pkg_paths: list = dataclasses.field(default_factory=list)
    serve_state: str = "not_running"
    serve_ring: RingBuffer = dataclasses.field(default_factory=lambda: RingBuffer(SERVE_RING_BYTES))
    serve_stdout_task: "asyncio.Task | None" = None
    serve_started_at: float | None = None
    serve_packages: list = dataclasses.field(default_factory=list)
    serve_errors: list = dataclasses.field(default_factory=list)
    serve_bend_registered: bool = False


def _daemon_log_line(msg, **fields):
    """Append one JSON-line to the daemon log. Best-effort; swallows errors."""
    try:
        WS_DAEMON_LOG.parent.mkdir(parents=True, exist_ok=True)
        entry = {
            "t": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%fZ"),
            "pid": os.getpid(),
            "msg": msg,
            **fields,
        }
        with open(WS_DAEMON_LOG, "a") as f:
            f.write(json.dumps(entry, default=str) + "\n")
    except OSError:
        pass


class WsDaemon:
    """asyncio-backed Unix-socket RPC server. State is in-memory only."""

    def __init__(self, socket_path):
        self.socket_path = pathlib.Path(socket_path)
        self.workspaces = {}  # populated in Phase 2
        self._server = None
        self._shutdown_event = None

    async def run(self):
        self._shutdown_event = asyncio.Event()
        # If a stale socket exists and isn't answering, remove it.
        if self.socket_path.exists():
            try:
                _rpc_send({"method": "ping"}, socket_path=self.socket_path, timeout=0.5)
                raise RuntimeError(f"another daemon already running on {self.socket_path}")
            except DaemonNotRunning:
                try:
                    self.socket_path.unlink()
                except FileNotFoundError:
                    pass
        self.socket_path.parent.mkdir(parents=True, exist_ok=True)
        self._server = await asyncio.start_unix_server(
            self._handle_client, path=str(self.socket_path)
        )
        try:
            os.chmod(self.socket_path, 0o600)
        except OSError:
            pass
        _daemon_log_line("daemon started", socket=str(self.socket_path))
        try:
            await self._shutdown_event.wait()
        finally:
            self._server.close()
            await self._server.wait_closed()
            try:
                self.socket_path.unlink()
            except FileNotFoundError:
                pass
            _daemon_log_line("daemon stopped")

    async def _handle_client(self, reader, writer):
        try:
            line = await reader.readline()
            if not line:
                return
            try:
                req = json.loads(line.decode("utf-8"))
            except json.JSONDecodeError as exc:
                await self._respond(writer, {"ok": False, "error": f"invalid json: {exc}"})
                return
            method = req.get("method") if isinstance(req, dict) else None
            handler = getattr(self, f"_rpc_{method}", None) if method else None
            if handler is None:
                await self._respond(writer, {"ok": False, "error": f"unknown method: {method!r}"})
                return
            try:
                result = await handler(req, writer)
            except Exception as exc:  # noqa: BLE001 — surfaced to client
                _daemon_log_line("rpc error", method=method, error=str(exc))
                await self._respond(writer, {"ok": False, "error": str(exc)})
                return
            if result is not None:
                await self._respond(writer, result)
        finally:
            try:
                writer.close()
                await writer.wait_closed()
            except Exception:  # noqa: BLE001 — client already gone is fine
                pass

    async def _respond(self, writer, obj):
        payload = (json.dumps(obj, default=str) + "\n").encode("utf-8")
        writer.write(payload)
        try:
            await writer.drain()
        except (ConnectionResetError, BrokenPipeError):
            pass

    # ---- RPC handlers ----

    async def _rpc_ping(self, req, writer):
        return {
            "ok": True,
            "pid": os.getpid(),
            "workspaceCount": len(self.workspaces),
        }

    async def _rpc_shutdown(self, req, writer):
        _daemon_log_line("shutdown requested")
        await self._respond(writer, {"ok": True})
        # Stop every serve child before the event loop closes, so we don't
        # leak bend processes when the daemon goes down.
        await self._stop_all_serves()
        loop = asyncio.get_running_loop()
        loop.call_later(0.05, self._shutdown_event.set)
        return None

    # ---- serve lifecycle ----

    async def _rpc_start_serve(self, req, writer):
        name = normalize(req.get("name", ""))
        if not name:
            return {"ok": False, "error": "missing name"}
        pkg_paths = [pathlib.Path(p) for p in req.get("pkgPaths") or []]
        if not pkg_paths:
            return {"ok": False, "error": "pkgPaths is empty"}
        ws = self.workspaces.get(name)
        if ws is None:
            ws = Workspace(name=name, wsdir=ws_dir(name))
            self.workspaces[name] = ws
        if ws.serve_proc is not None and ws.serve_proc.returncode is None:
            return {
                "ok": False,
                "error": f"serve already running for {name}",
                "servePid": ws.serve_proc.pid,
            }
        ws.serve_pkg_paths = pkg_paths
        ws.serve_ring = RingBuffer(SERVE_RING_BYTES)
        ws.serve_state = "starting"
        ws.serve_packages = []
        ws.serve_errors = []
        ws.serve_bend_registered = False
        ws.serve_started_at = time.time()
        await self._spawn_bend_serve(ws)
        registered = await self._wait_for_bend_registration(ws.serve_started_at)
        ws.serve_bend_registered = registered
        return {
            "ok": True,
            "workspace": name,
            "servePid": ws.serve_proc.pid if ws.serve_proc else None,
            "bendRegistered": registered,
            "state": ws.serve_state,
        }

    async def _rpc_status(self, req, writer):
        name = normalize(req.get("name", ""))
        ws = self.workspaces.get(name)
        if ws is None:
            return {
                "ok": True,
                "workspace": name,
                "state": "not_running",
                "serveUp": False,
                "claudeUp": False,
                "packages": [],
                "errors": [],
                "urls": {},
                "pkgPaths": [],
                "bendRegistered": False,
            }
        serve_up = ws.serve_proc is not None and ws.serve_proc.returncode is None
        return {
            "ok": True,
            "workspace": name,
            "state": ws.serve_state,
            "serveUp": serve_up,
            "claudeUp": False,  # Phase 3 populates this
            "servePid": ws.serve_proc.pid if serve_up else None,
            "packages": ws.serve_packages,
            "errors": ws.serve_errors,
            "urls": _derive_urls_for(name),
            "pkgPaths": [str(p) for p in ws.serve_pkg_paths],
            "bendRegistered": ws.serve_bend_registered,
        }

    async def _rpc_list(self, req, writer):
        items = []
        for name, ws in sorted(self.workspaces.items()):
            serve_up = ws.serve_proc is not None and ws.serve_proc.returncode is None
            items.append({
                "name": name,
                "state": ws.serve_state,
                "serveUp": serve_up,
                "claudeUp": False,  # Phase 3 populates
                "servePid": ws.serve_proc.pid if serve_up else None,
                "pkgCount": len(ws.serve_pkg_paths),
            })
        return {"ok": True, "workspaces": items}

    async def _rpc_stop_serve(self, req, writer):
        name = normalize(req.get("name", ""))
        ws = self.workspaces.get(name)
        if ws is None:
            return {"ok": True, "wasRunning": False, "workspace": name}
        result = await self._stop_serve(ws)
        return {"ok": True, "workspace": name, **result}

    async def _rpc_restart_serve(self, req, writer):
        name = normalize(req.get("name", ""))
        ws = self.workspaces.get(name)
        pkg_paths_arg = req.get("pkgPaths")
        if ws is None and not pkg_paths_arg:
            return {"ok": False, "error": f"unknown workspace {name!r} and no pkgPaths given"}
        if ws is not None:
            await self._stop_serve(ws)
        # Fresh pkgPaths override the previous set; otherwise reuse what we had.
        new_paths = [str(p) for p in (pkg_paths_arg or (ws.serve_pkg_paths if ws else []))]
        if not new_paths:
            return {"ok": False, "error": "no pkgPaths to restart with"}
        return await self._rpc_start_serve(
            {"method": "start_serve", "name": name, "pkgPaths": new_paths},
            writer,
        )

    async def _spawn_bend_serve(self, ws):
        ws.wsdir.mkdir(parents=True, exist_ok=True)
        # Truncate the legacy .serve.log so existing parse_serve_log readers see
        # fresh output. Dual-write to the file keeps cmd_logs/cmd_status working
        # against the file while they're still on the pre-daemon read path.
        log_file = serve_log_path(ws.name)
        log_file.parent.mkdir(parents=True, exist_ok=True)
        log_file.write_bytes(b"")
        env = os.environ.copy()
        env["BEND_WORKTREE"] = ws.name
        env.setdefault("NODE_ARGS", "--max_old_space_size=16384")
        cmd = [
            "bend", "reactor", "serve",
            *[str(p) for p in ws.serve_pkg_paths],
            "--update", "--ts-watch", "--enable-tools", "--run-tests",
        ]
        _daemon_log_line(
            "serve spawn", name=ws.name,
            cmd=" ".join(shlex.quote(c) for c in cmd),
        )
        ws.serve_proc = await asyncio.create_subprocess_exec(
            *cmd,
            cwd=str(ws.wsdir),
            env=env,
            stdin=asyncio.subprocess.DEVNULL,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.STDOUT,
            start_new_session=True,
        )
        _daemon_log_line("serve pid", name=ws.name, pid=ws.serve_proc.pid)
        ws.serve_stdout_task = asyncio.create_task(self._read_serve_stdout(ws))

    async def _read_serve_stdout(self, ws):
        """Drain bend stdout into the ring buffer + legacy .serve.log."""
        proc = ws.serve_proc
        log_file = serve_log_path(ws.name)
        try:
            with open(log_file, "ab") as logf:
                while True:
                    chunk = await proc.stdout.read(8192)
                    if not chunk:
                        break
                    ws.serve_ring.append(chunk)
                    try:
                        logf.write(chunk)
                        logf.flush()
                    except OSError:
                        pass
                    self._refresh_serve_state(ws)
        except Exception as exc:  # noqa: BLE001 — reader death is surfaced via state
            _daemon_log_line("serve stdout reader error", name=ws.name, error=str(exc))
        finally:
            rc = await proc.wait()
            _daemon_log_line("serve exited", name=ws.name, returncode=rc)
            if ws.serve_state not in ("error",):
                ws.serve_state = "not_running"

    def _refresh_serve_state(self, ws):
        text = ws.serve_ring.text()
        result = parse_serve_log(text)
        ws.serve_state = result["state"]
        ws.serve_packages = result["packages"]
        ws.serve_errors = result["errors"]

    async def _wait_for_bend_registration(self, start_time, timeout=BEND_REGISTRATION_TIMEOUT_S):
        """Block until bend writes a fresh *-introspection file to route-configs.

        The workspace Claude's devex-mcp-server only scans route-configs at
        startup, so bend must be registered BEFORE we launch Claude.
        """
        deadline = time.time() + timeout
        while time.time() < deadline:
            if ROUTE_CONFIGS_DIR.exists():
                for f in ROUTE_CONFIGS_DIR.iterdir():
                    if not f.name.endswith("-introspection"):
                        continue
                    try:
                        if f.stat().st_mtime >= start_time:
                            _daemon_log_line("bend registered", introspection=f.name)
                            return True
                    except OSError:
                        continue
            await asyncio.sleep(1)
        _daemon_log_line("bend registration timeout", timeout=timeout)
        return False

    async def _stop_serve(self, ws, grace=SERVE_STOP_GRACE_S):
        """SIGTERM → wait → SIGKILL. No-op if serve isn't running."""
        proc = ws.serve_proc
        if proc is None or proc.returncode is not None:
            return {"wasRunning": False}
        pid = proc.pid
        _daemon_log_line("serve stop: SIGTERM", name=ws.name, pid=pid)
        try:
            os.killpg(os.getpgid(pid), signal.SIGTERM)
        except (ProcessLookupError, PermissionError):
            pass
        try:
            await asyncio.wait_for(proc.wait(), timeout=grace)
        except asyncio.TimeoutError:
            _daemon_log_line("serve stop: SIGKILL", name=ws.name, pid=pid)
            try:
                os.killpg(os.getpgid(pid), signal.SIGKILL)
            except (ProcessLookupError, PermissionError):
                pass
            try:
                await asyncio.wait_for(proc.wait(), timeout=5.0)
            except asyncio.TimeoutError:
                _daemon_log_line("serve stop: SIGKILL timeout", name=ws.name, pid=pid)
        ws.serve_state = "not_running"
        return {"wasRunning": True, "returncode": proc.returncode}

    async def _stop_all_serves(self):
        if not self.workspaces:
            return
        _daemon_log_line("shutting down all serves", count=len(self.workspaces))
        await asyncio.gather(
            *(self._stop_serve(ws) for ws in self.workspaces.values()),
            return_exceptions=True,
        )


def _derive_urls_for(name):
    """Best-effort URL resolution from the discovery cache. Mirrors cmd_status."""
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


def _rpc_send(req, socket_path=WS_DAEMON_SOCKET, timeout=5.0):
    """Blocking single-request RPC. Returns parsed JSON response."""
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.settimeout(timeout)
    try:
        sock.connect(str(socket_path))
    except (FileNotFoundError, ConnectionRefusedError, OSError) as exc:
        sock.close()
        raise DaemonNotRunning(str(exc)) from exc
    try:
        sock.sendall((json.dumps(req) + "\n").encode("utf-8"))
        buf = b""
        while b"\n" not in buf:
            chunk = sock.recv(65536)
            if not chunk:
                break
            buf += chunk
    finally:
        sock.close()
    line, _, _ = buf.partition(b"\n")
    if not line:
        raise DaemonNotRunning("empty response")
    return json.loads(line.decode("utf-8"))


def daemon_rpc(method, *, autostart=True, timeout=5.0, **params):
    """Client helper. Auto-starts the daemon once on DaemonNotRunning."""
    req = {"method": method, **params}
    try:
        return _rpc_send(req, timeout=timeout)
    except DaemonNotRunning:
        if not autostart:
            raise
        _ensure_daemon_running()
        return _rpc_send(req, timeout=timeout)


def _ensure_daemon_running():
    """Launch the daemon if it isn't up. Used by auto-start path."""
    try:
        _rpc_send({"method": "ping"}, timeout=0.5)
        return
    except DaemonNotRunning:
        pass
    log("daemon not running — starting it")
    _fork_daemon_detached()
    deadline = time.monotonic() + WS_DAEMON_START_TIMEOUT_S
    while time.monotonic() < deadline:
        try:
            _rpc_send({"method": "ping"}, timeout=0.5)
            return
        except DaemonNotRunning:
            time.sleep(0.1)
    raise RuntimeError("daemon failed to start within timeout")


def _fork_daemon_detached():
    """Double-fork + setsid to spawn `ws.py daemon run` as a detached process."""
    pid = os.fork()
    if pid > 0:
        os.waitpid(pid, 0)  # reap the intermediate child
        return
    # First child
    os.setsid()
    pid2 = os.fork()
    if pid2 > 0:
        os._exit(0)
    # Grandchild — actual daemon.
    os.chdir(str(HOME))
    devnull = os.open(os.devnull, os.O_RDWR)
    os.dup2(devnull, 0)
    os.dup2(devnull, 1)
    WS_DAEMON_LOG.parent.mkdir(parents=True, exist_ok=True)
    log_fd = os.open(str(WS_DAEMON_LOG), os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
    os.dup2(log_fd, 2)
    os.close(devnull)
    os.close(log_fd)
    os.execv(sys.executable, [sys.executable, str(THIS_FILE), "daemon", "run"])


# ---- daemon CLI commands ----

def cmd_daemon_run(args):
    """Foreground event loop. `daemon start` execs into this after forking."""
    daemon = WsDaemon(WS_DAEMON_SOCKET)
    loop = asyncio.new_event_loop()
    asyncio.set_event_loop(loop)

    def _stop():
        _daemon_log_line("signal received")
        if daemon._shutdown_event is not None:
            daemon._shutdown_event.set()

    for sig in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
        try:
            loop.add_signal_handler(sig, _stop)
        except NotImplementedError:
            pass

    try:
        loop.run_until_complete(daemon.run())
    finally:
        loop.close()


def cmd_daemon_start(args):
    try:
        resp = _rpc_send({"method": "ping"}, timeout=0.5)
        emit({"ok": True, "running": True, "pid": resp.get("pid"), "alreadyRunning": True})
        return
    except DaemonNotRunning:
        pass
    # Remove any stale socket that a previous (unclean) exit left behind.
    try:
        WS_DAEMON_SOCKET.unlink()
    except FileNotFoundError:
        pass
    _fork_daemon_detached()
    deadline = time.monotonic() + WS_DAEMON_START_TIMEOUT_S
    while time.monotonic() < deadline:
        try:
            resp = _rpc_send({"method": "ping"}, timeout=0.5)
            emit({"ok": True, "running": True, "pid": resp.get("pid"), "started": True})
            return
        except DaemonNotRunning:
            time.sleep(0.1)
    emit_error("daemon failed to start within timeout")


def cmd_daemon_stop(args):
    try:
        _rpc_send({"method": "shutdown"}, timeout=2.0)
    except DaemonNotRunning:
        emit({"ok": True, "wasRunning": False})
        return
    deadline = time.monotonic() + WS_DAEMON_STOP_TIMEOUT_S
    while time.monotonic() < deadline:
        if not WS_DAEMON_SOCKET.exists():
            emit({"ok": True, "wasRunning": True})
            return
        time.sleep(0.1)
    emit_error("daemon did not stop within timeout")


def cmd_daemon_status(args):
    try:
        resp = _rpc_send({"method": "ping"}, timeout=0.5)
        emit({
            "ok": True,
            "running": True,
            "pid": resp.get("pid"),
            "workspaceCount": resp.get("workspaceCount", 0),
            "socket": str(WS_DAEMON_SOCKET),
        })
    except DaemonNotRunning:
        emit({"ok": True, "running": False, "socket": str(WS_DAEMON_SOCKET)})


def cmd_daemon_logs(args):
    if not WS_DAEMON_LOG.exists():
        emit({"ok": True, "lines": [], "path": str(WS_DAEMON_LOG)})
        return
    with open(WS_DAEMON_LOG, "rb") as f:
        f.seek(0, 2)
        size = f.tell()
        read_size = min(size, LOG_TAIL_BYTES)
        f.seek(size - read_size)
        data = f.read()
    lines = data.decode("utf-8", errors="replace").splitlines()
    tail = getattr(args, "tail", None)
    if tail:
        lines = lines[-tail:]
    emit({"ok": True, "lines": lines, "path": str(WS_DAEMON_LOG)})


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

    parent = detect_parent_workspace()
    if parent == name:
        parent = None

    tmux_session = f"{parent}/{name}" if parent else name
    existing = ws_dir(name).exists()

    missing = [r for r in repos if not r["remoteResolved"]]
    ok = len(missing) == 0

    emit({
        "ok": ok,
        "workspace": name,
        "parent": parent,
        "tmuxSession": tmux_session,
        "serveSubdomain": f"{name}.local.<lb>.<domain>",
        "repos": repos,
        "existing": existing,
        "error": "unresolved-remotes" if missing else None,
        "missingRepos": [r["repo"] for r in missing] or None,
    })


# ---------------------------------------------------------------- Command: init

def _wait_for_bend_registration(start_time, timeout=120):
    """Wait until bend writes a fresh *-introspection file to route-configs.

    The workspace Claude's devex-mcp-server only scans route-configs at startup,
    so bend must be registered BEFORE we launch the workspace Claude. Otherwise
    the MCP server finds nothing and the bend_* tools never appear.
    """
    deadline = time.time() + timeout
    while time.time() < deadline:
        if ROUTE_CONFIGS_DIR.exists():
            for f in ROUTE_CONFIGS_DIR.iterdir():
                if f.name.endswith("-introspection"):
                    try:
                        if f.stat().st_mtime >= start_time:
                            log(f"bend registered: {f.name}")
                            return True
                    except OSError:
                        continue
        time.sleep(1)
    log(f"WARN: no fresh bend introspection after {timeout}s")
    return False


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
    parent = normalize(args.parent) if args.parent else None
    tmux_session = f"{parent}/{name}" if parent else name
    prompt_file = pathlib.Path(f"/tmp/ws-{name}-init-prompt.txt")
    wsdir = ws_dir(name)

    if not prompt_file.exists():
        emit_error(f"prompt file not found: {prompt_file}", recoverable=False)
        sys.exit(1)

    wsdir.mkdir(parents=True, exist_ok=True)

    # Shared serve-commands session + per-workspace window (for bend output)
    if not tmux_has_session(SHARED_SERVE_SESSION):
        tmux("new-session", "-d", "-s", SHARED_SERVE_SESSION, "-n", "_placeholder")
    if name not in tmux_list_windows(SHARED_SERVE_SESSION):
        tmux("new-window", "-t", SHARED_SERVE_SESSION, "-n", name, "-c", str(wsdir))
    tmux("kill-window", "-t", f"{SHARED_SERVE_SESSION}:_placeholder")

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
        setup_start = time.time()
        setup_results = _setup_repos(name, repo_specs)

        pkg_paths = _compute_pkg_paths(name, setup_results)
        if pkg_paths:
            log(f"init: starting serve for {len(pkg_paths)} packages...")
            _send_serve_command(name, pkg_paths)
            _wait_for_bend_registration(setup_start, timeout=120)
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
        "parent": parent,
        "tmuxSession": tmux_session,
        "serveWindow": f"{SHARED_SERVE_SESSION}:{name}",
        "workspaceDir": str(wsdir),
        "setup": setup_results,
    })


# ---------------------------------------------------------------- Clone + yarn helpers (for setup / add)

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
    return {"repo": repo_clone.name, "ok": True}


def has_claude_md(repo_clone):
    return (repo_clone / "CLAUDE.md").exists()


# ---------------------------------------------------------------- Command: setup

def select_packages(discovery):
    return [p["name"] for p in discovery["packages"] if p["isDefault"]]


def _send_serve_command(name, pkg_paths):
    """Send `uv run ws.py serve-daemon <name> <pkgs>` to the tmux serve window."""
    serve_cmd = (
        f"uv run {shlex.quote(str(THIS_FILE))} serve-daemon "
        f"{shlex.quote(name)} "
        + " ".join(shlex.quote(str(p)) for p in pkg_paths)
    )
    tmux("send-keys", "-t", f"{SHARED_SERVE_SESSION}:{name}", serve_cmd, "Enter")


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

    cache = load_discovery_cache()
    # Derive repo specs from the handoff prompt's repos — but we don't see the prompt.
    # Instead: treat every direct child dir of wsdir as a repo to set up.
    # This makes setup idempotent: re-running picks up any repos added since.
    repo_dirs = [p for p in wsdir.iterdir() if p.is_dir() and not p.name.startswith(".")]
    if not repo_dirs:
        emit_error(f"no repos found in {wsdir}", recoverable=True,
                   hint="call 'ws.py add <name> <repo[:branch]>...' instead")
        return

    repo_specs = []
    for d in repo_dirs:
        repo = d.name
        remote = resolve_remote(repo)
        if not remote:
            log(f"WARN: no remote found for {repo}")
            continue
        branch = current_branch(d) or f"{DEFAULT_BRANCH_PREFIX}{name}"
        repo_specs.append({"repo": repo, "remote": remote, "branch": branch})

    results = _setup_repos(name, repo_specs)
    pkg_paths = _compute_pkg_paths(name, results)

    serve_started = False
    if pkg_paths:
        _send_serve_command(name, pkg_paths)
        serve_started = True

    emit({
        "ok": all(r.get("ok") for r in results),
        "workspace": name,
        "workspaceDir": str(wsdir),
        "repos": results,
        "servePackages": [str(p) for p in pkg_paths],
        "serveStarted": serve_started,
        "serveWindow": f"{SHARED_SERVE_SESSION}:{name}",
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

    _stop_serve(name, wait_timeout=30)
    if pkg_paths:
        _send_serve_command(name, pkg_paths)

    emit({
        "ok": all(r.get("ok") for r in results),
        "workspace": name,
        "added": [r["repo"] for r in results],
        "repos": results,
        "servePackages": [str(p) for p in pkg_paths],
        "serveRestarted": True,
    })


# ---------------------------------------------------------------- Command: status

def _serve_is_up(name):
    return len(pgrep_f(daemon_marker(name))) > 0


def cmd_status(args):
    name = normalize(args.name)
    log_path = serve_log_path(name)
    if not log_path.exists():
        emit({
            "ok": True,
            "workspace": name,
            "state": "not_running",
            "serveUp": _serve_is_up(name),
            "packages": [],
            "errors": [{"type": "NO_LOG", "fatal": True, "line": f"No serve log at {log_path}"}],
            "allReady": False,
            "logPath": str(log_path),
        })
        return

    mtime = os.path.getmtime(log_path)
    stale_seconds = round(time.time() - mtime, 1)
    text, total_bytes = read_tail(log_path)
    result = parse_serve_log(text)

    if stale_seconds > 60 and result["state"] == "starting":
        result["state"] = "stale"
        result["errors"].append({
            "type": "STALE_LOG", "fatal": True,
            "line": f"Log not updated in {round(stale_seconds)}s and no packages detected",
        })

    cache = load_discovery_cache()
    wsdir = ws_dir(name)
    urls = {}
    if wsdir.exists():
        for d in wsdir.iterdir():
            if not d.is_dir() or d.name.startswith("."):
                continue
            repo_entry = cache.get(d.name, {})
            repo_urls = repo_entry.get("urls", {})
            for pkg_name, u in repo_urls.items():
                lb = u.get("lb", "app")
                basename = u.get("basename")
                if basename:
                    domain = LB_DOMAIN_MAP.get(lb, f"{lb}.hubteamqa.com")
                    urls[pkg_name] = f"https://{name}.local.{domain}{basename}"

    emit({
        "ok": True,
        "workspace": name,
        "state": result["state"],
        "serveUp": _serve_is_up(name),
        "allReady": result["allReady"],
        "packages": result["packages"],
        "errors": result["errors"],
        "urls": urls,
        "staleSeconds": stale_seconds,
        "logPath": str(log_path),
        "logBytes": total_bytes,
    })


# ---------------------------------------------------------------- Command: wait-ready

def cmd_wait_ready(args):
    name = normalize(args.name)
    deadline = time.time() + args.timeout
    last_state = None
    poll_interval = 5

    while time.time() < deadline:
        log_path = serve_log_path(name)
        if not log_path.exists():
            state = "not_running"
        else:
            text, _ = read_tail(log_path)
            parsed = parse_serve_log(text)
            state = parsed["state"]
            if state == "ready":
                cmd_status(args)
                return
            if state == "error":
                log(f"[{name}] reached error state; aborting wait")
                cmd_status(args)
                return
        if state != last_state:
            log(f"[{name}] state={state}")
            last_state = state
        time.sleep(poll_interval)

    log(f"[{name}] timeout after {args.timeout}s")
    cmd_status(args)


# ---------------------------------------------------------------- Command: urls

def cmd_urls(args):
    name = normalize(args.name)
    wsdir = ws_dir(name)
    cache = load_discovery_cache()
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

def _stop_serve(name, wait_timeout=30):
    """Send SIGTERM to serve-daemon, escalate to SIGKILL. Return list of actions."""
    name = normalize(name)
    marker = daemon_marker(name)
    pids = pgrep_f(marker)
    actions = []
    if not pids:
        return {"actions": ["no daemon found"], "pidsKilled": []}

    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
            actions.append(f"SIGTERM pid={pid}")
        except ProcessLookupError:
            actions.append(f"pid={pid} already gone")
            continue

    deadline = time.time() + wait_timeout
    while time.time() < deadline:
        remaining = [p for p in pids if pid_alive(p)]
        if not remaining:
            actions.append("all stopped gracefully")
            return {"actions": actions, "pidsKilled": pids}
        time.sleep(1)

    # Escalate
    still_alive = [p for p in pids if pid_alive(p)]
    for pid in still_alive:
        actions.append(f"SIGKILL pid={pid}")
        try:
            kill_tree(pid, signal.SIGKILL)
        except Exception as e:
            actions.append(f"kill_tree failed: {e}")

    return {"actions": actions, "pidsKilled": pids}


def cmd_stop(args):
    name = normalize(args.name)
    result = _stop_serve(name)
    if args.teardown:
        tmux("kill-window", "-t", f"{SHARED_SERVE_SESSION}:{name}")
        result["actions"].append(f"killed tmux window {SHARED_SERVE_SESSION}:{name}")

    emit({"ok": True, "workspace": name, **result})


# ---------------------------------------------------------------- Command: restart

def cmd_restart(args):
    name = normalize(args.name)
    wsdir = ws_dir(name)
    if not wsdir.exists():
        emit_error(f"workspace dir does not exist: {wsdir}", recoverable=False)
        return

    stop_result = _stop_serve(name)

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

    # Recreate the serve window if it's missing
    if not tmux_has_session(SHARED_SERVE_SESSION):
        tmux("new-session", "-d", "-s", SHARED_SERVE_SESSION, "-n", "_placeholder")
    if name not in tmux_list_windows(SHARED_SERVE_SESSION):
        tmux("new-window", "-t", SHARED_SERVE_SESSION, "-n", name, "-c", str(wsdir))

    if pkg_paths:
        _send_serve_command(name, pkg_paths)

    emit({
        "ok": True,
        "workspace": name,
        "stop": stop_result,
        "servePackages": [str(p) for p in pkg_paths],
        "serveWindow": f"{SHARED_SERVE_SESSION}:{name}",
    })


# ---------------------------------------------------------------- Command: nuke

def cmd_nuke(args):
    name = normalize(args.name)
    wsdir = ws_dir(name)
    actions = []

    stop_result = _stop_serve(name)
    actions.extend(stop_result["actions"])

    # Kill tmux windows / sessions
    tmux("kill-window", "-t", f"{SHARED_SERVE_SESSION}:{name}")
    actions.append(f"killed window {SHARED_SERVE_SESSION}:{name}")

    # Kill workspace session and any child sessions
    sessions_result = tmux("list-sessions", "-F", "#{session_name}")
    sessions = sessions_result.stdout.split() if sessions_result.returncode == 0 else []
    for s in sessions:
        if s == name or s.startswith(f"{name}/") or s.endswith(f"/{name}"):
            tmux("kill-session", "-t", s)
            actions.append(f"killed session {s}")

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


# ---------------------------------------------------------------- Command: serve-daemon

def cmd_serve_daemon(args):
    name = normalize(args.name)
    pkg_paths = args.pkgs
    daemon = ServeDaemon(name, pkg_paths)
    daemon.run()


# ---------------------------------------------------------------- main

def main():
    parser = argparse.ArgumentParser(description="ws.py — workspace manager")
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("plan", help="Validate + preview a workspace plan")
    p.add_argument("name")
    p.add_argument("repos", nargs="+")

    p = sub.add_parser("init", help="Create tmux session + (optionally clone/yarn/serve) + launch workspace Claude")
    p.add_argument("name")
    p.add_argument("--parent", default=None)
    p.add_argument(
        "--repos", nargs="+", default=None,
        help="Repo specs (repo[:branch]); when given, init runs the full setup "
             "(clone + yarn + serve) and waits for bend to register before "
             "launching the workspace Claude.",
    )

    p = sub.add_parser("setup", help="Clone + yarn + discover + serve for workspace")
    p.add_argument("name")

    p = sub.add_parser("add", help="Add repos to an existing workspace")
    p.add_argument("name")
    p.add_argument("repos", nargs="+")

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

    p = sub.add_parser("stop", help="Stop the serve daemon")
    p.add_argument("name")
    p.add_argument("--teardown", action="store_true")

    p = sub.add_parser("restart", help="Stop + start serve")
    p.add_argument("name")

    p = sub.add_parser("nuke", help="Destroy workspace (serve, tmux, files)")
    p.add_argument("name")
    p.add_argument("--delete-branches", action="store_true")

    p = sub.add_parser("discover", help="Discover packages/URLs for one repo path")
    p.add_argument("repo_path")
    p.add_argument("--workspace", default=None)

    p = sub.add_parser("serve-daemon",
                       help="(internal) bend serve wrapper with signal traps")
    p.add_argument("name")
    p.add_argument("pkgs", nargs="+")

    p = sub.add_parser("daemon", help="ws-daemon lifecycle (single long-lived process)")
    dsub = p.add_subparsers(dest="daemon_command", required=True)
    dsub.add_parser("run", help="Foreground event loop (used by `start` after fork)")
    dsub.add_parser("start", help="Spawn the daemon in the background")
    dsub.add_parser("stop", help="Shut the daemon down over RPC")
    dsub.add_parser("status", help="Is the daemon running?")
    lg = dsub.add_parser("logs", help="Tail the daemon's log file")
    lg.add_argument("--tail", type=int, default=200)

    args = parser.parse_args()

    daemon_handlers = {
        "run": cmd_daemon_run,
        "start": cmd_daemon_start,
        "stop": cmd_daemon_stop,
        "status": cmd_daemon_status,
        "logs": cmd_daemon_logs,
    }

    if args.command == "daemon":
        daemon_handlers[args.daemon_command](args)
        return

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
        "serve-daemon": cmd_serve_daemon,
    }
    handlers[args.command](args)


if __name__ == "__main__":
    main()
