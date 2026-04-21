# ws-daemon + TUI implementation TODO

Live task list for the `ws-daemon` / `ws_tui.py` migration.

Canonical design: `~/.claude/plans/could-we-have-keep-generic-dewdrop.md`.

One commit per checked item. Commit prefix: `ws-daemon:` or `ws-tui:`.
No emoji, no `Co-Authored-By` footer on this branch.

---

## Phase 0 — process setup

- [x] Create branch `brbrown/ws-tui-daemon`
- [x] Create `~/src/dotfiles/.claude/skills/ws/notes/` dir
- [x] Write initial `IMPLEMENTATION-TODO.md`
- [x] Write initial `SESSION-LOG.md` with "Session 1 start" entry
- [ ] Commit: `ws-daemon: scaffold implementation tracking`

## Phase 1 — daemon skeleton

- [x] Add `ws.py daemon run` subcommand (asyncio event loop, binds `~/.ws-daemon.sock`, accepts connections, responds to `ping` / `shutdown`)
- [x] Add `ws.py daemon start` (fork + setsid + exit when socket accepts)
- [x] Add `ws.py daemon stop` (RPC `shutdown`, wait for socket cleanup)
- [x] Add `ws.py daemon status` (socket connect + `ping`)
- [x] Add `ws.py daemon logs` (tail `~/.ws-daemon.log`)
- [x] Auto-start logic in all RPC-client commands (opt-out via `--no-autostart`) — helper `daemon_rpc(..., autostart=True)` now used by every rewired command
- [x] Verify: `ws.py daemon start` → `ws.py daemon status` returns running; `ws.py daemon stop` returns; socket file gone

## Phase 2 — daemon owns serve

- [x] Daemon RPC: `start_serve` (Popen `bend reactor serve`, wire stdout → ring buffer)
- [x] Daemon RPC: `stop_serve` (SIGTERM → 15s → SIGKILL)
- [x] Daemon RPC: `restart_serve`
- [x] Daemon RPC: `status` (derive from ring buffer + process state)
- [x] Daemon RPC: `list`
- [x] Daemon RPC: `tail_serve` (both follow and non-follow)
- [x] Daemon RPC: `remove_pkg`
- [x] MCP ordering: `start_serve` blocks until `~/.hubspot/route-configs/<pid>-introspection` appears (port `_wait_for_bend_registration`)
- [x] Rewire `cmd_init` / `cmd_setup` / `cmd_add` / `cmd_restart` / `cmd_stop` / `cmd_nuke` / `cmd_status` / `cmd_wait_ready` to call daemon
- [x] Delete `ServeDaemon` class, `_send_serve_command`, `SHARED_SERVE_SESSION`, `daemon_marker`, module-level `_stop_serve` / `_serve_is_up` / `_wait_for_bend_registration`, `DAEMON_LOG_FILE`, `cmd_serve_daemon`, `serve-daemon` subparser, `--teardown` flag
- [x] Update `SKILL.md` serve-related guidance
- [x] End-to-end test: daemon-level only (lifecycle + start_serve with bogus pkgPath + bend-registration snapshot filter). Full workspace spin-up with real repos deferred — will happen organically when Brady creates his next real workspace on this branch.

## Phase 3 — daemon owns Claude

- [x] Daemon RPC: `start_claude` (`pty.openpty` + asyncio subprocess `hsclaude`, close slave in daemon, drain master fd into ring buffer)
- [x] Daemon RPC: `stop_claude` (SIGTERM pgroup → 5s → SIGKILL)
- [x] Daemon RPC: `attach_claude` (ack JSON → switch socket to raw bytes, replay ring buffer, fan-out)
- [x] Daemon RPC: `resize_claude`
- [x] New CLI `ws.py attach-claude` (terminal raw mode, stdin ↔ socket proxy, `Ctrl-\` local detach, SIGWINCH → resize_claude)
- [x] `cmd_init` stops creating tmux session; issues `start_claude` RPC
- [x] Remove `/tmp/ws-<name>-launch.sh` generation
- [x] Rewrite `cmd_nuke` Claude-teardown path
- [x] Update `SKILL.md` — "switch to tmux session" → "run `ws.py attach-claude`"
- [x] Update `ARCHITECTURE.md` — replaced tmux row with ws-daemon row; redrew sequence-full + sequence-add diagrams around daemon RPCs.
- [x] Daemon-level smoke test: start_claude → resize_claude → stop_claude clean. Full attach/detach/re-attach e2e deferred until next real workspace init on this branch (needs a real tty).

## Phase 4 — TUI MVP (no embedded PTY)

- [x] `ws_tui.py` PEP 723 header + skeleton (Textual, watchfiles — pyte only pulled in if/when Phase 5 lands embedded PtyPane)
- [x] Sidebar `DataTable` fed by `list` RPC, refreshed by `watchfiles` + 2s timer
- [x] Serve-log tab streaming `tail_serve`
- [x] Status tab rendering `status` JSON
- [x] Vim-style keybindings with space leader (j/k/h/l, `<space>` + letter: r/s/c/u/q)
- [ ] Modals: add, remove, nuke-confirm, logs, grep, URL picker — deferred; URL picker works today as a toast notification, the rest are one screen each and can be added as daily-use demands
- [x] Claude tab placeholder — "press `<space> c` to attach (fullscreen)"
- [x] Shell-out to `ws.py attach-claude` via `app.suspend()` for the placeholder

## Phase 5 — attach mode

- [x] **Decide**: fullscreen `app.suspend()` + shell-out wins for now. Embedded `PtyPane` designed but deferred — see `notes/PHASE-5-PTYPANE-DESIGN.md` for the future-session pickup.
- [x] Fullscreen end-to-end: `<space> c` → `app.suspend()` → `ws.py attach-claude <name>` → `Ctrl-\` → return to sidebar. Lives in `ws_tui.py::_chord_attach`.
- [ ] (deferred) Implement `PtyPane` — only if daily-use ergonomics surface a real complaint. Design doc unblocks the future session.
- [ ] (deferred) Gate embedded pane behind `--experimental-pty` flag — same trigger.

## Decision items (non-coding)

- [x] **Phase-5 attach mode** — fullscreen suspend+attach chosen. Zero nested-redraw cost, ~10 LOC, reuses the daemon attach protocol unchanged. Embedded `PtyPane` documented in `notes/PHASE-5-PTYPANE-DESIGN.md`; revisit only if daily use produces a real ergonomic complaint.
- [ ] **Alias `ws.py serve-daemon ls`** to `ws.py list` — yes/no? Add only if it'd get used.
