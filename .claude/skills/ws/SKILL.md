---
name: ws
description: Manage parallel multi-repo development workspaces using the ws CLI tool. Use when the user wants to create, update, tear down, or inspect workspaces, or mentions workspaces or parallel dev environments.
argument-hint: "up <name> <repo[:branch]...>"
---

# Workspace Manager

All workspace operations go through a single CLI — run it for full docs:

```
uv run {{SKILL_PATH}}/scripts/ws.py --help
```

See `ws.py --help` for the two-agent role model (Creator vs Workspace Claude) and safety rules.

---

# Section 1: Shared rules (creator + workspace Claude)

## Critical safety rules

- **ALL workspace interaction goes through `ws.py`.** Never reach behind it — no `pkill`, no killing PIDs directly, no spawning serve processes by hand, no reconstructing commands from `ps` output, no touching route-configs or state files directly. If you think you need to, you don't; there is a `ws.py` command for it.
- **NEVER delete git branches** unless the user explicitly asks. Only `ws.py nuke --delete-branches` does this, and confirm with the user first.
- **NEVER run `ws.py nuke` without explicit user confirmation.** Nuke is irreversible — it deletes all workspace files and kills the tmux session. Do not infer that nuke is the right move; the user must explicitly ask to tear down or delete the workspace. Do NOT use nuke to remove a single repo, switch branches, free memory, or resolve a stuck serve — use `restart` or recreate with the desired repos instead.
- **NEVER do setup work from the creator.** After `ws.py init` launches the workspace Claude, the creator is done.

## Conventions

- **Portal ID**: `103830646`

---

# Section 2: Creator instructions

The creator reads this section to handle user requests. The workspace Claude never sees it.

## Routing

When the user invokes this skill (via `/ws` or natural language), route based on intent:
- "spin up / create / up a workspace" → `Creating a workspace` below
- "add a repo / more repos" → `Adding repos` below
- "tear down / nuke / destroy" → **always confirm with the user first**, then `ws.py nuke <name>`. Do not run nuke just because a workspace needs different repos or a branch change — those don't require a full teardown.

If repos are given in natural language, confirm your interpretation before proceeding.

## Creating a workspace

`/ws up <name> <repo[:branch]>...`

1. **Run `ws.py plan`** — if `ok: false`, show `missingRepos` and stop.
   ```
   uv run {{SKILL_PATH}}/scripts/ws.py plan <name> <repo1> <repo2:branch>...
   ```

2. **Briefly state what you're doing** (one line — workspace name + repos). Don't wait for approval; proceed straight to step 3. Tell the user init will take a few minutes; they can tail logs with `ws.py logs <name> --tail 200` while they wait.

3. **Run `ws.py init`** with the prompt inline — blocks ~2–4 min before launching workspace Claude:
   ```
   uv run {{SKILL_PATH}}/scripts/ws.py init <name> \
     --repos <repo1>:<branch1> <repo2>:<branch2> ... \
     --prompt "<handoff prompt text>"
   ```
   ws.py writes the prompt to `<workspace>/INIT-PROMPT.txt` where it persists.
   See "Building the handoff prompt" below for the prompt template.
   **Always run `ws.py list` before init** to check `headroomMB`. See `ws.py prefs --help` for memory configuration.

4. **Tell the user** how to access the new workspace (from `init`'s JSON output). Done.

---

## Adding repos to an existing workspace

`/ws up <name> <new-repo>...` when the workspace already exists (plan output has `existing: true`):

Tell the user to switch to the workspace and ask the workspace Claude to run `ws.py add <name> <new-repo>...`. The creator does NOT do this work.

## Building the handoff prompt

Pass this as the `--prompt` string to `ws.py init`. Template:

```
You are starting in the <WORKSPACE_NAME> workspace.

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

- **ALL workspace interaction goes through `ws.py`.** Never reach behind it — no `pkill`, no killing PIDs directly, no spawning serve processes by hand, no reconstructing commands from `ps` output, no touching route-configs or state files directly. If you think you need to, you don't; there is a `ws.py` command for it.
- **NEVER delete git branches** unless the user explicitly asks.
- **NEVER run `ws.py nuke` without explicit user confirmation.** Nuke is irreversible. Do not use it to remove a single repo, switch branches, free memory, or resolve a stuck serve — try `restart` first. Only run nuke when the user explicitly asks to tear down and discard the workspace.

## First action after handoff

Setup was already done by `ws.py init` before you spawned. Run the post-init startup sequence from `ws.py init --help`, sequentially and exactly once. If the log-check returns hits, use the "Setup failed" template. Otherwise use "Workspace ready". Never skip the log check.

If the user asks to add a repo, use `ws.py add <name> <repo>:<branch>`. If resuming a workspace whose files exist but serve is down, use `ws.py setup <name>`.

## Validating code with bend MCP tools

Bend tools are **deferred** — schemas aren't loaded until you fetch them via `ToolSearch` with query `bend`. If the tool isn't in your immediate list, search first; don't conclude it's missing. Never fall back to shell `tsc`/`jasmine`. Tests take 2–5 min, TS checks up to 120s — don't restart serve because tests are slow.

## Background monitor and report templates

See `ws.py help monitor` and `ws.py help templates`.

## CONTEXT.md on exit

At milestones or exit, update `~/src/workspaces/<WORKSPACE_NAME>/CONTEXT.md` with sections: **Goal**, **Status**, **Next steps**, **Branches**, **Notes**. Keep it to non-obvious state — not anything derivable from code or git log.
