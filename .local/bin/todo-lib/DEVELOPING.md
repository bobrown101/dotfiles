# Developing `todo`

## Architecture

Four-layer structure, one-directional dependency flow:

```
todo (entrypoint) → commands.js → api.js
                                → model.js
                                → view.js
```

| File | Role | Rules |
|------|------|-------|
| `todo` | CLI entrypoint, arg parsing, command routing, `--completions` handler | No business logic. Parses argv, dispatches to commands. |
| `todo-lib/api.js` | HTTP client for Todoist REST API v1 | Thin wrappers around `request()`. Returns promises. No data transformation. |
| `todo-lib/model.js` | Pure data transformation functions | No I/O, no side effects. Translates between API shapes and internal shapes. |
| `todo-lib/view.js` | Terminal output formatting | All ANSI/table/formatting logic lives here. Never called from api.js or model.js. |
| `todo-lib/commands.js` | Command handlers (controller layer) | Wires api → model → view. Each exported function is one CLI command. |

## Adding a new command

1. Add the handler in `commands.js` — async function that calls api, transforms with model, outputs with view
2. Add a `case` in the `switch` in `todo` (entrypoint)
3. Add to the `SUBCOMMANDS` array in the `completions()` function in `todo`
4. Add help text in `view.js` `printHelp()`
5. Add a test in `todo-test.js`

## API details

- **Base URL:** `https://api.todoist.com/api/v1/`
- **Auth:** Bearer token from `TODOIST_API_TOKEN` env var or `~/.config/todoist/token` file
- **Response envelope:** List endpoints return `{ results: [...], next_cursor }` except completed tasks which return `{ items: [...] }`
- **Token is read on every request** via `getToken()` (no caching)
- All list accessors have defensive `|| []` fallbacks in case the response shape changes

### Endpoints used

| Function | Method | Path |
|----------|--------|------|
| `listTasks` | GET | `/api/v1/tasks` |
| `getTask` | GET | `/api/v1/tasks/{id}` |
| `createTask` | POST | `/api/v1/tasks` |
| `closeTask` | POST | `/api/v1/tasks/{id}/close` |
| `deleteTask` | DELETE | `/api/v1/tasks/{id}` |
| `updateTask` | POST | `/api/v1/tasks/{id}` |
| `listProjects` | GET | `/api/v1/projects` |
| `listCompletedTasks` | GET | `/api/v1/tasks/completed/by_completion_date` |

### Timeout behavior

`request()` accepts an optional `{ timeout }` parameter (ms). Used by `listTasksQuick` and `listProjectsQuick` (3s timeout) for shell completions where hanging is unacceptable. Completions swallow all errors silently — this is intentional.

## Priority mapping

Todoist's API uses inverted priority values (4=urgent, 1=none). This tool normalizes for the user:

| User flag | API value | Display |
|-----------|-----------|---------|
| `--priority 1` | 4 | 🔴 urgent |
| `--priority 2` | 3 | 🟡 high |
| `--priority 3` | 2 | 🟢 normal |
| `--priority 4` | 1 | ⚪ none |

Conversion: `apiPriority = 5 - userPriority`. This is done in `model.userToApiPriority()`. The view layer maps API values directly to emoji.

## Project resolution

`model.resolveProjectId(name, projects)` does case-insensitive matching:
1. Exact match first (case-insensitive)
2. Falls back to partial substring match
3. Returns first match — no disambiguation for ambiguous partials

## View / table rendering

`visLen()` calculates terminal display width of strings containing ANSI escapes and emoji. It has separate `isWide()` and `isZeroWidth()` checks for CJK characters, emoji, variation selectors, and zero-width joiners.

The `table()` function renders Unicode box-drawing tables. Column widths are auto-calculated from content.

`NO_COLOR` env var and non-TTY detection disable ANSI codes.

## Running tests

```
node .local/bin/todo-test.js
```

Tests are subprocess-based (spawn the real `todo` binary) plus direct model unit tests. No mocking, no test framework.

**What's tested:**
- Help output and flag variants (`help`, `--help`, `-h`)
- Unknown command handling
- Completions output (subcommands, flags)
- Argument validation for all commands (missing required args)
- Token missing error
- All model pure functions (formatTask, formatProject, sortTasks, groupTasksByProject, resolveProjectId, buildTaskBody, priority mapping)

**What's not tested (by design):**
- Live API calls — would require a real token and create/delete real tasks
- View rendering — visually verified, hard to assert meaningfully

## Known limitations

- `--flag=value` syntax not supported, only `--flag value` (space-separated)
- No way to clear a due date via `todo edit` (falsy check drops empty strings)
- Partial project matching can be ambiguous with similarly-named projects
- Completed tasks endpoint has a different response key (`items` vs `results`) — if Todoist changes this, the `|| []` fallback silently returns nothing rather than crashing
- The default `list` command makes 3 parallel API calls (tasks, completed, projects) — 2 if `--project` was already resolved

## Stow setup

Files live under `.local/bin/` in the dotfiles repo. `stow --target=$HOME . --ignore='\.claude'` creates symlinks in `~/.local/bin/`, which must be in `$PATH`. Fish completions go to `~/.config/fish/completions/`.
