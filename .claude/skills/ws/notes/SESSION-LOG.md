# ws-daemon + TUI session log

Append-only. One entry per Claude session. Keep it to non-obvious state — anything derivable from `git log` or code doesn't belong here.

Entry format:

```markdown
## YYYY-MM-DD (session N)
**Did**: bullets of what shipped this session
**Next**: exact task the next session should start on
**Notes**: surprises, rabbit holes, blockers, design decisions made mid-coding
```

---

## 2026-04-20 (session 1)

**Did**:
- Approved plan v2 at `~/.claude/plans/could-we-have-keep-generic-dewdrop.md` — single long-lived daemon, in-memory state, no dtach, Textual TUI with vim keybindings + space leader.
- Branched `brbrown/ws-tui-daemon` from `master` (commit `b9fc08c`).
- Created `notes/` dir, seeded `IMPLEMENTATION-TODO.md` and this log.
- **Phase 1 shipped** (`e7e6706`): `ws.py daemon run/start/stop/status/logs`. Asyncio event loop, Unix socket at `~/.ws-daemon.sock` (mode 0600), newline-JSON framing, `ping` + `shutdown` methods, structured JSON-line log at `~/.ws-daemon.log`. Verified end-to-end: start → status → stop → socket cleanup.
- Auto-start client helper (`daemon_rpc`, `_ensure_daemon_running`, `_fork_daemon_detached`) is in the file but nothing calls it yet — wired up in Phase 2 when the first RPC-client commands land.

**Next**: Phase 2 — daemon owns `bend reactor serve`. Start with the `Workspace` in-memory dataclass + `start_serve` RPC (MCP ordering: must block until `~/.hubspot/route-configs/<pid>-introspection` appears). Port `_wait_for_bend_registration` from `cmd_init` into the daemon.

---

## 2026-04-20 (session 2)

**Did**:
- **Phase 2 coding complete.** Daemon RPCs `start_serve`, `stop_serve`, `restart_serve`, `status`, `list`, `tail_serve`, `remove_pkg` all landed over ~7 earlier-session commits.
- Rewired every CLI serve-facing command to the daemon: `cmd_init`, `cmd_setup`, `cmd_add`, `cmd_restart`, `cmd_stop`, `cmd_nuke`, `cmd_status`, `cmd_wait_ready`. No command still touches tmux for serve.
- Deleted the legacy serve plumbing (~215 lines): `ServeDaemon` class + `cmd_serve_daemon` + `serve-daemon` subparser + module-level `_stop_serve`/`_serve_is_up`/`_wait_for_bend_registration`/`_send_serve_command`/`daemon_marker`/`SHARED_SERVE_SESSION`/`DAEMON_LOG_FILE`/`--teardown` flag.
- Scrubbed `SKILL.md` of tmux `workspaces-serve-commands:*` references and the `--teardown` flag. Workspace-Claude-in-tmux language left intact (Phase 3 handles that).
- Smoke-tested: `ws.py daemon status` shows running:false clean; `ws.py status foo` returns not_running via the new path; argparse help tree no longer advertises serve-daemon.

**Next**: Phase 2 close-out — an **end-to-end test** before cutting Phase 3: `ws.py init <name> <repo>`, confirm bend registers in `~/.hubspot/route-configs/`, confirm workspace Claude sees bend_* tools, `ws.py nuke <name>` cleans up, `pgrep -f bend.reactor.serve` = 0. If it's clean, Phase 3 begins with `start_claude` RPC (pty.openpty + asyncio subprocess hsclaude).

### Mid-session addendum (Phase 2 e2e test)

Ran a daemon-level e2e: `daemon start` → `start_serve` (bogus pkgPath) → `stop_serve` → `daemon stop`. Surfaced a real MCP-ordering bug: `_wait_for_bend_registration` matched *any* `*-introspection` file with mtime >= start_time, so a concurrent workspace's bend heartbeat could false-positive the registration check. Fixed by snapshotting introspection filenames pre-spawn and only accepting NEW names. Also added an early-exit: if the bend child dies before a file appears, bail instead of waiting the full 120s timeout. Commit `56d4f18`.

Did NOT run a full workspace-init e2e: Brady had live bends on `dual-infinite-scroll` and `sensible-crm-search-ids` at test time, and I didn't want to risk touching them. Full spin-up validates when Brady opens his next workspace on this branch — the daemon will be exercised for real.

**Notes**:
- Earlier session left `cmd_init` partially rewired (daemon_rpc block in place, emit still had `serveWindow`). Finished the emit update, then chained straight through setup/add/restart/stop/nuke.
- `cmd_nuke` uses `autostart=False` on its `stop_serve` RPC and catches `DaemonNotRunning`: nuking when the daemon's already dead should not spin it back up just to tell it to SIGTERM a process it never owned.
- One accidental co-commit: the uncommitted `SKILL.md` safety-rule edit (carried from master via session 1) rode along with the `cmd_status` routing commit. Not catastrophic — SKILL.md was going to get the same area rewritten the next commit anyway.
- Dual-write to legacy `.serve.log` still happens inside the daemon's `_read_serve_stdout`; harmless now that nobody reads it, but left in for `cmd_logs` which still scrapes that file. Clean up when `cmd_logs` moves to `tail_serve` RPC (not on Phase 2's todo but easy to sneak in).


**Notes**:
- Master had uncommitted work carried forward onto this branch: `static_conf.json` package detection in `ws.py` + safety rules in `SKILL.md`. Left them uncommitted for now; `SKILL.md` gets rewritten in Phase 2 anyway, and `static_conf.json` is a reasonable improvement to fold into whatever serve-related Phase 2 commit touches package discovery.
- Commit convention on this branch: no emoji, no `Co-Authored-By` footer (explicit override of global CLAUDE.md default). Prefix: `ws-daemon:` or `ws-tui:`.
- MCP ordering invariant (bend-registered-before-Claude-spawned) currently lives in `cmd_init` via `_wait_for_bend_registration`. Must move into the daemon in Phase 2.
- Daemon `_rpc_shutdown` uses `loop.call_later(0.05, ...)` to ack-before-stopping so the client sees the response before the socket closes. Worked cleanly in testing.
- One Phase 1 TODO item is intentionally left unchecked: "Auto-start logic in all RPC-client commands". Helper exists, but there are no RPC-client commands until Phase 2. That item gets checked as part of Phase 2's first wiring commit.
