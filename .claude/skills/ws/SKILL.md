---
name: ws
description: Manage parallel multi-repo development workspaces using git worktrees, tmux, and bend serve. Use when the user wants to create, update, tear down, or inspect workspaces, or mentions workspaces, worktrees, or parallel dev environments.
argument-hint: "[up <name> <repo[:branch]...> | down <name> | nuke <name> | rm <name> <repo...> | ls | info <name> | attach <name>]"
---

# Workspace Manager

Manage isolated multi-repo development workspaces. Each workspace gets its own git clones, bend serve instance (with a unique subdomain), and tmux session.

## Design principle: fast handoff

The **creator** (the Claude instance where the user asks for a workspace) does the absolute minimum: validate inputs, create the directory, launch the tmux session, and hand off to the **workspace Claude** (the Claude instance that runs inside the workspace tmux session). The workspace Claude handles everything else — cloning, installing, package discovery, serve, and asking the user any follow-up questions. This keeps the creator fast and lets the workspace Claude own its own environment.

## Conventions

- **Workspace root**: `~/src/workspaces/<name>/`
- **Name normalization**: always replace spaces with hyphens in the workspace name before using it anywhere (directory paths, tmux session, prompt file, serve subdomain, branch names). E.g. `"search endpoint migration"` → `"search-endpoint-migration"`.
- **Source repos**: `~/src/<repo>/` (these must exist before cloning)
- **Clones**: `~/src/workspaces/<name>/<repo>/` (cloned from the repo's GitHub remote URL)
- **Branch default**: `brbrown/<workspace-name>` (override per-repo with `repo:branch` syntax)
- **Serve URL**: `https://<name>.local.app.hubspotqa.com`
- **Test URL base**: `https://<name>.local.hsappstatic.net`
- **Portal ID**: `103830646`
- **Shell**: The user's shell is fish. All commands sent to tmux windows run in fish. Use `env VAR=value command` syntax instead of `VAR=value command`.
- **No metadata files** — the filesystem IS the state. List `~/src/workspaces/` to see workspaces, list subdirs with `.git` dirs to see repos.

## Operations

When the user invokes this skill (via `/ws` or natural language like "spin up a workspace"), determine which operation they want and execute it.

If the user provides repo names in natural language (e.g., "Customer Data Table"), match them against directory names in `~/src/` (e.g., `customer-data-table`). Confirm the match with the user if ambiguous.

### up — Create or update a workspace

`/ws up <name> <repo[:branch]...>`

This is idempotent. Works for both new and existing workspaces.

**Creating a new workspace:**

The creator does only these steps:

1. **Validate repos and resolve remote URLs in a single command** for each repo:
   ```
   git -C ~/src/<repo1> remote get-url origin && git -C ~/src/<repo2> remote get-url origin
   ```
   Stop and report if any fail.

2. **Present a confirmation plan before executing.** After validating repos (step 1), present a single summary and ask the user to confirm or adjust. The plan should include:
   - **Workspace name** (= tmux session name and serve subdomain)
   - **Branch name** for each repo (default: `brbrown/<workspace-name>`, or as specified)
   - **Repos** that will be cloned
   - **Serve URL** (`https://<name>.local.app.hubspotqa.com`)

   Format example:
   ```
   Here's the plan:

   Workspace: css-hover-cell-cleanup
   Repos & branches:
     customer-data-table → brbrown/css-hover-cell-cleanup
   Serve URL: https://css-hover-cell-cleanup.local.app.hubspotqa.com

   OK to proceed, or any changes?
   ```

   Wait for explicit approval before proceeding.

3. **Write the handoff prompt to a temp file**, then **run `ws-init`** — two tool calls (sequential):

   First, use the Write tool to write the handoff prompt (see "Claude tab launch" below) to `/tmp/ws-<name>-init-prompt.txt`. Writing to `/tmp` doesn't require approval.

   Then run:
   ```bash
   ~/.local/bin/ws-init <name>
   ```

   The `ws-init` script handles everything: creating the workspace directory, writing `.claude/settings.json`, creating the tmux session/windows, and launching the workspace Claude from the prompt file. This is a single Bash call that can be auto-approved, avoiding the multiple approval prompts that mkdir-on-sensitive-paths and tmux `&&` chains would trigger.

4. **Tell the user** the workspace is being set up and to switch to the `<name>` tmux session. Do NOT do any further setup work — the workspace Claude handles everything from here.

**Updating an existing workspace (repos specified):**

1. Determine which repos are new (not yet in workspace) and which already exist
2. For new repos: pass them to the workspace Claude via the handoff prompt to clone
3. For existing repos where the specified branch differs from current: ask the user to confirm the branch switch before proceeding
4. If tmux session doesn't exist, create it

**Updating with no repos specified (`/ws up <name>`):**

Just ensure the tmux session exists (create if needed) and tell the user to attach.

### down — Tear down a workspace

`/ws down <name>`

1. Kill all processes referencing the workspace path:
   ```
   pkill -TERM -f ~/src/workspaces/<name>
   sleep 2
   pkill -9 -f ~/src/workspaces/<name>
   ```
   IMPORTANT: `tmux kill-session` alone does NOT kill bend's child processes (tsc, rspack, webpack). They detach and survive. Must pkill by workspace path BEFORE killing tmux.
2. Kill the tmux session: `tmux kill-session -t <name>`
3. `rm -rf ~/src/workspaces/<name>/`
4. Report what was cleaned up
5. **Branches are kept on the remote** — if they were pushed. Local branches are gone with the clone, which is fine.

### nuke — Tear down and delete branches

`/ws nuke <name>`

1. BEFORE doing anything, gather branch info for all repos in the workspace (repo name, branch name)
2. Show the user what will be deleted and **ask for confirmation**. Do NOT proceed without explicit yes.
3. Run the full `down` procedure
4. Delete the branch from each source repo (in case it exists there too): `git -C ~/src/<repo> branch -D <branch>` (ignore errors if branch doesn't exist)
5. Optionally delete remote branches if pushed: `git -C ~/src/<repo> push origin --delete <branch>` (ask user first)
6. Report which branches were deleted

### rm — Remove repos from a workspace

`/ws rm <name> <repo...>`

1. For each repo: `rm -rf ~/src/workspaces/<name>/<repo>`
2. Restart serve (see below)
3. Report what was removed

### ls — List workspaces

`/ws ls`

1. List directories in `~/src/workspaces/`
2. For each, check if a tmux session exists: `tmux has-session -t <name>`
3. List subdirectories with `.git` dirs (these are the repos)
4. Display each workspace with running/stopped status and its repos

### info — Show workspace details

`/ws info <name>`

1. List repos in the workspace (subdirs with `.git` dirs)
2. For each repo, get current branch: `git -C <path> branch --show-current`
3. Show: workspace name, root path, each repo with its branch
4. Show the base URL: `https://<name>.local.app.hubspotqa.com`
5. Try to infer app URLs for each repo (see "URL inference" below)
6. Show helpful commands: how to add repos, tear down, attach

### attach

`/ws attach <name>`

Claude cannot perform an interactive tmux attach. Instead, tell the user to run:
- If inside tmux: `tmux switch-client -t <name>`
- If outside tmux: `tmux attach -t <name>`

## tmux layout

Two windows per workspace:

1. **shell** — empty shell for manual work. Working directory: `~/src/workspaces/<name>/`
2. **<name>** — starts a Claude Code instance (window and session both named after the workspace). Working directory: `~/src/workspaces/<name>/`

Serve runs as a Claude Code background task owned by the workspace Claude (see "Serve command" below).

Creation is handled by `~/.local/bin/ws-init <name>` — see step 3 of "up" above. The script creates the tmux session, windows, and launches the workspace Claude.

### Claude tab launch

Always pass `--name <workspace-name>` so the Claude session is named after the workspace.

The workspace Claude instance is responsible for ALL setup: cloning repos, installing deps, discovering packages, starting serve, and reporting workspace details. The creator passes all necessary context in the initial prompt.

**Handoff prompt template** (written to `/tmp/ws-<name>-init-prompt.txt` by the creator):

```
You are setting up the <name> workspace.

REPOS TO CLONE (clone each, then checkout the branch from origin/master):
<for each repo>
  - repo: <repo-name>, remote: <remote-url>, branch: <branch-name>
</for each repo>

SETUP STEPS:
1. Clone each repo into ~/src/workspaces/<name>/<repo>/ from its remote URL
2. For each clone, checkout the workspace branch: git checkout -b <branch> origin/master (if branch exists on remote, just git checkout <branch>)
3. Run bend yarn in each clone (sequentially)
4. Discover serveable packages and start serve (see below)
5. Report workspace details: name, repos with branches, serve URL, app URLs

SERVE:
- Discover packages: list subdirs with package.json in each repo clone (exclude node_modules, target, schemas, hubspot.deploy, docs, acceptance-tests)
- Classify repos: if <repo>.yaml exists in hubspot.deploy/ → app; if only kitchen-sink/storybook/acceptance-tests yamls → library
- Default selection: always serve the main package; serve kitchen sinks only for libraries with no consuming app in the workspace; never serve storybooks or acceptance-tests
- If the defaults are the only option, auto-accept. Otherwise ask the user which packages to serve.
- Run: env BEND_WORKTREE=<name> NODE_ARGS=--max_old_space_size=16384 bend reactor serve <pkg-paths...> --update --ts-watch --enable-tools --run-tests
- Launch serve as a background task (Bash with run_in_background: true), then verify it started

WORKTREE URLS:
The workspace name is used as a subdomain prefix on ALL local dev URLs. Examples:
- App: https://<name>.local.app.hubspotqa.com/contacts/103830646/objects/0-1/views/all/list
- Test runner: https://<name>.local.hsappstatic.net/<package-name>/static/test/test.html?spec=
- Kitchen sink: https://<name>.local.app.hubspotqa.com/<repo>-kitchen-sink/103830646/
NEVER use the non-worktree domain (local.hsappstatic.net without prefix). Always use <name>.local.hsappstatic.net or <name>.local.app.hubspotqa.com.

PORTAL ID: 103830646

<optional: user intent/task context>
```

Include the user's task context or intent if they provided one (e.g., "The user wants to investigate virtualization DOM mutation performance"). This helps the workspace Claude understand what the user is working on and ask relevant follow-up questions.

No escaping is needed — the prompt is written to a file via the Write tool, and the `ws-init` script reads it from there. This avoids all quoting/escaping issues with tmux send-keys.

## Serve command

All serve setup is handled by the **workspace Claude instance**, not the creator. The handoff prompt (see "Claude tab launch") includes instructions for the workspace Claude to follow.

### Package discovery and selection (workspace Claude)

Each repo contains multiple serveable packages (main app/lib, kitchen sinks, storybooks, utility libs, etc.). Rather than serving everything, discover the available packages and let the user choose.

**Discovery:** For each repo clone, list subdirectories that are serveable packages:
```bash
ls -d ~/src/workspaces/<name>/<repo>/*/ | grep -v node_modules | grep -v target | grep -v schemas | grep -v hubspot.deploy | grep -v docs | grep -v acceptance-tests
```

Each subdirectory with a `package.json` is a serveable package. Some repos are single-package (only a root `package.json`) — in that case, serve the repo root.

**Classify each repo** by checking `<clone>/hubspot.deploy/` for a deploy yaml named after the main package:
- If `<repo>.yaml` exists (e.g., `crm-index-ui/hubspot.deploy/crm-index-ui.yaml`) → the main package is a **deployable app**
- If only `*-kitchen-sink.yaml` / `*-storybook.yaml` / `*-acceptance-tests.yaml` exist → the main package is a **library** and the kitchen sink is its browser testing surface

**Selection:** Present the discovered packages to the user grouped by repo, with defaults pre-selected. Format as a checklist:

```
Which packages do you want to serve?

crm-index-ui:  (app — has its own deploy)
  [x] crm-index-ui

crm-object-table:  (library — kitchen sink is the deployable)
  [x] crm-object-table
  [x] crm-object-table-kitchen-sink

customer-data-properties:  (library — kitchen sink is the deployable)
  [x] customer-data-properties
  [ ] customer-data-properties-kitchen-sink
  [ ] property-value-citations

(packages marked [x] are recommended — say "yes" to accept, or tell me which to add/remove)
```

**Default selection heuristics:**

- **Always pre-select** the main package (the one sharing the repo's name).
- **Kitchen sinks (`*-kitchen-sink`):**
  - If the repo is a **library** AND no app repo in the workspace consumes it → pre-select its kitchen sink (it's the only browser testing surface).
  - If an **app repo** is in the workspace that consumes the library → do NOT pre-select the kitchen sink. The app is the testing surface.
- **Never pre-select** `*-storybook` or `*-acceptance-tests` packages.
- **Other utility packages** (e.g., `property-value-citations`): do NOT pre-select. The user can opt in.

**Auto-accept:** If the default selection results in only the pre-selected packages and there are no additional optional packages to choose from (i.e., every discovered package is pre-selected), skip the prompt entirely and proceed with the defaults. Only prompt when there are meaningful choices to make.

If the user says "all" or "everything", serve all packages. If they just confirm, use the defaults.

### Building the serve command

`bend reactor serve` accepts specific package paths as positional args. Pass only the selected package directories instead of the repo root.

For each repo, run `bend yarn` first (in the clone dir), then build the serve command with explicit package paths:

```
env BEND_WORKTREE=<name> NODE_ARGS=--max_old_space_size=16384 bend reactor serve <pkg-path-1> <pkg-path-2> ... --update --ts-watch --enable-tools --run-tests
```

Where each `<pkg-path>` is a full path like `~/src/workspaces/<name>/<repo>/<package>/`.

### Launching serve as a background task (workspace Claude)

The workspace Claude instance should:

1. Run `bend yarn` sequentially for each repo first (these are short-lived and should run in the foreground):
   ```bash
   cd ~/src/workspaces/<name>/<repo1> && bend yarn && cd ~/src/workspaces/<name>/<repo2> && bend yarn
   ```

2. Then launch the serve command as a background task using the Bash tool with `run_in_background: true`:
   ```bash
   Bash(command="cd ~/src/workspaces/<name> && env BEND_WORKTREE=<name> NODE_ARGS=--max_old_space_size=16384 bend reactor serve <pkg-path-1> <pkg-path-2> ... --update --ts-watch --enable-tools --run-tests 2>&1", run_in_background=true)
   ```

This keeps the background task owned by the long-lived workspace Claude session. The workspace Claude can monitor output, react to errors, and restart serve as needed — even after the creator Claude session is gone.

### Serve health check

After starting or restarting serve, verify it's actually running:

1. Wait 10 seconds for the process to start: `sleep 10`
2. Read the background task's output using `TaskOutput` with the serve task ID
3. Check the output for problems:
   - **Error patterns**: `Error:`, `EADDRINUSE`, `ENOENT`, `Cannot find module`, `ERR!`, `failed`, `FATAL`, `command not found`
   - **Success patterns**: `Compiled`, `webpack`, `rspack`, `Watching for changes`, `ready`, `Built in`
4. If errors are found:
   - Diagnose the issue from the output (wrong paths, missing deps, syntax errors in the command, etc.)
   - Fix the root cause (e.g., re-run `bend yarn`, correct the command)
   - Restart serve and check again
   - Report the issue and fix to the user
5. If no output yet (process still starting), wait another 10 seconds and check again. Check up to 3 times total before reporting that serve is still starting and the user should check manually.

Also use this health check after restarting serve (step 4 of "Restarting serve").

### Restarting serve

When repos are added or removed from a running workspace:

1. `pkill -TERM -f "BEND_WORKTREE=<name>"` then `sleep 1` then `pkill -9 -f "BEND_WORKTREE=<name>"`
2. Launch a new background Bash task with the updated serve command (see "Launching serve as a background task")
3. Run the serve health check (see above)

Note: restart kills by `BEND_WORKTREE=<name>` (targets just serve). Full teardown kills by workspace path (targets everything).

## URL inference

The base URL is always `https://<name>.local.app.hubspotqa.com`.

For per-repo app links, try to infer the path by checking the repo:
1. Look for kitchen sink routes: `find <clone> -path "*/kitchen-sink/*Route*" -o -name "kitchenSinkRoutes*" 2>/dev/null | head -5`
2. Look for static config: `cat <clone>/static/staticConfig.json 2>/dev/null` or similar hubspot.deploy config files
3. Fall back to known patterns:
   - Kitchen sinks: `/<repo-name>-kitchen-sink/<portal-id>/`
   - Full apps (e.g., `crm-index-ui`): `/contacts/<portal-id>/objects/0-1/views/all/list`
4. If nothing found, just give the base URL and let the user navigate.

## Guidelines

- **Creator does minimal work**: The creator validates inputs, creates the workspace dir + settings, launches tmux, and hands off. All cloning, installing, package discovery, and serve setup is the workspace Claude's job.
- **Minimize Bash round trips**: Chain independent commands with `&&` into a single Bash call wherever possible. Every separate Bash invocation requires a permission check and adds latency.
- Always validate that source repos exist before cloning
- Never delete branches without explicit user confirmation (nuke only)
- `down` preserves remote branches — local branches are gone with the clone, which is expected
- The filesystem is the single source of truth. No metadata files, no state tracking.
- When running multiple git/tmux commands, run them sequentially (they depend on each other)
- For `pkill`, always SIGTERM first, wait, then SIGKILL. Processes may not die immediately.
- Use `git -C <path>` instead of `cd <path> && git ...` to avoid compound-command security prompts.
- The `~/.local/bin/ws-init` script is part of this skill and handles workspace bootstrapping (dir creation, settings, tmux, Claude launch).
- Workspace directories get permissive `.claude/settings.json` written by the creator (see step 3 of "up"). This gives the workspace Claude broad read/write/execute access within the workspace without per-command approval prompts.
