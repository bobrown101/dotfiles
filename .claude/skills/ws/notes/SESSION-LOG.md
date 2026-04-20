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

**Next**: start Phase 1 — add `ws.py daemon run` subcommand (asyncio event loop, `~/.ws-daemon.sock`, `ping`/`shutdown` methods).

**Notes**:
- Master had uncommitted work carried forward onto this branch: `static_conf.json` package detection in `ws.py` + safety rules in `SKILL.md`. Left them uncommitted for now; they'll either land on master separately or get folded into a Phase-2 commit when `SKILL.md` is rewritten anyway.
- Commit convention on this branch: no emoji, no `Co-Authored-By` footer (explicit override of global CLAUDE.md default). Prefix: `ws-daemon:` or `ws-tui:`.
- MCP ordering invariant (bend-registered-before-Claude-spawned) currently lives in `cmd_init` via `_wait_for_bend_registration`. Must move into the daemon in Phase 2.
