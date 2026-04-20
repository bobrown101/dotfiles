# Workspace architecture

This is the reference map for how `ws.py`, `ws-daemon`, `bend reactor serve`, and the two Claude instances (creator + workspace) fit together. SKILL.md is the operating manual; this file is the map.

## Cast of characters

| Participant | Role |
|---|---|
| 👤 **User** | Asks for workspaces, works in them, tears them down. |
| 🤖 **Creator Claude** | The top-level Claude the user is chatting with. Plans the workspace, writes the handoff prompt, invokes `ws.py init`. Thin. |
| 🐍 **ws.py** | Single-file Python CLI at `scripts/ws.py`. All orchestration: validate, clone, yarn, discover, serve, stop, status, nuke. Emits JSON. |
| 📂 **Filesystem** | Three kinds of shared state: `~/src/<repo>` (source clones), `~/src/workspaces/<name>/` (workspace dir + clones), `~/src/workspaces/workspace-discovery-cache.json` (package/URL cache). Bend itself also writes `~/.hubspot/route-configs/<pid>-introspection` for its MCP handshake — we read it but don't own it. Everything else lives in memory inside ws-daemon. |
| 🛰️ **ws-daemon** | Single long-lived asyncio process. Binds `~/.ws-daemon.sock` (mode 0600). Owns every `bend reactor serve` Popen and every workspace Claude PTY (pty.openpty + subprocess). Holds per-workspace ring buffers for serve stdout and claude PTY output. Every `ws.py` subcommand that touches live state is a thin RPC client to this daemon. Dies = everything dies (intentional). Auto-started on first client RPC. |
| 🏗️ **bend serve** | `bend reactor serve --enable-tools --ts-watch --run-tests`, spawned by ws-daemon as a subprocess. stdout streams into the daemon's in-memory ring buffer. Bend writes `~/.hubspot/route-configs/<pid>-introspection` on startup. |
| 🧰 **hsclaude** | `/Users/brbrown/.local/bin/hsclaude` → `dvx claude`. The wrapper that wires up HubSpot MCP servers. Spawned by ws-daemon under a PTY (master fd owned by the daemon, slave becomes claude's stdio and is closed in the daemon after exec). |
| 🤖 **Workspace Claude** | The nested Claude running under ws-daemon's PTY. Users attach via `ws.py attach-claude <name>`, which proxies bytes over the daemon socket (raw mode, Ctrl-\ detach). Multiple clients can attach read-only; last writable client owns input. |
| 🔌 **devex-mcp-server** | Spawned as a subprocess of each Claude instance (via `hsclaude`). Scans `~/.hubspot/route-configs/` **at startup** to find running bend serves, then exposes their tools (`bend_compile`, `bend_package_ts_get_errors`, etc.) as deferred MCP tools. Only re-scans on Claude restart. |

## The ordering constraint that drives the whole design

The MCP server scans `route-configs/` **once, at startup**. So the sequence has to be:

1. `ws.py init` (client) asks ws-daemon to `start_serve`
2. Daemon spawns `bend reactor serve` and bend writes `<pid>-introspection` to `route-configs/`
3. Daemon's `_wait_for_bend_registration` snapshots the dir pre-spawn and waits for a *new* file name to appear — then returns success to the client
4. `ws.py init` then calls `start_claude`, which makes the daemon spawn `hsclaude` under a PTY
5. Workspace Claude spawns `devex-mcp-server` → it finds bend → tools register

If (4) happens before (2)/(3), the MCP server scans an empty directory, finds nothing, and the workspace Claude has no bend tools — with no way to trigger a rescan short of restarting. The invariant lives inside the daemon now (in `_rpc_start_serve`), so any client that uses the RPC gets the ordering for free.

## Full sequence: create → work → tear down

![Full workspace lifecycle](diagrams/sequence-full.png)

Source: [`diagrams/sequence-full.mmd`](diagrams/sequence-full.mmd). To regenerate the PNG after edits, see [README.md → Regenerating the diagrams](README.md#regenerating-the-diagrams).

## Secondary flow: adding a repo to a live workspace

![Add a repo to an existing workspace](diagrams/sequence-add.png)

Source: [`diagrams/sequence-add.mmd`](diagrams/sequence-add.mmd).

## Why `ws.py init` blocks instead of delegating to the Workspace Claude

An earlier version of this design had `ws.py init` just launch the workspace Claude; the workspace Claude then called `ws.py add` to clone, yarn, and start serve. That failed because:

1. Workspace Claude spawned before any clone/yarn/serve work.
2. Its `devex-mcp-server` scanned an empty `route-configs/`.
3. Seconds later, `add` started bend, but the MCP scan had already happened. No bend tools in the session.

Moving the setup into `init` (with daemon-side `_wait_for_bend_registration` between serve start and Claude launch) makes the MCP scan deterministic. The trade-off is that the creator's CLI call blocks for minutes — the user sees a single "this will take a few minutes; you can tail bend with `ws.py logs`" message and can just wait.

## Files to read when extending this system

- `scripts/ws.py` — everything. Subcommands are one function each, all at top level.
- `SKILL.md` — what the creator + workspace Claude should do (the "operating manual"). Section 3 gets pasted verbatim into the handoff prompt.
- `~/.local/bin/hsclaude` — two-line wrapper around `dvx claude`, which is the real MCP setup entry point. If MCP behavior changes, this is upstream.
- `~/src/workspaces/workspace-discovery-cache.json` — just a JSON dict of `repo → {remote, type, packages, urls}`; safe to delete if it gets stale.
