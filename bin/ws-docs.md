# ws — workspace manager

A CLI tool for running multiple parallel HubSpot frontend dev environments.
Each "workspace" is an isolated set of git worktrees served together via
`bend reactor serve` with a unique subdomain, managed inside a tmux session.

Source: `~/src/dotfiles/bin/ws` (Node.js, zero dependencies)
Installed: `~/.local/bin/ws` → symlink to the source file
Completions: `.config/fish/completions/ws.fish` → thin shim calling `command ws --completions`
Tests: `node ~/src/dotfiles/bin/ws-test.js`

Previously a Fish shell script (`.config/fish/functions/ws.fish`). Migrated to
Node.js to be shell-agnostic and eliminate the manual copy step Fish required.

## What problem this solves

HubSpot frontend work frequently spans multiple repos (e.g., crm-index-ui +
crm-object-table + customer-data-table). These get served together via
`bend reactor serve <path1> <path2> ...`.

When you need to work on two features simultaneously, you can't check out two
branches of the same repo. Even if you could, you'd need two separate serve
instances with distinct URLs. This tool solves both problems using:

1. **Git worktrees** — each workspace creates a separate working copy of each
   repo under `~/workspaces/<name>/<repo>/`. Worktrees share the same .git
   object store as `~/src/<repo>`, so they're cheap. Each gets its own branch.

2. **BEND_WORKTREE** — HubSpot's bend tool gives each serve instance a unique
   subdomain when this env var is set. `BEND_WORKTREE=my-feature` →
   `https://my-feature.local.app.hubspotqa.com`.

3. **tmux sessions** — each workspace gets a tmux session with windows for
   serve, a shell, and a Claude Code instance.

## Filesystem layout (the single source of truth)

```
~/workspaces/                 All workspaces
~/workspaces/<name>/          Workspace root
~/workspaces/<name>/<repo>/   Git worktree (has a .git FILE pointing to parent)
```

There are no metadata files. The filesystem IS the state:
- `~/workspaces/` → list of workspace names
- `~/workspaces/<name>/` → list of repos (dirs with a `.git` file = worktrees)
- Each `.git` file contains `gitdir: /Users/brbrown/src/<repo>/.git/worktrees/...`
  which lets us derive the parent repo path

## Code structure

The file is organized top-to-bottom in dependency order:

| Section | What |
|---|---|
| Constants | `HOME`, `SRC`, `WS_DIR`, `BRANCH_PREFIX` |
| Color helpers | ANSI wrappers with `NO_COLOR` / non-TTY detection |
| Shell helpers | `run()`, `runSilent()`, `tmuxHasSession()`, `pgrepCount()` |
| Filesystem helpers | `getRepos()`, `parentRepo()`, `allWorkspaces()` |
| URL maps | `APP_PATHS` and `TEST_PATHS` objects, `appUrl()`, `testUrls()` |
| Commands | `cmdUp`, `cmdDown`, `cmdAdd`, `cmdRm`, `cmdLs`, `cmdInfo`, `cmdAttach`, `cmdCheck`, `cmdHelp` |
| Completions | `getSrcRepos()`, `cmdCompletions()` — outputs candidates for shell completion |
| CLI router | `process.argv` dispatch |

## Design decisions and why

### No metadata files
We intentionally eliminated `~/.local/share/ws/<name>` metadata files that
previously stored the list of repos per workspace. The filesystem can't drift
out of sync — if you manually add/remove a worktree, `ws ls` still reflects
reality.

### Process cleanup with pkill -f
`tmux kill-session` does NOT kill bend's child processes. When bend runs
`tsc --watch`, rspack dev servers, etc., those processes detach from the
terminal (show `??` in ps aux). They survive the session dying.

The fix: before killing tmux, `cmdDown` runs `pkill -f "$wsRoot"` which
matches any process whose command line includes the workspace path. This works
because tsc/rspack/webpack all reference workspace paths in their arguments.
SIGTERM first, sleep 2 seconds, then SIGKILL.

### Branch naming
All worktree branches are `brbrown/<workspace-name>` (set via `BRANCH_PREFIX`).
If the branch already exists, the worktree checks it out instead of creating a
new one. Branches are NOT deleted on `ws down` — they may have unpushed commits.

### Worktrees start from origin/master
`createWorktree` runs `git fetch origin` then passes `origin/master` as the
start-point to `git worktree add -b`. This means new branches are based on
the latest remote master, not whatever the local `~/src/<repo>` checkout
happens to have checked out. If the fetch fails (e.g., offline), the worktree
add also fails — this is intentional since starting from stale code silently
is worse. The fallback path (reusing an existing branch) does NOT reset to
origin/master, since that branch may have unpushed work.

### Serve command uses shell glob
The serve command uses `$wsRoot/*` (shell glob) rather than listing repo paths
individually. Adding a worktree manually to the workspace directory automatically
includes it in the next serve restart.

### tmux send-keys uses spawnSync array form
`spawnSync('tmux', ['send-keys', '-t', target, cmd, 'Enter'])` avoids the shell
interpreting the `*` in the serve command as a glob before tmux sees it. This
was a bug in an earlier version.

### Sleep via spawnSync
`spawnSync('sleep', ['2'])` is used instead of busy-waiting or setTimeout. This
is synchronous by design — the tool is a sequential CLI, not an async server.

### Claude window gets monitor-silence 30
The Claude tmux window has `monitor-silence 30` set so that when Claude stops
producing output, tmux highlights that window in the status bar. For cross-
workspace monitoring, `ws check` captures pane content and pattern-matches.

## Gotchas

### parentRepo relies on .git file format
Git worktrees have a `.git` FILE (not directory) containing:
```
gitdir: /Users/brbrown/src/<repo>/.git/worktrees/<worktree-name>
```
We parse this to derive the parent repo path by stripping `/.git/worktrees/...`.
If git ever changes this format, `parentRepo()` breaks and worktrees won't be
removed from the parent during `ws down`.

### URL mappings are hardcoded
`APP_PATHS` and `TEST_PATHS` map repo names to local dev URLs (kitchen sinks,
test pages). New repos need manual entries added to these objects.

### The .claude directory in workspaces
`ws up` creates a `~/workspaces/<name>/.claude/` directory (from Claude Code
starting in the workspace root). `getRepos()` correctly ignores this because
`.claude/` doesn't have a `.git` file. But be aware it exists when iterating
workspace contents.

### Shell completions use `command ws`
The fish completion shim uses `command ws --completions ...` (not just `ws`) to
bypass the fish function in `.config/fish/functions/ws.fish` and call the node
script directly. Without `command`, the fish function intercepts the call and
falls through to the help output.

### restartServe kills by BEND_WORKTREE, cmdDown kills by wsRoot
`restartServe` (used by add/rm) kills with `pkill -f "BEND_WORKTREE=<name>"`
to target just the serve process. `cmdDown` kills with `pkill -f "$wsRoot"` to
catch ALL processes referencing the workspace path.

## Testing

### Running tests

```
node bin/ws-test.js
```

The test file has zero dependencies. It runs the `ws` binary as a subprocess
(via `spawnSync`) and asserts on exit codes and output strings.

### What the tests cover

**Basic command tests** (no side effects, always safe to run):
- `help` — exit codes, expected text
- Unknown command — exit 1, error message, help shown
- Usage errors — every command with missing args
- Nonexistent workspace — every command that takes a name
- Nonexistent repo — `up` with a repo not in `~/src`
- `ls` — exit 0, lists all workspace dirs, shows running/stopped status
- `check` — exit 0
- `info` — tested against whatever workspaces exist on disk

**Lifecycle test** (creates real worktrees and a tmux session):
- Creates a temporary git repo at `~/src/ws-test-fixture` (with a self-referencing
  `origin` remote so `git fetch origin` and `origin/master` resolve)
- Runs: `up` → `info` → `ls` → `rm` → `add` → `down`
- Verifies at each step: filesystem state, tmux session state, exit codes, output
- Checks edge cases: duplicate `up`, `rm` nonexistent repo, `add` already-present repo, `--branch` flag parsing
- Verifies no orphan processes after `down`
- Cleans up the temp repo and workspace in a `finally` block

### When to add new tests

Add a test when you:
- **Add a new command** — add both a usage-error test and a lifecycle step
- **Add a new flag** — test the flag, test it missing its value, test it with invalid input
- **Change process cleanup logic** — the "no orphan processes" assertion in the lifecycle test should catch regressions, but add targeted assertions if the cleanup strategy changes
- **Change the serve command** — verify `restartServe` still works by testing `add` or `rm`
- **Fix a bug** — add a regression test that would have caught it

You do NOT need to add tests for:
- URL map changes (adding entries to `APP_PATHS` / `TEST_PATHS`)
- Help text wording changes
- Color/formatting changes
