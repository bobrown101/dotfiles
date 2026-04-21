#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = [
#     "textual>=0.80",
#     "watchfiles>=0.21",
# ]
# ///
"""ws_tui.py — Textual polish layer over ws-daemon.

Sidebar lists workspaces (fed by the daemon's `list` RPC, refreshed on
route-configs changes + a 2s idle tick). Main pane has three tabs:

  • Serve log — streams `tail_serve` from the daemon
  • Status   — pretty-prints the `status` RPC
  • Claude   — placeholder; `<space> c` suspends the TUI and shells out
               to `ws.py attach-claude <name>` (fullscreen)

Vim-style bindings with space as leader. Outside the Claude pane,
`<space>` enters command mode; chord with one key to act. See the
BINDINGS map at the bottom of the file.

This file is a pure RPC client. It imports nothing from ws.py — the
socket path and RPC methods are the only contract.
"""
from __future__ import annotations

import asyncio
import json
import os
import pathlib
import shutil
import socket
import subprocess
import sys
from dataclasses import dataclass, field
from typing import Any

from textual import events, on, work
from textual.app import App, ComposeResult
from textual.binding import Binding
from textual.containers import Horizontal, Vertical
from textual.reactive import reactive
from textual.widgets import (
    DataTable, Footer, Header, RichLog, Static, TabbedContent, TabPane,
)

# --------------------------------------------------------------- constants

HOME = pathlib.Path.home()
WS_DAEMON_SOCKET = HOME / ".ws-daemon.sock"
ROUTE_CONFIGS_DIR = HOME / ".hubspot" / "route-configs"
WS_PY = pathlib.Path(__file__).parent / "ws.py"
LIST_POLL_INTERVAL_S = 2.0


# --------------------------------------------------------------- RPC helpers

class DaemonNotRunning(RuntimeError):
    pass


def rpc(method: str, **params: Any) -> dict:
    """Blocking single-request RPC. Used for all non-streaming calls."""
    req = {"method": method, **params}
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.settimeout(10.0)
    try:
        sock.connect(str(WS_DAEMON_SOCKET))
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


async def rpc_async(method: str, **params: Any) -> dict:
    """Run the blocking rpc() in a thread — fine for sub-10ms daemon calls."""
    return await asyncio.to_thread(rpc, method, **params)


# --------------------------------------------------------------- TUI app

@dataclass
class UiState:
    selected: str | None = None
    workspaces: list[dict] = field(default_factory=list)


class WsTuiApp(App):
    CSS = """
    #sidebar { width: 34; border-right: solid $accent; }
    #sidebar-title { padding: 0 1; color: $accent-lighten-1; text-style: bold; }
    #leader-hint { padding: 0 1; color: $text-muted; }
    DataTable { height: 1fr; }
    RichLog { height: 1fr; }
    #status-body { padding: 1 2; }
    """

    TITLE = "ws-tui"
    SUB_TITLE = "workspaces under ws-daemon"

    BINDINGS = [
        Binding("space", "enter_leader", "leader", show=True),
        Binding("escape", "leave_leader", "cancel", show=False),
        Binding("j", "row_down", "down", show=False),
        Binding("k", "row_up", "up", show=False),
        Binding("h", "prev_tab", "prev tab", show=False),
        Binding("l", "next_tab", "next tab", show=False),
        Binding("q", "quit", "quit", show=False),
    ]

    leader_active: reactive[bool] = reactive(False)

    def __init__(self) -> None:
        super().__init__()
        self.state = UiState()
        self._tail_task: asyncio.Task | None = None
        self._tail_sock: socket.socket | None = None

    # ---- compose -------------------------------------------------------

    def compose(self) -> ComposeResult:
        yield Header()
        with Horizontal():
            with Vertical(id="sidebar"):
                yield Static("Workspaces", id="sidebar-title")
                yield DataTable(id="ws-list", cursor_type="row", zebra_stripes=True)
                yield Static("", id="leader-hint")
            with Vertical(id="main"):
                with TabbedContent(initial="tab-serve"):
                    with TabPane("Serve log", id="tab-serve"):
                        yield RichLog(id="serve-log", wrap=False, markup=False, highlight=False, auto_scroll=True)
                    with TabPane("Status", id="tab-status"):
                        yield Static("(select a workspace)", id="status-body")
                    with TabPane("Claude", id="tab-claude"):
                        yield Static(
                            "Press  [b]<space> c[/b]  to attach to this workspace's Claude (fullscreen).\n\n"
                            "Ctrl-\\ detaches and returns you here.",
                            id="claude-body",
                        )
        yield Footer()

    # ---- lifecycle -----------------------------------------------------

    async def on_mount(self) -> None:
        table = self.query_one("#ws-list", DataTable)
        table.add_columns("workspace", "state", "serve", "claude")
        # @work methods are fire-and-forget — don't await them; set_interval
        # re-invokes refresh_list every LIST_POLL_INTERVAL_S without awaiting.
        self.refresh_list()
        self.set_interval(LIST_POLL_INTERVAL_S, self.refresh_list)
        # Watch route-configs for faster reaction to serve state changes.
        self._watch_task = asyncio.create_task(self._watch_route_configs())

    async def on_unmount(self) -> None:
        self._stop_tail()

    # ---- data refresh --------------------------------------------------

    @work(exclusive=True, group="list-refresh")
    async def refresh_list(self) -> None:
        try:
            resp = await rpc_async("list")
        except DaemonNotRunning:
            resp = {"ok": False, "workspaces": []}
            self.sub_title = "daemon not running — `ws.py daemon start`"
            return
        except Exception as exc:  # noqa: BLE001
            self.sub_title = f"list rpc error: {exc}"
            return
        self.sub_title = f"{len(resp.get('workspaces', []))} workspaces"
        self.state.workspaces = resp.get("workspaces") or []
        table = self.query_one("#ws-list", DataTable)
        # Preserve selection across refreshes.
        prev_cursor = table.cursor_row
        table.clear()
        for ws in self.state.workspaces:
            table.add_row(
                ws["name"],
                ws.get("state") or "-",
                "●" if ws.get("serveUp") else "·",
                "●" if ws.get("claudeUp") else "·",
                key=ws["name"],
            )
        if self.state.workspaces:
            row = min(prev_cursor, len(self.state.workspaces) - 1)
            table.move_cursor(row=max(row, 0))
            self.state.selected = self.state.workspaces[max(row, 0)]["name"]
        else:
            self.state.selected = None

    async def _watch_route_configs(self) -> None:
        """Tick the list sooner when bend writes/removes an introspection file."""
        try:
            from watchfiles import awatch
        except ImportError:
            return
        if not ROUTE_CONFIGS_DIR.exists():
            return
        try:
            async for _changes in awatch(str(ROUTE_CONFIGS_DIR)):
                self.refresh_list()
        except (asyncio.CancelledError, OSError):
            return

    # ---- tail_serve streaming ------------------------------------------

    def _stop_tail(self) -> None:
        if self._tail_task is not None:
            self._tail_task.cancel()
            self._tail_task = None
        if self._tail_sock is not None:
            try:
                self._tail_sock.close()
            except OSError:
                pass
            self._tail_sock = None

    @work(exclusive=True, group="tail-serve")
    async def start_tail(self, name: str) -> None:
        self._stop_tail()
        log = self.query_one("#serve-log", RichLog)
        log.clear()
        log.write(f"[dim]tailing serve for {name}…[/dim]")
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.settimeout(5.0)
        try:
            await asyncio.to_thread(sock.connect, str(WS_DAEMON_SOCKET))
        except OSError as exc:
            log.write(f"[red]tail connect failed: {exc}[/red]")
            sock.close()
            return
        sock.settimeout(None)
        self._tail_sock = sock
        req = {"method": "tail_serve", "name": name, "follow": True}
        await asyncio.to_thread(sock.sendall, (json.dumps(req) + "\n").encode("utf-8"))
        # Ack line.
        buf = b""
        try:
            while b"\n" not in buf:
                chunk = await asyncio.to_thread(sock.recv, 65536)
                if not chunk:
                    return
                buf += chunk
        except OSError:
            return
        line, _, rest = buf.partition(b"\n")
        try:
            ack = json.loads(line.decode("utf-8"))
        except json.JSONDecodeError:
            log.write("[red]invalid ack on tail_serve[/red]")
            return
        if not ack.get("ok"):
            log.write(f"[red]tail_serve refused: {ack.get('error')}[/red]")
            return
        if rest:
            self._emit_log_bytes(log, rest)
        while True:
            try:
                chunk = await asyncio.to_thread(sock.recv, 65536)
            except OSError:
                break
            if not chunk:
                break
            self._emit_log_bytes(log, chunk)

    def _emit_log_bytes(self, log: RichLog, data: bytes) -> None:
        try:
            text = data.decode("utf-8", errors="replace")
        except Exception:  # noqa: BLE001
            return
        for line in text.splitlines():
            log.write(line)

    # ---- selection / tab changes --------------------------------------

    @on(DataTable.RowHighlighted, "#ws-list")
    def on_row_highlighted(self, event: DataTable.RowHighlighted) -> None:
        key = event.row_key.value if event.row_key else None
        if not key:
            return
        self.state.selected = str(key)
        self.refresh_status()
        self.start_tail(str(key))

    @work(exclusive=True, group="status-refresh")
    async def refresh_status(self) -> None:
        name = self.state.selected
        body = self.query_one("#status-body", Static)
        if not name:
            body.update("(no workspace selected)")
            return
        try:
            resp = await rpc_async("status", name=name)
        except DaemonNotRunning:
            body.update("daemon not running")
            return
        except Exception as exc:  # noqa: BLE001
            body.update(f"status rpc error: {exc}")
            return
        body.update(_format_status(resp))

    # ---- actions -------------------------------------------------------

    def action_enter_leader(self) -> None:
        self.leader_active = True
        self.query_one("#leader-hint", Static).update(
            "[b]leader:[/b] r=restart  s=stop  c=attach  u=urls  q=quit  [b]esc[/b]=cancel"
        )

    def action_leave_leader(self) -> None:
        self.leader_active = False
        self.query_one("#leader-hint", Static).update("")

    def action_row_down(self) -> None:
        table = self.query_one("#ws-list", DataTable)
        table.action_cursor_down()

    def action_row_up(self) -> None:
        table = self.query_one("#ws-list", DataTable)
        table.action_cursor_up()

    def action_next_tab(self) -> None:
        tabs = self.query_one(TabbedContent)
        order = ["tab-serve", "tab-status", "tab-claude"]
        try:
            idx = order.index(tabs.active)
        except ValueError:
            idx = 0
        tabs.active = order[(idx + 1) % len(order)]

    def action_prev_tab(self) -> None:
        tabs = self.query_one(TabbedContent)
        order = ["tab-serve", "tab-status", "tab-claude"]
        try:
            idx = order.index(tabs.active)
        except ValueError:
            idx = 0
        tabs.active = order[(idx - 1) % len(order)]

    # ---- leader chords -------------------------------------------------

    def on_key(self, event: events.Key) -> None:
        if not self.leader_active:
            return
        key = event.key
        # Swallow the key so default bindings don't fire during leader.
        event.stop()
        event.prevent_default()
        self.action_leave_leader()
        name = self.state.selected
        if not name:
            self.notify("no workspace selected", severity="warning")
            return
        if key == "r":
            self._chord_restart(name)
        elif key == "s":
            self._chord_stop(name)
        elif key == "c":
            self._chord_attach(name)
        elif key == "u":
            self._chord_urls(name)
        elif key == "q":
            self.exit()
        else:
            self.notify(f"unbound chord: <space> {key}", severity="warning")

    @work(exclusive=True, group="chord")
    async def _chord_restart(self, name: str) -> None:
        self.notify(f"restart_serve {name}…")
        try:
            resp = await rpc_async("restart_serve", name=name)
        except Exception as exc:  # noqa: BLE001
            self.notify(f"restart failed: {exc}", severity="error")
            return
        self.notify(
            "restarted" if resp.get("ok") else f"restart refused: {resp.get('error')}",
            severity="information" if resp.get("ok") else "error",
        )
        self.refresh_list()

    @work(exclusive=True, group="chord")
    async def _chord_stop(self, name: str) -> None:
        self.notify(f"stop_serve {name}…")
        try:
            resp = await rpc_async("stop_serve", name=name)
        except Exception as exc:  # noqa: BLE001
            self.notify(f"stop failed: {exc}", severity="error")
            return
        self.notify(
            "stopped" if resp.get("ok") else f"stop refused: {resp.get('error')}",
            severity="information" if resp.get("ok") else "error",
        )
        self.refresh_list()

    def _chord_attach(self, name: str) -> None:
        """Fullscreen shell-out to ws.py attach-claude.

        Textual's app.suspend() restores the alternate screen + raw-mode state
        on exit from the with-block, so we just shell out inside it. claude
        keeps running in ws-daemon regardless of how the subprocess exits —
        Ctrl-\\ detaches cleanly, SIGINT/SIGTERM on the CLI also only closes
        the proxy. See notes/PHASE-5-PTYPANE-DESIGN.md for what an embedded
        alternative to this fullscreen path would look like.
        """
        if not WS_PY.exists():
            self.notify(f"ws.py missing at {WS_PY}", severity="error")
            return
        uv_bin = shutil.which("uv")
        if uv_bin is None:
            self.notify("`uv` not in PATH — can't shell out to ws.py", severity="error")
            return
        with self.suspend():
            subprocess.run([uv_bin, "run", str(WS_PY), "attach-claude", name])

    @work(exclusive=True, group="chord")
    async def _chord_urls(self, name: str) -> None:
        try:
            resp = await rpc_async("status", name=name)
        except Exception as exc:  # noqa: BLE001
            self.notify(f"urls failed: {exc}", severity="error")
            return
        urls = resp.get("urls") or {}
        if not urls:
            self.notify(f"no urls for {name}", severity="warning")
            return
        lines = []
        for pkg, entry in urls.items():
            u = entry.get("url") if isinstance(entry, dict) else entry
            if u:
                lines.append(f"{pkg}: {u}")
        if lines:
            self.notify("\n".join(lines), timeout=10)
        else:
            self.notify("no resolved urls yet", severity="warning")


# --------------------------------------------------------------- formatting

def _format_status(resp: dict) -> str:
    if not resp.get("ok"):
        return f"status error: {resp.get('error', 'unknown')}"
    lines = []
    lines.append(f"[b]{resp.get('workspace')}[/b]")
    lines.append(f"state: {resp.get('state')}")
    lines.append(f"serve: {'up' if resp.get('serveUp') else 'down'}"
                 + (f" (pid {resp.get('servePid')})" if resp.get("servePid") else ""))
    lines.append(f"claude: {'up' if resp.get('claudeUp') else 'down'}"
                 + (f" (pid {resp.get('claudePid')})" if resp.get("claudePid") else ""))
    lines.append(f"bendRegistered: {resp.get('bendRegistered')}")
    lines.append(f"attached clients: {resp.get('attachedClients', 0)}")
    pkgs = resp.get("packages") or []
    if pkgs:
        lines.append("")
        lines.append("[b]packages[/b]")
        for p in pkgs:
            lines.append(f"  • {p}")
    errors = resp.get("errors") or []
    if errors:
        lines.append("")
        lines.append("[b red]errors[/b red]")
        for e in errors[-10:]:
            lines.append(f"  ! {e}")
    urls = resp.get("urls") or {}
    if urls:
        lines.append("")
        lines.append("[b]urls[/b]")
        for pkg, entry in urls.items():
            u = entry.get("url") if isinstance(entry, dict) else entry
            if u:
                lines.append(f"  {pkg}: {u}")
    return "\n".join(lines)


# --------------------------------------------------------------- entrypoint

def main() -> None:
    if not WS_DAEMON_SOCKET.exists():
        print(
            "ws-daemon is not running. Start it with:\n\n"
            f"  uv run {WS_PY} daemon start\n",
            file=sys.stderr,
        )
        sys.exit(2)
    WsTuiApp().run()


if __name__ == "__main__":
    main()
