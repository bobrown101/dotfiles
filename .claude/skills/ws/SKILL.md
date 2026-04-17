---
name: ws
description: Manage parallel multi-repo development workspaces using git worktrees, tmux, and bend serve. Use when the user wants to create, update, tear down, or inspect workspaces, or mentions workspaces, worktrees, or parallel dev environments.
argument-hint: "up <name> <repo[:branch]...>"
---

# Workspace Manager

Manage isolated multi-repo development workspaces. Each workspace gets its own git clones, bend serve instance (with a unique subdomain), and tmux session.

Two Claude instances are involved:
- **Creator**: the Claude instance where the user asks for a workspace. Reads this entire file. Does minimal work: validates inputs, writes the handoff prompt, launches tmux via `ws-init`.
- **Workspace Claude**: the Claude instance that runs inside the workspace tmux session. Only sees the handoff prompt (Section 3 below). Does all the real work: cloning, installing, discovery, serve, and user interaction.

---

# Section 1: Shared rules (creator + workspace Claude)

These rules apply to BOTH the creator and the workspace Claude. The creator reads them here; the workspace Claude receives them in the handoff prompt.

## Critical safety rules

- **NEVER use `pkill -f` with the workspace name or workspace path.** This WILL match and kill the Claude process itself (its args contain the workspace name). To kill serve processes, use the "Stopping serve" procedure which targets `bend-instance=<name>` specifically.
- **NEVER delete branches without explicit user confirmation.** Only the `nuke` operation deletes branches, and it must confirm first.
- **NEVER do setup work from the creator.** After launching ws-init, the creator is done. All cloning, installing, and serve is the workspace Claude's job.

## Conventions

- **Workspace root**: `~/src/workspaces/<name>/`
- **Name normalization**: replace spaces with hyphens everywhere (directory paths, tmux session, prompt file, serve subdomain, branch names). E.g. `"search endpoint migration"` -> `"search-endpoint-migration"`.
- **Source repos**: `~/src/<repo>/` (must exist before cloning)
- **Clones**: `~/src/workspaces/<name>/<repo>/`
- **Branch default**: `brbrown/<workspace-name>` (override per-repo with `repo:branch` syntax)
- **Serve URL**: `https://<name>.local.<lbPrefix>.<domain><historyBasename>` (resolved from deploy config + quartz config; see "URL resolution")
- **Test URL**: `https://<name>.local.hsappstatic.net/<package>/static/test/test.html?spec=`
- **Portal ID**: `103830646`
- **Shell**: fish. Use `env VAR=value command` syntax, not `VAR=value command`.
- **No metadata files** -- the filesystem IS the state.
- **Parent/child workspaces**: When a workspace is created from inside another workspace, its tmux session is named `<parent>/<child>` (e.g., `streaming-object-updates/gantt-streaming`). This makes child workspaces visually group under their parent in tmux's session picker (`prefix + s`). The workspace directory remains flat at `~/src/workspaces/<child>/`.
- **Git**: Use `git -C <path>` instead of `cd <path> && git ...` to avoid compound-command permission prompts.
- **Bash round trips**: Chain independent commands with `&&` into a single Bash call where possible. Each separate invocation requires a permission check.
- **Serve session**: `workspaces-serve-commands` (shared tmux session, one window per workspace's serve command)

## Discovery cache

File: `~/src/workspaces/workspace-discovery-cache.json`

Shared across all workspaces. Maps repo names to discovery results:

```json
{
  "crm-object-table": {
    "cachedAt": "2026-04-01T15:30:00Z",
    "remote": "git@github.com:HubSpotEngineering/crm-object-table.git",
    "type": "library",
    "packages": [
      {"name": "crm-object-table", "isDefault": true},
      {"name": "crm-object-table-kitchen-sink", "isDefault": true},
      {"name": "crm-object-table-storybook", "isDefault": false},
      {"name": "crm-object-table-acceptance-tests", "isDefault": false}
    ],
    "urls": {
      "crm-object-table-kitchen-sink": {"lb": "app", "basename": "/crm-object-table-kitchen-sink/:portalId/"}
    }
  }
}
```

**Creator uses it** to skip `git remote get-url` calls (checks `remote` field).
**Workspace Claude uses it** to skip package discovery (checks `type` and `packages` fields). If a repo is not cached or only has `remote`, run full discovery and **merge** results back (don't overwrite the file).

The `isDefault` field records per-repo defaults before cross-repo heuristics. To invalidate, delete the repo's key from the JSON.

---

# Section 2: Creator instructions

The creator reads this section to handle user requests. The workspace Claude never sees this section.

## Routing

When the user invokes this skill (via `/ws` or natural language like "spin up a workspace"), create or update a workspace as described below.

If the user provides repo names in natural language (e.g., "Customer Data Table"), match them against directory names in `~/src/` (e.g., `customer-data-table`). Confirm the match with the user if ambiguous.

## Creating or updating a workspace

`/ws up <name> <repo[:branch]...>`

Idempotent. Works for both new and existing workspaces.

**Detecting parent workspace (for sub-workspaces):**

Before creating a workspace, check if the creator is running inside an existing workspace:
1. Check if the current working directory starts with `~/src/workspaces/`. If so, extract the workspace name from the path (the directory immediately under `workspaces/`).
2. Alternatively, check if the current tmux session name matches a workspace directory in `~/src/workspaces/`.
3. If a parent is detected, the new workspace is a **child workspace**. Pass `--parent <parent-name>` to `ws-init` (step 4 below). The tmux session will be named `<parent>/<child>`, making it group under the parent in the session picker.
4. Include the parent in the confirmation plan so the user sees the relationship.

**Creating a new workspace:**

1. **Validate repos and resolve remote URLs.** Check the discovery cache for `remote` URLs first. For uncached repos, resolve via `git -C ~/src/<repo> remote get-url origin`. Stop and report if any repo fails validation.

2. **Present a confirmation plan and wait for approval:**
   ```
   Here's the plan:

   Workspace: css-hover-cell-cleanup
   Parent: streaming-object-updates  (or omit if no parent)
   Repos & branches:
     customer-data-table -> brbrown/css-hover-cell-cleanup
   Serve URL: resolved after setup (depends on repo's deploy config)
   tmux session: streaming-object-updates/css-hover-cell-cleanup  (or just the name if no parent)

   OK to proceed, or any changes?
   ```

3. **Write the handoff prompt to `/tmp/ws-<name>-init-prompt.txt`** using the Write tool. The prompt is built by filling in Section 3's template variables (see "Building the handoff prompt" below). No escaping needed -- the Write tool handles it.

4. **Run `~/.local/bin/ws-init <name> [--parent <parent-name>]`**. This script creates the workspace directory, writes `.claude/settings.json`, creates the tmux session (named `<parent>/<name>` if parent is provided, otherwise `<name>`), and launches the workspace Claude from the prompt file.

5. **Tell the user** the workspace is being set up and to switch to the tmux session (use the full session name including parent prefix if applicable). Done -- no further work.

**Updating an existing workspace (new repos specified):**

1. Check which repos already exist in `~/src/workspaces/<name>/`
2. For new repos: tell the user to switch to the workspace tmux session and ask the workspace Claude to clone and serve the new repos. The creator does NOT do this work itself.
3. For existing repos where the specified branch differs from current: ask the user to confirm the branch switch
4. If tmux session doesn't exist, create it with ws-init

**Updating with no repos specified (`/ws up <name>`):**

Ensure the tmux session exists (create if needed) and tell the user to attach.

## tmux layout

Two tmux sessions are involved:

1. **`<name>`** or **`<parent>/<name>`** (tmux session) — Claude Code instance. Working directory: `~/src/workspaces/<name>/`. If the workspace was created from inside another workspace, the session is named `<parent>/<name>` so it groups under the parent in the tmux session picker.
2. **`workspaces-serve-commands:<name>`** (tmux window in shared session) — bend reactor serve for this workspace

Creation is handled by `~/.local/bin/ws-init <name> [--parent <parent>]`. The script creates both the workspace tmux session and the serve window in the shared `workspaces-serve-commands` session.

## Building the handoff prompt

Write the handoff prompt to `/tmp/ws-<name>-init-prompt.txt` using the Write tool.

The prompt has two parts:
1. **Header**: workspace-specific variables (name, repo list with remotes and branches)
2. **Body**: the full text of Section 3 below, included verbatim

Template:

```
You are setting up the <WORKSPACE_NAME> workspace.

<if parent workspace exists: PARENT: <PARENT_WORKSPACE_NAME>>

REPOS:
<for each repo>
  - repo: <REPO_NAME>, remote: <REMOTE_URL>, branch: <BRANCH_NAME>
</for each repo>

<optional: TASK CONTEXT: <user's intent or task description>>

<paste Section 3 verbatim here>
```

Include the user's task context if they provided one (e.g., "The user wants to investigate virtualization DOM mutation performance"). This helps the workspace Claude understand what to focus on. Include the PARENT line if the workspace was created from inside another workspace — this gives the workspace Claude context about lineage (useful for CONTEXT.md).

---

# Section 3: Workspace Claude instructions

Everything below this line is included verbatim in the handoff prompt. The workspace Claude only sees this section (plus the header with repo details). This is the single source of truth for workspace setup behavior.

## Critical safety rules

- **NEVER use `pkill -f` with the workspace name or workspace path.** This WILL match and kill you (your args contain the workspace name). To kill serve processes, target `bend-instance=<WORKSPACE_NAME>` specifically (see "Stopping serve").
- **NEVER delete git branches** unless the user explicitly asks for it.

## Conventions

- **Git**: Always use `git -C <path>` instead of `cd <path> && git ...`. Compound commands with `cd && git` trigger a security approval prompt that blocks automation.
- **Shell**: fish. Use `env VAR=value command` syntax, not `VAR=value command`.
- **Bash round trips**: Chain independent commands with `&&` into a single Bash call where possible — but never `cd && git` (use `git -C` instead).

## One-pager / docs lookup rules

- **During workspace setup** (cloning, installing, discovering packages, starting serve): do NOT call `get_onepager` or `search_docs`. Setup is infrastructure work, not code editing.
- **During task investigation** after setup: only fetch one-pagers that are directly relevant to the task context (e.g. `data-fetching-client` if investigating DFC patterns). Do NOT fetch one-pagers triggered by incidental keyword matches (e.g. "acceptance-tests" appearing in a directory exclusion list).

## Setup steps

1. **Clone each repo** into `~/src/workspaces/<WORKSPACE_NAME>/<REPO_NAME>/` from its remote URL
2. **Checkout the workspace branch**: `git -C <CLONE_PATH> checkout -b <BRANCH_NAME> origin/master` — don't check if the remote branch exists first, just run this directly. If it fails because the branch already exists, fall back to `git -C <CLONE_PATH> checkout <BRANCH_NAME>`. Always use `git -C`, never `cd && git`. Run all repo checkouts in a single Bash call chained with `&&`.
3. **Check for repo-level CLAUDE.md**: After checkout, check if each cloned repo has a `CLAUDE.md` at its root. In the final report (step 6), note which repos have CLAUDE.md and which don't — this helps the user know where AI context is available.
4. **Run `bend yarn`** in each clone in **parallel** (separate Bash tool calls in a single message). These are independent and safe to parallelize.
5. **Discover packages and start serve** (see below)
6. **Report workspace details** to the user (see "What to report" below)

## Package discovery

Check `~/src/workspaces/workspace-discovery-cache.json` for cached results first. If a repo has `type` and `packages` in the cache, use those directly and skip discovery.

**For uncached repos:**

1. List subdirectories with `package.json` (exclude `node_modules`, `target`, `schemas`, `hubspot.deploy`, `docs`, `acceptance-tests`):
   ```bash
   ls -d ~/src/workspaces/<WORKSPACE_NAME>/<REPO_NAME>/*/ | grep -v node_modules | grep -v target | grep -v schemas | grep -v hubspot.deploy | grep -v docs | grep -v acceptance-tests
   ```
   If no subdirectories have `package.json`, the repo is single-package -- serve the repo root.

2. Classify the repo by checking `<clone>/hubspot.deploy/`:
   - `<repo>.yaml` exists -> **app** (deployable)
   - Only `*-kitchen-sink.yaml` / `*-storybook.yaml` / `*-acceptance-tests.yaml` -> **library**

3. **Resolve URLs for each package** (see "URL resolution" below). This reads deploy YAML and quartz config to determine the actual load balancer and route path for each app package.

4. Write results back to `~/src/workspaces/workspace-discovery-cache.json`. Read the file first, merge your new entry (don't overwrite other repos), then write it back. Include all fields:
   ```json
   {
     "<REPO_NAME>": {
       "cachedAt": "<current ISO 8601 timestamp>",
       "remote": "<the git remote URL from the REPOS header>",
       "type": "library or app",
       "packages": [
         {"name": "<pkg>", "isDefault": true/false},
         ...
       ],
       "urls": {
         "<pkg>": {"lb": "<lb-name>", "basename": "<historyBasename>"},
         ...
       }
     }
   }
   ```

## URL resolution

For each package discovered, resolve its URL components from config files. This uses the same data sources as the deploy pipeline, so URLs stay correct when repos change their routing or load balancer.

**Step 1: Read the deploy config.** Find the YAML file in `<clone>/hubspot.deploy/` whose `artifactBuildMetadata.module` matches the package name. Extract `loadBalancers[0]` (defaults to `"app"` if missing).

**Step 2: Map the load balancer to a domain.** Use this mapping:
- `"app"` → `app.hubspotqa.com`
- `"privatehubteam"` → `private.hubteamqa.com`
- `"tools"` → `tools.hubteamqa.com`
- anything else → `<name>.hubteamqa.com`

**Step 3: Read the quartz config.** The file is at `<clone>/<package-path>/static/__generated__/quartz/quartz.config.json`. This is generated by `bend yarn`. Read `config.type` and `config.historyBasename`.
- If `config.type` is not `"application"`, the package has no browseable URL (it's a library).
- If `historyBasename` is an array, use the first element.
- If `historyBasename` contains `:portalId`, substitute with `103830646`.

**Step 4: Construct the URL.**
```
https://<WORKSPACE_NAME>.local.<lbPrefix>.<domain><historyBasename>
```

Example: for a package with `loadBalancers: ["app"]` and `historyBasename: "/contacts/:portalId"`:
```
https://my-workspace.local.app.hubspotqa.com/contacts/103830646
```

**If quartz.config.json doesn't exist yet** (serve hasn't compiled), store `{"lb": "<lb-name>", "basename": null}` in the cache and note in the report that the URL will be available after serve finishes compiling.

**Cache the results** in the `urls` field of the discovery cache so future workspaces for the same repo skip this work.

## Package selection

**Defaults:**
- **Always pre-select** the main package (shares the repo's name)
- **For libraries**, also pre-select `*-kitchen-sink` (it's the browser testing surface)
- **Never pre-select** `*-storybook` or `*-acceptance-tests`
- **Other utility packages**: don't pre-select, user can opt in

**Auto-accept:** Always auto-accept the defaults and proceed without prompting. Just briefly list which packages will be served (one line) and move on. Never ask the user to confirm package selection — they can always adjust later if needed.

## Starting serve

1. Run `bend yarn` in each clone directory in **parallel** (separate Bash tool calls in a single message)

2. Check for stale processes before starting:
   ```bash
   pgrep -f "bend-instance=<WORKSPACE_NAME>" 2>/dev/null && echo "STALE PROCESSES FOUND" || echo "clean"
   ```
   If stale, clean up (see "Stopping serve" below).

3. **Send the serve command to the tmux window** in the shared `workspaces-serve-commands` session:
   ```bash
   tmux send-keys -t "workspaces-serve-commands:<WORKSPACE_NAME>" "env BEND_WORKTREE=<WORKSPACE_NAME> NODE_ARGS=--max_old_space_size=16384 bend reactor serve <PKG_PATH_1> <PKG_PATH_2> ... --update --ts-watch --enable-tools --run-tests" Enter
   ```
   Each `<PKG_PATH>` is a full path like `~/src/workspaces/<WORKSPACE_NAME>/<REPO_NAME>/<PACKAGE>/`.

   The serve process runs in the tmux window, NOT as a background task of Claude. This means serve survives Claude restarts, and the user can see live output by switching to the `workspaces-serve-commands` tmux session.

4. Tell the user serve is compiling and give them the URLs (see "What to report"). Also tell them they can watch live output in `workspaces-serve-commands:<WORKSPACE_NAME>`.

5. **Proceed immediately** with the user's task or wait for instructions. Do NOT launch a background agent to monitor serve.

## Stopping serve

1. **Send Ctrl+C** to the serve tmux window and check if processes stopped:
   ```bash
   tmux send-keys -t "workspaces-serve-commands:<WORKSPACE_NAME>" C-c
   ```
2. **Wait 15 seconds**, then check:
   ```bash
   pgrep -f "bend-instance=<WORKSPACE_NAME>" 2>/dev/null && echo "STILL RUNNING" || echo "clean"
   ```
3. **If still running, repeat steps 1-2 up to 5 times** (send Ctrl+C again, wait 15 seconds, check). Sometimes the first Ctrl+C doesn't propagate to all child processes.
4. If still running after all retries, **force kill**:
   ```bash
   pkill -9 -f "bend-instance=<WORKSPACE_NAME>" 2>/dev/null
   ```
4. When **tearing down a workspace entirely**, also kill the tmux window:
   ```bash
   tmux kill-window -t "workspaces-serve-commands:<WORKSPACE_NAME>" 2>/dev/null
   ```

The `bend-instance=<WORKSPACE_NAME>` pattern is safe to `pkill` — it matches only bend child processes (tsc, rspack, Chrome, etc.), NOT Claude or shell processes.

## Restarting serve

1. Stop serve (see above)
2. Send the serve command to the tmux window again (see "Starting serve" step 3)

## Worktree URLs

The workspace name is a **subdomain prefix** on ALL local dev URLs. Routing is subdomain-based, NOT query-param-based.

**URL structure**: `https://<WORKSPACE_NAME>.local.<lbPrefix>.<domain><historyBasename>`

The `lbPrefix`, `domain`, and `historyBasename` come from URL resolution during package discovery (see "URL resolution" above). Use the resolved URLs from the discovery cache — do NOT hard-code paths.

- **Tests** (stable pattern): `https://<WORKSPACE_NAME>.local.hsappstatic.net/<PACKAGE_NAME>/static/test/test.html`

**WRONG** (do NOT use these formats):
- `https://local.hubspotqa.com/contacts?__worktree=<name>` — query params do not route to worktrees
- `https://local.hubspotqa.com/contacts` — missing workspace subdomain prefix

When a user asks for a URL, construct it from the cached `lb` + `basename` fields, not from assumptions about the path.

Portal ID: `103830646`

## Debugging serve and process issues

Serve output is in tmux session `workspaces-serve-commands`, window `<WORKSPACE_NAME>`. Capture recent output: `tmux capture-pane -t "workspaces-serve-commands:<WORKSPACE_NAME>" -p -S -50`

**Common issues:**
- **Stale processes**: always run the `pgrep -f "bend-instance=<WORKSPACE_NAME>"` check before starting serve. If stale, run "Stopping serve".
- **EADDRINUSE**: previous serve still running. Stop it, then restart.
- **Serve exits immediately**: missing `bend yarn`, wrong package paths, or node OOM (the `--max_old_space_size=16384` flag should prevent OOM).
- **Pages don't load**: verify worktree subdomain uses `<WORKSPACE_NAME>.local.<lbPrefix>.<domain>` (not `local.<domain>`), check `BEND_WORKTREE` was set, confirm `bend-instance=<WORKSPACE_NAME>` in process args.

## Validating code with mcp-bend tools

The mcp-bend tools talk directly to running Bend serve instances (discovered via `~/.hubspot/route-configs`). Use them instead of shell commands for compilation checks, type checking, and test runs.

### Checking compilation errors

Use `mcp__mcp-bend__compile` to get compilation errors across all running packages:

```
mcp__mcp-bend__compile()                    # all packages
mcp__mcp-bend__compile(packageName="my-pkg") # filter to one package
```

Returns formatted errors with file paths, line/column positions, and descriptions. Run this after code changes to catch build errors early.

### Type checking

Use `mcp__mcp-bend__package-ts-get-errors` to get TypeScript diagnostics:

```
mcp__mcp-bend__package-ts-get-errors(packageName="my-pkg")
```

Returns TypeScript errors with absolute paths and 1-indexed line/column positions. Times out after 120s if the TS watch isn't responding.

### Running tests

Use `mcp__mcp-bend__package-get-tests-results` to run Jasmine tests through the Bend host — no browser automation needed:

```
# Run all tests for a package
mcp__mcp-bend__package-get-tests-results(packageName="my-pkg")

# Run tests matching a spec filter
mcp__mcp-bend__package-get-tests-results(packageName="my-pkg", focusTests={"specNameQuery": "MyComponent"})
```

Returns formatted test results focusing on failed specs. Filtering is automatically cleared after each run.

### Discovering packages

Use `mcp__mcp-bend__list-packages` to see which packages the running Bend instance knows about. Useful to confirm serve is up and to get the correct package names for other tools.

### When to validate

- **After making code changes**: run compile + tests for affected packages
- **Before reporting work as done**: run the full test suite and type check for affected packages
- **On user request**: run whatever scope they ask for

### Patience with test runs

mcp-bend tools are synchronous. Full test suites take 2-5 minutes; TS checks up to 120s. Wait for them to return — silence is not a hang. Never restart serve because tests seem slow (recompilation is far more expensive). If a tool times out, investigate (serve still compiling? wrong package name?) rather than retrying blindly.

### Troubleshooting

If tools return no packages or error, serve may still be compiling. Use `mcp__mcp-bend__list-packages` to verify registration.

## What to report when done

After setup completes, tell the user:
- Workspace name
- Branch for each repo
- **CLAUDE.md status**: which repos have a `CLAUDE.md` (AI context available) and which don't
- **Resolved app URLs** from URL discovery (constructed from cached `lb` + `basename`). If quartz config wasn't available yet, note that the URL will be ready after serve compiles.
- Test URL for each package: `https://<WORKSPACE_NAME>.local.hsappstatic.net/<PACKAGE_NAME>/static/test/test.html`
- That serve is compiling (and they can start working while it builds)

## Saving context on exit

When the user says they're done, exiting, or wrapping up — or when you've completed a significant milestone — update `~/src/workspaces/<WORKSPACE_NAME>/CONTEXT.md` with:

```markdown
# <WORKSPACE_NAME> Context

## Goal
<What the user is trying to accomplish>

## Status
<What's been done so far>

## Next steps
<What's left to do>

## Branches
<List of repos and their current branch + latest commit subject>

## Notes
<Any blockers, decisions made, or things to watch out for>
```

This file is read by future sessions to restore context. Keep it concise — focus on non-obvious state that can't be derived from the code or git log.
