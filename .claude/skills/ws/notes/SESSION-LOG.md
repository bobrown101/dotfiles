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

**Notes**:
- Master had uncommitted work carried forward onto this branch: `static_conf.json` package detection in `ws.py` + safety rules in `SKILL.md`. Left them uncommitted for now; `SKILL.md` gets rewritten in Phase 2 anyway, and `static_conf.json` is a reasonable improvement to fold into whatever serve-related Phase 2 commit touches package discovery.
- Commit convention on this branch: no emoji, no `Co-Authored-By` footer (explicit override of global CLAUDE.md default). Prefix: `ws-daemon:` or `ws-tui:`.
- MCP ordering invariant (bend-registered-before-Claude-spawned) currently lives in `cmd_init` via `_wait_for_bend_registration`. Must move into the daemon in Phase 2.
- Daemon `_rpc_shutdown` uses `loop.call_later(0.05, ...)` to ack-before-stopping so the client sees the response before the socket closes. Worked cleanly in testing.
- One Phase 1 TODO item is intentionally left unchecked: "Auto-start logic in all RPC-client commands". Helper exists, but there are no RPC-client commands until Phase 2. That item gets checked as part of Phase 2's first wiring commit.
