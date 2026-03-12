# todo

A terminal client for [Todoist](https://todoist.com). Zero dependencies, just Node.js.

## Setup

1. Get your API token from [Todoist Settings > Integrations > Developer](https://app.todoist.com/app/settings/integrations/developer)

2. Save it:
   ```
   mkdir -p ~/.config/todoist
   echo "YOUR_TOKEN" > ~/.config/todoist/token
   chmod 600 ~/.config/todoist/token
   ```
   Or set `TODOIST_API_TOKEN` in your environment.

3. If using the dotfiles repo, run `stow --target=$HOME . --ignore='\.claude'` to symlink everything.

## Usage

```
todo                        # list all tasks (default)
todo list                   # same thing
todo list --project Work    # filter by project (partial match works)
todo list --filter "today"  # use a Todoist filter
```

### Adding tasks

```
todo add Buy milk
todo add Buy milk --due tomorrow
todo add Fix login bug --project Work --priority 1 --due friday
todo add Weekly report --due "every monday"
```

Priority: **1 = urgent** (red), 2 = high (yellow), 3 = normal (green), 4 = none (white).

Due dates accept natural language — anything Todoist understands: `tomorrow`, `next friday`, `jan 15`, `every weekday`.

### Completing and deleting

```
todo done 6g8Q5GJJ              # complete a task (prints what was completed)
todo done id1 id2 id3           # complete multiple at once
todo delete 6g8Q5GJJ            # delete a task
todo delete id1 id2             # delete multiple
```

### Editing

```
todo edit 6g8Q5GJJ --due "next week"
todo edit 6g8Q5GJJ --content "Updated task name" --priority 2
```

### Projects

```
todo projects                   # list all projects
```

### Help

```
todo help
todo --help
todo -h
```

## Shell completions

Fish completions are included. After stow, `todo <TAB>` gives subcommands, and `todo done <TAB>` fetches your active task IDs with previews.

The completions file is at `.config/fish/completions/todo.fish`.

## Output

Tasks are shown in a table grouped by project, sorted by priority then due date. Recently completed tasks (last 7 days) appear at the bottom. Due dates are color-coded: red = overdue/today, yellow = tomorrow, green = future.

## Files

```
.local/bin/todo              # CLI entrypoint
.local/bin/todo-lib/         # supporting modules
.local/bin/todo-test.js      # tests
.config/fish/completions/todo.fish
```
