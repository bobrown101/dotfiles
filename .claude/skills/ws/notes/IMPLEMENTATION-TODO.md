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
- [ ] Auto-start logic in all RPC-client commands (opt-out via `--no-autostart`) — helper `daemon_rpc(..., autostart=True)` written, but no RPC-client commands exist yet (Phase 2)
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
- [ ] Rewire `cmd_init` / `cmd_setup` / `cmd_add` / `cmd_restart` / `cmd_stop` to call daemon
- [ ] Delete `ServeDaemon` class, `_send_serve_command`, `SHARED_SERVE_SESSION`, `daemon_marker`
- [ ] Update `SKILL.md` serve-related guidance
- [ ] End-to-end test: spin up workspace, serve registers, bend tools load in a fresh Claude session

## Phase 3 — daemon owns Claude

- [ ] Daemon RPC: `start_claude` (`pty.openpty` + asyncio subprocess `hsclaude`, close slave in daemon, attach pyte stream reader)
- [ ] Daemon RPC: `stop_claude`
- [ ] Daemon RPC: `attach_claude` (ack JSON → switch socket to raw bytes, replay ring buffer, fan-out)
- [ ] Daemon RPC: `resize_claude`
- [ ] New CLI `ws.py attach-claude` (terminal raw mode, stdin ↔ socket proxy, `Ctrl-\` local detach)
- [ ] `cmd_init` stops creating tmux session; issues `start_claude` RPC
- [ ] Remove `/tmp/ws-<name>-launch.sh` generation
- [ ] Rewrite `cmd_nuke` Claude-teardown path
- [ ] Update `SKILL.md` — "switch to tmux session" → "run `ws.py attach-claude`"
- [ ] Update `ARCHITECTURE.md` — replace tmux row with daemon row; redraw sequence diagram
- [ ] End-to-end test: attach, detach, re-attach, nuke

## Phase 4 — TUI MVP (no embedded PTY)

- [ ] `ws_tui.py` PEP 723 header + skeleton (Textual, pyte pinned, watchfiles)
- [ ] Sidebar `DataTable` fed by `list` RPC, refreshed by `watchfiles` + 2s timer
- [ ] Serve-log tab streaming `tail_serve`
- [ ] Status tab rendering `status` JSON
- [ ] Vim-style keybindings with space leader (j/k/h/l, `<space>` + letter)
- [ ] Modals: add, remove, nuke-confirm, logs, grep, URL picker
- [ ] Claude tab placeholder — "press `<space> c` to attach (fullscreen)"
- [ ] Shell-out to `ws.py attach-claude` via `app.suspend()` for the placeholder

## Phase 5 — attach mode

- [ ] **Decide**: embedded `PtyPane` widget vs stick with fullscreen suspend+attach (revisit after Phase 4 has been in daily use for a week)
- [ ] (if embedded) Implement `PtyPane` — pyte integration, render loop, keybinding, resize
- [ ] (if embedded) Gate behind `--experimental-pty` flag
- [ ] (either) End-to-end: `<space> c` → attach → type → detach → return to sidebar

## Decision items (non-coding)

- [ ] **Phase-5 attach mode** — embedded vs fullscreen. Revisit end of Phase 3; pivot only if daily-use fullscreen experience warrants the complexity. See "Open tradeoff" section in the plan.
- [ ] **Alias `ws.py serve-daemon ls`** to `ws.py list` — yes/no? Add only if it'd get used.
