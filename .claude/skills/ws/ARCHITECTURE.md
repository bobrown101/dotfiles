# Workspace architecture

This is the reference map for how `ws.py`, tmux, `bend reactor serve`, and the two Claude instances (creator + workspace) fit together. SKILL.md is the operating manual; this file is the map.

## Cast of characters

| Participant | Role |
|---|---|
| 👤 **User** | Asks for workspaces, works in them, tears them down. |
| 🤖 **Creator Claude** | The top-level Claude the user is chatting with. Plans the workspace, writes the handoff prompt, invokes `ws.py init`. Thin. |
| 🐍 **ws.py** | Single-file Python CLI at `scripts/ws.py`. All orchestration: validate, clone, yarn, discover, serve, stop, status, nuke. Emits JSON. |
| 📂 **Filesystem** | Four locations that act as shared state: `~/src/<repo>` (source clones), `~/src/workspaces/<name>/` (workspace dir + `.serve.log`), `~/src/workspaces/workspace-discovery-cache.json` (package/URL cache), `~/.hubspot/route-configs/<pid>-introspection` (bend's MCP handshake). No other metadata stores exist. |
| 🪟 **tmux** | One session per workspace: `<name>`, running the workspace Claude. `bend reactor serve` runs detached (not in tmux) as a supervised background process; tail its log with `ws.py logs <name>`. |
| 🏗️ **bend serve** | `bend reactor serve --enable-tools --ts-watch --run-tests`, spawned detached by `ws.py` via `start_new_session=True` + `close_fds=True`. Per-workspace state (pid, lstart, marker, pkgPaths) in `<ws_dir>/.ws-serve.json`; liveness check is `process_alive(pid) && ps_lstart(pid) == stored_lstart`. Writes `<ws_dir>/.serve.log` and `~/.hubspot/route-configs/<pid>-introspection`. |
| 🧰 **hsclaude** | `/Users/brbrown/.local/bin/hsclaude` → `dvx claude`. The wrapper that wires up HubSpot MCP servers. Launching bare `claude` skips this, so spawned Claudes must go through `hsclaude`. |
| 🤖 **Workspace Claude** | The nested Claude running inside the workspace tmux session. Confirms setup, runs `wait-ready` + log-check, reports, then does whatever the user asks. |
| 🔌 **devex-mcp-server** | Spawned as a subprocess of each Claude instance (via `hsclaude`). Scans `~/.hubspot/route-configs/` **at startup** to find running bend serves, then exposes their tools (`bend_compile`, `bend_package_ts_get_errors`, etc.) as deferred MCP tools. Only re-scans on Claude restart. |

## The ordering constraint that drives the whole design

The MCP server scans `route-configs/` **once, at startup**. So the sequence has to be:

1. `ws.py` starts `bend reactor serve`
2. Bend writes `<pid>-introspection` to `route-configs/`
3. *Then* `ws.py` launches the Workspace Claude
4. Workspace Claude spawns `devex-mcp-server` → it finds bend → tools register

If (3) happens before (2), the MCP server scans an empty directory, finds nothing, and the workspace Claude has no bend tools — with no way to trigger a rescan short of restarting. That's why `ws.py init` blocks on `_wait_for_bend_registration` between serve launch and Claude launch.

## Full sequence: create → work → tear down

![Full workspace lifecycle](diagrams/sequence-full.png)

Source: [`diagrams/sequence-full.mmd`](diagrams/sequence-full.mmd). To regenerate the PNG after edits, see [README.md → Regenerating the diagrams](README.md#regenerating-the-diagrams).

## Secondary flow: adding a repo to a live workspace

![Add a repo to an existing workspace](diagrams/sequence-add.png)

Source: [`diagrams/sequence-add.mmd`](diagrams/sequence-add.mmd).

## Why `ws.py init` blocks instead of delegating to the Workspace Claude

An earlier version of this design had `ws.py init` just create tmux and launch the workspace Claude; the workspace Claude then called `ws.py add` to clone, yarn, and start serve. That failed because:

1. Workspace Claude spawned before any clone/yarn/serve work.
2. Its `devex-mcp-server` scanned an empty `route-configs/`.
3. Seconds later, `add` started bend, but the MCP scan had already happened. No bend tools in the session.

Moving the setup into `init` (with `_wait_for_bend_registration` between serve start and Claude launch) makes the MCP scan deterministic. The trade-off is that the creator's bash call blocks for minutes — the user sees a single "this will take a few minutes, watch compile in the serve window" message and can just wait.

## Files to read when extending this system

- `scripts/ws.py` — everything. Subcommands are one function each, all at top level.
- `SKILL.md` — what the creator + workspace Claude should do (the "operating manual"). Section 3 gets pasted verbatim into the handoff prompt.
- `~/.local/bin/hsclaude` — two-line wrapper around `dvx claude`, which is the real MCP setup entry point. If MCP behavior changes, this is upstream.
- `~/src/workspaces/workspace-discovery-cache.json` — just a JSON dict of `repo → {remote, type, packages, urls}`; safe to delete if it gets stale.
