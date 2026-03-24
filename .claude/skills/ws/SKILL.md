---
name: ws
description: Manage parallel multi-repo development workspaces using git worktrees, tmux, and bend serve. Use when the user wants to create, update, tear down, or inspect workspaces, or mentions workspaces, worktrees, or parallel dev environments.
argument-hint: "[up <name> <repo[:branch]...> | down <name> | nuke <name> | rm <name> <repo...> | ls | info <name> | attach <name>]"
---

# Workspace Manager

Manage isolated multi-repo development workspaces. Each workspace gets its own git clones, bend serve instance (with a unique subdomain), and tmux session.


## Conventions

- **Workspace root**: `~/src/workspaces/<name>/`
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

1. Validate each repo exists at `~/src/<repo>/`. Stop and report if any are missing.
2. **Resolve the remote URL** for each repo:
   ```
   git -C ~/src/<repo> remote get-url origin
   ```
   This gives the actual GitHub remote URL. The workspace clone will use this directly so its `origin` points to GitHub, not the local source repo.
3. `mkdir -p ~/src/workspaces/<name>/`
4. Pre-seed Claude Code trust: `mkdir -p ~/src/workspaces/<name>/.claude`
   This prevents the first-launch trust prompt when Claude starts in the workspace's tmux window.
5. For each repo, clone from the remote URL and check out a workspace branch:
   ```
   git clone <remote-url> ~/src/workspaces/<name>/<repo>
   git -C ~/src/workspaces/<name>/<repo> checkout -b <branch> origin/master
   ```
   If `-b <branch>` fails (branch already exists on the remote), check it out instead:
   ```
   git -C ~/src/workspaces/<name>/<repo> checkout <branch>
   ```
6. Run `bend yarn` in each clone (sequentially)
7. Discover packages and prompt the user to select which to serve (see "package discovery and selection" below)
8. Create tmux session (see "tmux layout" below)
9. Start serve in the tmux serve window (see "serve command" below)
10. Verify serve is running (see "serve health check" below)
11. Report: workspace name, repos with branches, base URL, and app URLs

**Updating an existing workspace (repos specified):**

1. Determine which repos are new (not yet in workspace) and which already exist
2. For new repos: clone as above
3. For existing repos where the specified branch differs from current: ask the user to confirm the branch switch before proceeding. Switch with `git -C <clone> checkout <branch>`
4. If anything changed, restart serve (see "restarting serve" below)
5. If tmux session doesn't exist, create it

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

Three windows per workspace:

1. **serve** — runs the bend serve command. Working directory: `~/src/workspaces/<name>/`
2. **shell** — empty shell for manual work. Working directory: `~/src/workspaces/<name>/`
3. **<name>** — starts a Claude Code instance (window and session both named after the workspace). Working directory: `~/src/workspaces/<name>/`

Creation sequence:
```bash
tmux new-session -d -s <name> -n serve -c ~/src/workspaces/<name>/
tmux send-keys -t <name>:serve '<serve-command>' Enter
tmux new-window -t <name> -n shell -c ~/src/workspaces/<name>/
tmux new-window -t <name> -n <name> -c ~/src/workspaces/<name>/
tmux send-keys -t <name>:<name> '<claude-launch-command>' Enter
tmux select-window -t <name>:shell
```

IMPORTANT: Use `tmux send-keys` with the command as a single argument (not piped through shell) so that globs in the serve command aren't expanded prematurely.

### Claude tab launch

Always pass `--name <workspace-name>` so the Claude session is named after the workspace:

```bash
claude --name <name>
```

If the user provided task context beyond just "create workspace X with repos Y" (e.g., "spin up a workspace to investigate perf issues in crm-object-table"), pass it as an initial prompt:

```bash
claude --name <name> "This is the <name> workspace. Run /ws info <name> to orient yourself. Then: <user's task context>"
```

The prompt should only contain the task context — NOT repo names, branches, serve URLs, or workspace details. The claude instance can discover all of that itself via `/ws info <name>`.

Escape any single quotes in the prompt (replace `'` with `'\''`) since the whole command is wrapped in single quotes for tmux send-keys.

## Serve command

### Package discovery and selection

Each repo contains multiple serveable packages (main app/lib, kitchen sinks, storybooks, utility libs, etc.). Rather than serving everything, discover the available packages and let the user choose.

**Discovery:** For each repo clone, list subdirectories that are serveable packages:
```bash
ls -d ~/src/workspaces/<name>/<repo>/*/ | grep -v node_modules | grep -v target | grep -v schemas | grep -v hubspot.deploy | grep -v docs | grep -v acceptance-tests
```

Each subdirectory with a `package.json` is a serveable package.

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

If the user says "all" or "everything", serve all packages. If they just confirm, use the defaults.

### Building the serve command

`bend reactor serve` accepts specific package paths as positional args. Pass only the selected package directories instead of the repo root.

For each repo, run `bend yarn` first (in the clone dir), then build the serve command with explicit package paths:

```
env BEND_WORKTREE=<name> NODE_ARGS=--max_old_space_size=16384 bend reactor serve <pkg-path-1> <pkg-path-2> ... --update --ts-watch --enable-tools --run-tests
```

Where each `<pkg-path>` is a full path like `~/src/workspaces/<name>/<repo>/<package>/`.

Chain it all together for the tmux send-keys:
```
cd ~/src/workspaces/<name>/<repo1> && bend yarn && cd ~/src/workspaces/<name>/<repo2> && bend yarn && cd ~ && env BEND_WORKTREE=<name> NODE_ARGS=--max_old_space_size=16384 bend reactor serve <pkg-path-1> <pkg-path-2> ... --update --ts-watch --enable-tools --run-tests
```

### Serve health check

After starting or restarting serve, verify it's actually running:

1. Wait 10 seconds for the process to start: `sleep 10`
2. Capture recent output from the serve window:
   ```
   tmux capture-pane -t <name>:serve -p -S -30
   ```
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

1. `tmux send-keys -t <name>:serve C-c` (Ctrl-C the current serve)
2. `sleep 2`
3. `pkill -TERM -f "BEND_WORKTREE=<name>"` then `sleep 1` then `pkill -9 -f "BEND_WORKTREE=<name>"`
4. Send the new serve command to the serve window
5. Run the serve health check (see above)

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

- Always validate that source repos exist before cloning
- Never delete branches without explicit user confirmation (nuke only)
- `down` preserves remote branches — local branches are gone with the clone, which is expected
- The filesystem is the single source of truth. No metadata files, no state tracking.
- When running multiple git/tmux commands, run them sequentially (they depend on each other)
- For `pkill`, always SIGTERM first, wait, then SIGKILL. Processes may not die immediately.
- Use `git -C <path>` instead of `cd <path> && git ...` to avoid compound-command security prompts.
- This skill replaces the old `ws` Node.js CLI tool at `~/.local/bin/ws`. NEVER modify files in `~/.local/bin/ws*` or `~/.local/lib/ws/` — those are legacy and should not be touched.
- Workspace directories are ephemeral. Any per-project Claude Code settings (permissions, rules) granted during a workspace session will be lost on teardown. Prefer configuring permissions globally in `~/.claude/settings.json` rather than per-workspace.
