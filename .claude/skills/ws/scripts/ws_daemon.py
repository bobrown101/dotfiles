"""ws_daemon — the ws-daemon singleton plus RPC client helpers.

The daemon exists for three reasons:
  1. Process ownership: `bend reactor serve` has to outlive the `ws.py` CLI
     call that started it. Something long-lived has to own the child and
     reap it cleanly on shutdown.
  2. Cross-process coordination: `ws status`, `ws logs`, `ws wait-ready`
     all need a single source of truth for "is serve up yet?" without each
     CLI having to re-scan ~/.hubspot/route-configs/ and guess.
  3. Streaming tail: `tail_serve` feeds from an in-memory ring buffer that
     survives log-file truncation.

(There was a short-lived TUI experiment that used the same socket; that's
gone now. The RPC layer stays because (1)-(3) don't collapse into one-shot
CLI calls.)

In-memory state is mirrored to ~/.ws-daemon.state.json on every start/stop.
On fresh daemon startup we load that file, validate each entry via pid +
ps-lstart, and adopt the ones whose bend is still alive. After a reboot
every lstart check fails, so we reset cleanly.
"""

import asyncio
import dataclasses
import datetime
import json
import logging
import logging.handlers
import os
import pathlib
import shlex
import signal
import socket
import subprocess  # noqa: F401 — used by _fork_daemon_detached indirectly
import sys
import time
import uuid

from ws_lib import (
    BEND_REGISTRATION_TIMEOUT_S,
    HOME,
    LB_DOMAIN_MAP,
    LOG_TAIL_BYTES,
    ROUTE_CONFIGS_DIR,
    SERVE_RING_BYTES,
    SERVE_STOP_GRACE_S,
    WS_DAEMON_LOG,
    WS_DAEMON_LOG_BACKUPS,
    WS_DAEMON_LOG_MAX_BYTES,
    WS_DAEMON_SOCKET,
    WS_DAEMON_START_TIMEOUT_S,
    WS_DAEMON_STATE,
    WS_DAEMON_STOP_TIMEOUT_S,
    WS_SCRIPT_PATH,
    emit,
    emit_error,
    load_discovery_cache,
    log,
    normalize,
    parse_serve_log,
    process_alive,
    process_start_time,
    serve_log_path,
    ws_dir,
)


# ---------------------------------------------------------------- Types

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
    serve_tail_subscribers: set = dataclasses.field(default_factory=set)
    # Identity fields for restart/reboot reconciliation. Populated on spawn
    # (self-owned) or on adoption (previous daemon spawned; we reattach by pid).
    bend_marker: "str | None" = None
    bend_lstart: "str | None" = None
    adopted: bool = False
    adopted_pid: "int | None" = None


# ---------------------------------------------------------------- Logging

_daemon_logger = None


def _configure_daemon_logger():
    """Install a rotating file handler on the daemon logger. Idempotent."""
    global _daemon_logger
    if _daemon_logger is not None:
        return _daemon_logger
    WS_DAEMON_LOG.parent.mkdir(parents=True, exist_ok=True)
    logger = logging.getLogger("ws-daemon")
    logger.setLevel(logging.INFO)
    handler = logging.handlers.RotatingFileHandler(
        str(WS_DAEMON_LOG),
        maxBytes=WS_DAEMON_LOG_MAX_BYTES,
        backupCount=WS_DAEMON_LOG_BACKUPS,
    )
    handler.setFormatter(logging.Formatter("%(message)s"))
    logger.handlers = [handler]
    logger.propagate = False
    _daemon_logger = logger
    return logger


def _daemon_log_line(msg, **fields):
    """Append one JSON-line to the daemon log. Best-effort; swallows errors."""
    try:
        logger = _configure_daemon_logger()
        entry = {
            "t": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%fZ"),
            "pid": os.getpid(),
            "msg": msg,
            **fields,
        }
        logger.info(json.dumps(entry, default=str))
    except OSError:
        pass


# ---------------------------------------------------------------- State checkpoint
# Survives daemon crashes so a fresh daemon can adopt bend processes spawned
# by the previous one. After a reboot, every stored (pid, lstart) becomes
# invalid → reconciliation drops them cleanly.

def _load_daemon_state():
    if not WS_DAEMON_STATE.exists():
        return {"workspaces": {}}
    try:
        data = json.loads(WS_DAEMON_STATE.read_text())
    except (json.JSONDecodeError, OSError):
        return {"workspaces": {}}
    if not isinstance(data, dict):
        return {"workspaces": {}}
    data.setdefault("workspaces", {})
    return data


def _save_daemon_state(daemon):
    """Serialize the daemon's workspace registry atomically."""
    entries = {}
    for name, ws in daemon.workspaces.items():
        pid = None
        if ws.serve_proc is not None and ws.serve_proc.returncode is None:
            pid = ws.serve_proc.pid
        elif getattr(ws, "adopted_pid", None):
            pid = ws.adopted_pid
        if not pid:
            continue
        entries[name] = {
            "pid": pid,
            "lstart": getattr(ws, "bend_lstart", None) or process_start_time(pid),
            "pkgPaths": [str(p) for p in ws.serve_pkg_paths],
            "marker": getattr(ws, "bend_marker", None),
            "bendRegistered": ws.serve_bend_registered,
            "startedAt": ws.serve_started_at,
        }
    payload = {"workspaces": entries}
    try:
        WS_DAEMON_STATE.parent.mkdir(parents=True, exist_ok=True)
        tmp = WS_DAEMON_STATE.with_suffix(".json.tmp")
        tmp.write_text(json.dumps(payload, indent=2, sort_keys=True, default=str))
        tmp.replace(WS_DAEMON_STATE)
    except OSError as exc:
        _daemon_log_line("state save failed", error=str(exc))


# ---------------------------------------------------------------- WsDaemon

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
        self._reconcile_state()
        self._server = await asyncio.start_unix_server(
            self._handle_client, path=str(self.socket_path)
        )
        try:
            os.chmod(self.socket_path, 0o600)
        except OSError:
            pass
        _daemon_log_line(
            "daemon started",
            socket=str(self.socket_path),
            adopted=sorted(self.workspaces.keys()),
        )
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

    def _reconcile_state(self):
        """Adopt previous-daemon-owned bends whose (pid, lstart) still match.

        Anything that fails validation (pid dead, lstart differs, e.g. after a
        reboot) gets dropped. State is rewritten to match reality before we
        accept any RPCs.
        """
        state = _load_daemon_state()
        entries = state.get("workspaces", {}) or {}
        adopted = []
        dropped = []
        for name, entry in entries.items():
            pid = entry.get("pid")
            want_lstart = entry.get("lstart")
            if not pid or not process_alive(pid):
                dropped.append({"workspace": name, "reason": "pid-dead", "pid": pid})
                continue
            have_lstart = process_start_time(pid)
            if not have_lstart or have_lstart != want_lstart:
                dropped.append({
                    "workspace": name,
                    "reason": "lstart-mismatch",
                    "pid": pid,
                    "want": want_lstart,
                    "have": have_lstart,
                })
                continue
            ws = Workspace(name=name, wsdir=ws_dir(name))
            ws.serve_pkg_paths = [pathlib.Path(p) for p in entry.get("pkgPaths") or []]
            ws.serve_bend_registered = bool(entry.get("bendRegistered"))
            ws.serve_started_at = entry.get("startedAt")
            ws.serve_state = "adopted"
            ws.adopted = True
            ws.adopted_pid = int(pid)
            ws.bend_lstart = have_lstart
            ws.bend_marker = entry.get("marker")
            self.workspaces[name] = ws
            adopted.append({"workspace": name, "pid": pid})
        if adopted or dropped:
            _daemon_log_line("state reconcile", adopted=adopted, dropped=dropped)
        _save_daemon_state(self)

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
        if ws.adopted and ws.adopted_pid and process_alive(ws.adopted_pid):
            return {
                "ok": False,
                "error": f"adopted serve already running for {name}; call stop_serve or restart_serve first",
                "servePid": ws.adopted_pid,
            }
        ws.serve_pkg_paths = pkg_paths
        ws.serve_ring = RingBuffer(SERVE_RING_BYTES)
        ws.serve_state = "starting"
        ws.serve_packages = []
        ws.serve_errors = []
        ws.serve_bend_registered = False
        ws.serve_started_at = time.time()
        existing_introspection = _snapshot_introspection_files()
        await self._spawn_bend_serve(ws)
        registered = await self._wait_for_bend_registration(
            ws, existing_introspection,
        )
        ws.serve_bend_registered = registered
        return {
            "ok": True,
            "workspace": name,
            "servePid": ws.serve_proc.pid if ws.serve_proc else None,
            "bendRegistered": registered,
            "state": ws.serve_state,
        }

    async def _rpc_tail_serve(self, req, writer):
        """Stream serve log. Ack JSON, then raw bytes until disconnect.

        This method uses a different wire protocol than the other RPCs: one
        JSON ack line, then raw bytes streamed on the same socket until the
        client drops. There is no framing or versioning once the ack is sent.
        If we ever add a second streaming method, centralize this by adding
        a `protocol: "json"|"stream"` discriminator to the dispatch table so
        clients can reject unexpected mode switches.
        """
        name = normalize(req.get("name", ""))
        ws = self.workspaces.get(name)
        if ws is None:
            return {"ok": False, "error": f"unknown workspace {name!r}"}
        follow = bool(req.get("follow"))
        tail_bytes = int(req.get("tailBytes") or SERVE_RING_BYTES)
        await self._respond(writer, {
            "ok": True,
            "protocol": "log-stream",
            "follow": follow,
        })
        snap = ws.serve_ring.snapshot()
        if len(snap) > tail_bytes:
            snap = snap[-tail_bytes:]
        if snap:
            writer.write(snap)
            try:
                await writer.drain()
            except (ConnectionResetError, BrokenPipeError):
                return None
        if not follow:
            return None
        q = asyncio.Queue(maxsize=256)
        ws.serve_tail_subscribers.add(q)
        try:
            while True:
                chunk = await q.get()
                if chunk is None:
                    break
                writer.write(chunk)
                try:
                    await writer.drain()
                except (ConnectionResetError, BrokenPipeError):
                    break
        finally:
            ws.serve_tail_subscribers.discard(q)
        return None

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
        serve_up, serve_pid = _ws_serve_liveness(ws)
        return {
            "ok": True,
            "workspace": name,
            "state": ws.serve_state,
            "serveUp": serve_up,
            "adopted": ws.adopted,
            "claudeUp": False,  # Phase 3 populates this
            "servePid": serve_pid,
            "packages": ws.serve_packages,
            "errors": ws.serve_errors,
            "urls": _derive_urls_for(name),
            "pkgPaths": [str(p) for p in ws.serve_pkg_paths],
            "bendRegistered": ws.serve_bend_registered,
        }

    async def _rpc_list(self, req, writer):
        items = []
        for name, ws in sorted(self.workspaces.items()):
            serve_up, serve_pid = _ws_serve_liveness(ws)
            items.append({
                "name": name,
                "state": ws.serve_state,
                "serveUp": serve_up,
                "adopted": ws.adopted,
                "claudeUp": False,  # Phase 3 populates
                "servePid": serve_pid,
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
        marker = uuid.uuid4().hex
        ws.bend_marker = marker
        env = os.environ.copy()
        env["BEND_WORKTREE"] = ws.name
        env["WS_DAEMON_OWNED"] = marker
        env.setdefault("NODE_ARGS", "--max_old_space_size=16384")
        cmd = [
            "bend", "reactor", "serve",
            *[str(p) for p in ws.serve_pkg_paths],
            "--update", "--ts-watch", "--enable-tools", "--run-tests",
        ]
        _daemon_log_line(
            "serve spawn", name=ws.name,
            cmd=" ".join(shlex.quote(c) for c in cmd),
            marker=marker,
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
        ws.adopted = False
        ws.adopted_pid = None
        ws.bend_lstart = process_start_time(ws.serve_proc.pid)
        _daemon_log_line(
            "serve pid", name=ws.name, pid=ws.serve_proc.pid, lstart=ws.bend_lstart,
        )
        ws.serve_stdout_task = asyncio.create_task(self._read_serve_stdout(ws))
        _save_daemon_state(self)

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
                    for q in list(ws.serve_tail_subscribers):
                        try:
                            q.put_nowait(chunk)
                        except asyncio.QueueFull:
                            pass  # slow subscriber; drop
                    self._refresh_serve_state(ws)
        except Exception as exc:  # noqa: BLE001 — reader death is surfaced via state
            _daemon_log_line("serve stdout reader error", name=ws.name, error=str(exc))
        finally:
            rc = await proc.wait()
            _daemon_log_line("serve exited", name=ws.name, returncode=rc)
            if ws.serve_state not in ("error",):
                ws.serve_state = "not_running"
            for q in list(ws.serve_tail_subscribers):
                try:
                    q.put_nowait(None)  # sentinel → subscriber closes
                except asyncio.QueueFull:
                    pass

    def _refresh_serve_state(self, ws):
        text = ws.serve_ring.text()
        result = parse_serve_log(text)
        ws.serve_state = result["state"]
        ws.serve_packages = result["packages"]
        ws.serve_errors = result["errors"]

    async def _wait_for_bend_registration(self, ws, existing, timeout=BEND_REGISTRATION_TIMEOUT_S):
        """Block until bend writes a NEW *-introspection file to route-configs.

        The workspace Claude's devex-mcp-server only scans route-configs at
        startup, so bend must be registered BEFORE we launch Claude. We
        ignore files that pre-existed the spawn (other workspaces' bends
        or leftovers) and also bail early if this ws's bend has already
        exited — no point waiting the full timeout for a dead process.
        """
        deadline = time.time() + timeout
        while time.time() < deadline:
            if ws.serve_proc is None or ws.serve_proc.returncode is not None:
                _daemon_log_line(
                    "bend registration aborted: serve exited",
                    name=ws.name,
                    returncode=(ws.serve_proc.returncode if ws.serve_proc else None),
                )
                return False
            new_files = _snapshot_introspection_files() - existing
            if new_files:
                _daemon_log_line(
                    "bend registered", name=ws.name,
                    introspection=sorted(new_files),
                )
                return True
            await asyncio.sleep(1)
        _daemon_log_line("bend registration timeout", name=ws.name, timeout=timeout)
        return False

    async def _stop_serve(self, ws, grace=SERVE_STOP_GRACE_S):
        """SIGTERM → wait → SIGKILL. No-op if serve isn't running."""
        proc = ws.serve_proc
        pid = None
        if proc is not None and proc.returncode is None:
            pid = proc.pid
        elif ws.adopted and ws.adopted_pid and process_alive(ws.adopted_pid):
            pid = ws.adopted_pid
        if pid is None:
            ws.serve_state = "not_running"
            _save_daemon_state(self)
            return {"wasRunning": False}
        _daemon_log_line("serve stop: SIGTERM", name=ws.name, pid=pid)
        try:
            os.killpg(os.getpgid(pid), signal.SIGTERM)
        except (ProcessLookupError, PermissionError):
            pass
        returncode = None
        if proc is not None:
            try:
                await asyncio.wait_for(proc.wait(), timeout=grace)
                returncode = proc.returncode
            except asyncio.TimeoutError:
                _daemon_log_line("serve stop: SIGKILL", name=ws.name, pid=pid)
                try:
                    os.killpg(os.getpgid(pid), signal.SIGKILL)
                except (ProcessLookupError, PermissionError):
                    pass
                try:
                    await asyncio.wait_for(proc.wait(), timeout=5.0)
                    returncode = proc.returncode
                except asyncio.TimeoutError:
                    _daemon_log_line("serve stop: SIGKILL timeout", name=ws.name, pid=pid)
        else:
            # Adopted process: no subprocess.Process to await. Poll pid liveness.
            deadline = time.monotonic() + grace
            while time.monotonic() < deadline and process_alive(pid):
                await asyncio.sleep(0.25)
            if process_alive(pid):
                _daemon_log_line("serve stop: SIGKILL (adopted)", name=ws.name, pid=pid)
                try:
                    os.killpg(os.getpgid(pid), signal.SIGKILL)
                except (ProcessLookupError, PermissionError):
                    pass
                deadline = time.monotonic() + 5.0
                while time.monotonic() < deadline and process_alive(pid):
                    await asyncio.sleep(0.25)
            ws.adopted = False
            ws.adopted_pid = None
        ws.serve_state = "not_running"
        _save_daemon_state(self)
        return {"wasRunning": True, "returncode": returncode}

    async def _stop_all_serves(self):
        if not self.workspaces:
            return
        _daemon_log_line("shutting down all serves", count=len(self.workspaces))
        await asyncio.gather(
            *(self._stop_serve(ws) for ws in self.workspaces.values()),
            return_exceptions=True,
        )


# ---------------------------------------------------------------- Module-level helpers

def _ws_serve_liveness(ws):
    """Return (serveUp, servePid) handling both owned and adopted bends."""
    if ws.serve_proc is not None and ws.serve_proc.returncode is None:
        return True, ws.serve_proc.pid
    if ws.adopted and ws.adopted_pid and process_alive(ws.adopted_pid):
        return True, ws.adopted_pid
    return False, None


def _snapshot_introspection_files():
    """Return the set of current *-introspection filenames in route-configs.

    Used to distinguish 'a brand-new bend just registered' from 'some
    other workspace's existing bend is still sitting in this dir'.
    """
    if not ROUTE_CONFIGS_DIR.exists():
        return set()
    try:
        return {
            f.name for f in ROUTE_CONFIGS_DIR.iterdir()
            if f.name.endswith("-introspection")
        }
    except OSError:
        return set()


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


# ---------------------------------------------------------------- RPC client

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
    # Route stderr to devnull too; the daemon uses a RotatingFileHandler-backed
    # logger (_daemon_log_line) so an fd held directly on WS_DAEMON_LOG would
    # bypass rotation.
    os.dup2(devnull, 2)
    os.close(devnull)
    os.execv(sys.executable, [sys.executable, str(WS_SCRIPT_PATH), "daemon", "run"])


# ---------------------------------------------------------------- daemon CLI commands

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
