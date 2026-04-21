---
name: ws
description: Manage parallel multi-repo development workspaces using git worktrees, tmux, and bend serve. Use when the user wants to create, update, tear down, or inspect workspaces, or mentions workspaces, worktrees, or parallel dev environments.
argument-hint: "up <name> <repo[:branch]...>"
---

# Workspace Manager

Manage isolated multi-repo development workspaces. Each workspace gets its own git clones and its own `bend serve` instance (with a unique subdomain). A single long-lived `ws-daemon` owns every serve; the workspace Claude still runs in its own tmux session (for now — Phase 3 moves Claude under the daemon too).

See `ARCHITECTURE.md` in this dir for the full component map and a sequence diagram of the create → work → teardown flow. This file is the operating manual; that one is the map.

All non-trivial logic lives in a single Python CLI:

```
{{SKILL_PATH}}/scripts/ws.py
```

Invoke every subcommand via `uv run {{SKILL_PATH}}/scripts/ws.py <command>`. Every command emits JSON to stdout and logs human-readable progress to stderr. Parse the JSON; don't scrape the stderr.

Two Claude instances are involved:
- **Creator**: the Claude instance where the user asks for a workspace. Reads this file, runs `ws.py plan`, shows the plan, writes the handoff prompt, runs `ws.py init`. Done.
- **Workspace Claude**: runs inside the workspace tmux session. Reads the handoff prompt (Section 3 below). Runs `ws.py setup`, reports to the user.

---

# Section 1: Shared rules (creator + workspace Claude)

## Critical safety rules

- **NEVER use `pkill -f` with the workspace name or workspace path.** This WILL match and kill the Claude process itself. Use `ws.py stop` instead — it asks the ws-daemon to signal bend over RPC.
- **NEVER delete git branches** unless the user explicitly asks. Only `ws.py nuke --delete-branches` does this, and the creator should confirm with the user first.
- **NEVER do setup work from the creator.** After `ws.py init` launches the workspace Claude, the creator is done.
- **NEVER hand-manage the bend serve process.** Do not `kill` the serve PID, do not spawn `bend reactor serve …` yourself, do not reconstruct a `bend reactor serve` command from `ps` output. Every serve lifecycle operation — start, stop, restart, adding a package — goes through `ws.py` (which talks to the ws-daemon). Hand-rolled restarts drop registration in `~/.hubspot/route-configs/` (so `serveUp` flips false in status), and reconstructed commands silently miss the `--env bend-instance=<name>` / `--env local-static-domain=<name>.local.hsappstatic.net` flags — the instance URL then stops resolving or, worse, serves a different workspace's packages. If you think you need to touch serve directly, you don't; use `ws.py restart <name>` (or `stop` / `add`) instead.

## Conventions

- **Workspace root**: `~/src/workspaces/<name>/`
- **Name normalization**: spaces become hyphens. `ws.py` does this for you; callers don't need to pre-normalize.
- **Source repos** (for remote resolution): `~/src/<repo>/`
- **Branch default**: `brbrown/<workspace-name>` (override per-repo with `repo:branch` syntax)
- **Portal ID**: `103830646`
- **Shell in tmux windows**: fish. `ws.py` handles quoting — don't construct shell pipelines by hand.
- **Discovery cache**: `~/src/workspaces/workspace-discovery-cache.json` — `ws.py` reads and writes this automatically.
- **Parent/child workspaces**: when spawned from inside another workspace, the tmux session is named `<parent>/<child>` so it groups in tmux's session picker. `ws.py init --parent <name>` handles it.
- **No metadata files** — the filesystem IS the state.

---

# Section 2: Creator instructions

The creator reads this section to handle user requests. The workspace Claude never sees it.

## Routing

When the user invokes this skill (via `/ws` or natural language), route based on intent:
- "spin up / create / up a workspace" → `Creating a workspace` below
- "add a repo / more repos" → `Adding repos` below
- "tear down / nuke / destroy" → `ws.py nuke <name>`

If repos are given in natural language (e.g. "Customer Data Table"), match against directory names under `~/src/` (e.g. `customer-data-table`). Confirm ambiguous matches.

## Creating a workspace

`/ws up <name> <repo[:branch]>...`

1. **Run `ws.py plan`**:
   ```
   uv run {{SKILL_PATH}}/scripts/ws.py plan <name> <repo1> <repo2:branch>...
   ```
   The JSON output tells you: normalized workspace name, detected parent (if cwd is under another workspace), resolved remotes, branches, and any unresolved repos. If `ok: false`, show the `missingRepos` and stop — don't proceed.

2. **Briefly state what you're doing** (one line — workspace name + repos). Don't wait for approval; proceed straight to step 3. Tell the user up front that init will take a few minutes; they can tail bend output with `ws.py logs <name> --tail 200` while they wait.

3. **Write the handoff prompt** to `/tmp/ws-<name>-init-prompt.txt` using the Write tool. Template in "Building the handoff prompt" below.

4. **Run `ws.py init` with the repo list** — this blocks for ~2–4 min doing the full setup (clone, yarn, serve) BEFORE launching the workspace Claude, so its MCP server finds bend registered in `~/.hubspot/route-configs/` at startup:
   ```
   uv run {{SKILL_PATH}}/scripts/ws.py init <name> [--parent <parent>] \
     --repos <repo1>:<branch1> <repo2>:<branch2> ...
   ```

5. **Tell the user** the tmux session name to switch to (from the `tmuxSession` field of init's JSON output). Done.

## Adding repos to an existing workspace

`/ws up <name> <new-repo>...` when the workspace already exists (plan output has `existing: true`):

Tell the user to switch to the workspace tmux session and ask the workspace Claude to run `ws.py add <name> <new-repo>...`. The creator does NOT do this work.

## Building the handoff prompt

Write the handoff prompt to `/tmp/ws-<name>-init-prompt.txt` using the Write tool. Template:

```
You are starting in the <WORKSPACE_NAME> workspace.

<if parent: PARENT: <PARENT_WORKSPACE_NAME>>

REPOS (already cloned + serve already running):
  - <repo1>:<branch1>
  - <repo2>:<branch2>

<optional: TASK CONTEXT: <user's intent, if they provided one>>

<paste Section 3 below verbatim here>
```

The `REPOS:` block is informational only — `ws.py init` has already cloned them and started serve. Workspace Claude just confirms status and reports.

---

# Section 3: Workspace Claude instructions

Everything below this line is included verbatim in the handoff prompt. The workspace Claude only sees this section (plus the header with repo details).

## Critical safety rules

- **NEVER use `pkill -f` with the workspace name or workspace path.** Use `ws.py stop` — it asks the ws-daemon to signal bend over RPC.
- **NEVER delete git branches** unless the user explicitly asks.
- **NEVER hand-manage the bend serve process.** Do not `kill` the serve PID, do not spawn `bend reactor serve …` yourself, do not reconstruct a `bend reactor serve` command from `ps` output. Serve lifecycle — start, stop, restart, add-a-package — is always `ws.py restart|stop|add`. Hand-rolled restarts drop registration in `~/.hubspot/route-configs/` (`serveUp` flips false) and reconstructed commands silently miss the `--env bend-instance=<name>` / `--env local-static-domain=<name>.local.hsappstatic.net` flags — the instance URL then stops resolving. If serve looks stuck, `ws.py status <name>` first, then `ws.py restart <name>`.

## Commands

All operations go through `ws.py`. Every command emits JSON on stdout; read stderr only for progress.

Alias `WS=uv run ~/src/dotfiles/.claude/skills/ws/scripts/ws.py` mentally — commands below elide it.

| Command | Purpose |
|---|---|
| `add <name> <repo:branch>...` | Clone + yarn + discover + start serve. Idempotent (skips cloned repos) |
| `status <name>` | `{state, serveUp, packages, errors, urls, ...}` snapshot |
| `wait-ready <name> --timeout 600` | Blocks until `state: ready` (or timeout) |
| `urls <name>` | Resolved app + test URLs. Use `url` field verbatim |
| `logs <name> --tail N [--grep P]` | Serve log tail. Sets `tailOnly`/`truncated` flags |
| `stop <name>` | Asks ws-daemon to SIGTERM bend; escalates to SIGKILL after 15s |
| `restart <name>` | `stop` + re-launch |
| `nuke <name> [--delete-branches]` | Full teardown. Confirm with user before `--delete-branches` |

## First action after handoff

Clone + yarn + serve were already done by `ws.py init` before you spawned. Your job is just to confirm things are healthy and report.

```
ws.py wait-ready <WORKSPACE_NAME> --timeout 600
ws.py logs <WORKSPACE_NAME> --tail 200 --grep "ERROR|FATAL|EADDRINUSE|Cannot find module"
ws.py urls <WORKSPACE_NAME>
```

If the log-check returns hits, surface them with the "Setup failed" template. Otherwise use "Workspace ready" with the URL data. Always run the log check — don't skip it.

If the user later asks to add another repo, use `ws.py add <name> <repo>:<branch>` (idempotent; stops and restarts serve with the combined package list). If you're resuming a workspace whose repos are already cloned but serve is down, use `ws.py setup <name>`.

`setup`'s JSON output includes `skippedRepos: [{repo, reason}...]`. If it's non-empty, list the entries and ask the user to confirm before continuing — `setup` skips repos it can't resolve a remote for rather than hard-failing, so a surprise skip can mean a missing `~/src/<repo>` clone.

## Validating code with bend MCP tools

Serve is launched with `--enable-tools --ts-watch --run-tests`, so bend MCP tools are usable for compile, TS diagnostics, and tests.

Bend tools are **deferred** — they exist but schemas aren't loaded until you fetch them via `ToolSearch` with query `bend`. If the tool isn't in your immediate list, search first; don't conclude it's missing. Never fall back to shell `tsc`/`jasmine`.

If `ToolSearch` returns no matches, it's an environment issue. Check `ws.py status` is `ready`, `ps -ef | grep bend.*reactor.*serve` shows `--enable-tools`, and `~/.hubspot/route-configs/` has an entry for the serve PID — then surface the env problem to the user.

Tests take 2–5 min, TS checks up to 120s. Wait — don't restart serve because tests are slow.

## Background monitor

When the user asks for monitoring, launch a background agent with:

> Monitor workspace `<NAME>`. Every 60s run `ws.py status <NAME>`.
> - `state: error` + `EADDRINUSE`: `ws.py restart <NAME>`; cap at 3 restarts, then escalate.
> - `state: error` (other): stop monitoring; post the unhealthy template with error details.
> - `state: stale`: `ws.py stop <NAME>` and alert; don't auto-restart.
> - New fatal errors mid-run: `ws.py logs <NAME> --tail 200 --grep ERROR` and surface.
> - Exit when the user says so or after 5 consecutive `ready` checks post-restart.

## Report templates

**Workspace ready** (only after `wait-ready: ready` AND the log-grep check was clean):
```markdown
## Workspace ready — `<name>`
**Repos**: `<repo>` → `<branch>` (CLAUDE.md: ✅/❌)
**Compiled packages**: `<pkg>`, `<pkg>`
**App URLs** (from `ws.py urls`, only `ready: true` with non-null `url`):
- `<pkg>`: `<url>`
**Test URLs**: - `<pkg>`: `<test-url>`
**Log check**: clean.
**Serve**: owned by ws-daemon (tail with `ws.py logs <name>`).
```

**Setup failed**:
```markdown
## Workspace setup failed — `<name>`
**Stopped at**: clone | checkout | yarn | serve
**First error**: <error excerpt>
**Next step**: <specific action> | Rerun: `ws.py add <name> ...`
```

**Unhealthy** (from background monitor):
```markdown
## Workspace unhealthy — `<name>`
**State**: error|stale · **Serve up**: true|false
**Errors**: `<type>`: `<line>`
**Actions taken**: <restart attempts>
**Recommendation**: investigate | `ws.py restart` | `ws.py nuke`
```

## CONTEXT.md on exit

At milestones or exit, update `~/src/workspaces/<WORKSPACE_NAME>/CONTEXT.md` with sections: **Goal**, **Status**, **Next steps**, **Branches**, **Notes**. Keep it to non-obvious state — not anything derivable from code or git log.
