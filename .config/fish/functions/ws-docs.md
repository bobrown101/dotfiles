# ws.fish — notes for future Claude sessions

This file captures context that isn't obvious from reading ws.fish itself.
The code has thorough inline docs at the top of the file — read those first.

## Where the file lives

- Source of truth: `~/src/dotfiles/.config/fish/functions/ws.fish`
- Active copy: `~/.config/fish/functions/ws.fish`
- These are NOT symlinked. After editing the dotfiles copy, you must manually
  copy it to the active location for fish to pick up the changes.

## Key design decisions and why

### No metadata files
We intentionally eliminated `~/.local/share/ws/<name>` metadata files that
previously stored the list of repos per workspace. The filesystem is the only
source of truth now:
- `~/workspaces/` lists workspaces
- `~/workspaces/<name>/` lists repos (dirs with a `.git` file = worktrees)
- Each worktree's `.git` file contains `gitdir: /path/to/parent/.git/worktrees/...`
  which lets us derive the parent repo path

The motivation was avoiding metadata drift — if you manually add/remove a
worktree, the metadata file would be stale. The filesystem can't lie.

### Process cleanup with pkill -f
`tmux kill-session` does NOT kill bend's child processes. When bend runs
`tsc --watch`, rspack dev servers, etc., those processes detach from the
terminal (show `??` in ps aux terminal column). They survive the tmux session
dying because they no longer have a controlling terminal.

The fix: before killing tmux, we `pkill -f "$ws_root"` which matches any
process whose command line includes the workspace path. This works because
tsc/rspack/webpack all reference workspace paths in their arguments (tsconfig
paths, entry points, etc.). We SIGTERM first, wait 2 seconds, then SIGKILL.

This was verified empirically: `ws up` spawned 9 node processes, `ws down`
killed all 9 with zero stragglers.

### Branch naming
All worktree branches are `brbrown/<workspace-name>`. This is hardcoded
(not configurable) matching the user's git branch naming convention. If the
branch already exists, the worktree checks it out instead of creating a new one.
Branches are NOT deleted on `ws down` — they may have unpushed commits.

### bend reactor serve uses glob
The serve command uses `$ws_root/*` (glob) rather than listing each repo path
individually. This is simpler and means adding a worktree manually to the
workspace directory would automatically include it in the next serve.

### BEND_WORKTREE env var
This is a HubSpot-specific feature of the `bend` tool. Setting
`BEND_WORKTREE=<name>` gives the serve instance a unique subdomain:
`https://<name>.local.app.hubspotqa.com` instead of `https://local.hubspotqa.com`.
This is what allows multiple workspaces to serve simultaneously without port
or URL conflicts.

### Claude window gets monitor-silence 30
The claude tmux window has `monitor-silence 30` set so that when Claude stops
producing output for 30 seconds (waiting for permission, asking a question, or
finished), tmux highlights the window in the status bar. This only helps when
you're already attached to that tmux session.

For cross-workspace monitoring, `ws check` captures pane content and
pattern-matches for permission prompts, questions, idle state, etc.

## Gotchas

### _ws_parent_repo relies on .git file format
Git worktrees have a `.git` FILE (not directory) containing:
```
gitdir: /Users/brbrown/src/<repo>/.git/worktrees/<worktree-name>
```
We parse this to derive the parent repo path by stripping `/.git/worktrees/...`.
If git ever changes this format, `_ws_parent_repo` and therefore `_ws_down`
would break — worktrees wouldn't be properly removed from the parent repo.

### URL mappings are hardcoded
`_ws_app_url` and `_ws_test_urls` contain hardcoded switch statements mapping
repo names to their local dev URLs (kitchen sinks, jasmine test pages). These
were sourced from the user's Chrome bookmarks in the "Local app links" and
"Local Tests" bookmark folders (Chrome Profile 1). New repos need manual
entries added to these switch blocks.

### The .claude directory in workspaces
`ws up` creates a `~/workspaces/<name>/.claude/` directory (from Claude Code
starting in the workspace root). `_ws_repos` correctly ignores this because
`.claude/` doesn't have a `.git` file. But be aware it exists when iterating
workspace contents.

### fish function autoloading
All functions in ws.fish are defined in a single file. Fish autoloads the
file when `ws` is called, which makes all the helper functions (`_ws_up`,
`_ws_down`, `_ws_repos`, etc.) available. If you split these into separate
files, each would need its own file named after the function.

## Testing changes

After editing ws.fish:
1. Copy to active location: `cp ~/src/dotfiles/.config/fish/functions/ws.fish ~/.config/fish/functions/ws.fish`
2. Open a new fish shell (or `source ~/.config/fish/functions/ws.fish`)
3. Test with a real `ws up <name> <repo>` / `ws down <name>` cycle
4. Check `ps aux | grep workspaces` after `ws down` to verify no orphaned processes
