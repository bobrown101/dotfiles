# ws - Workspace manager for parallel multi-repo HubSpot frontend development
#
# PROBLEM THIS SOLVES:
#
# At HubSpot, frontend work frequently spans multiple repos. For example, you might
# be changing crm-index-ui, crm-object-table, and customer-data-table all at once.
# These get served together via `bend reactor serve <path1> <path2> ...`.
#
# The issue arises when you want to work on TWO features simultaneously. Feature A
# might need crm-index-ui (branch A) + customer-data-table (branch A), and Feature B
# might need crm-index-ui (branch B) + crm-object-table (branch B). You can't check
# out two branches of the same repo at the same time — and even if you could, you'd
# need two separate bend serve instances with distinct URLs.
#
# HOW IT WORKS:
#
# This tool combines three things to solve the problem:
#
# 1. Git worktrees — each workspace creates a separate working copy of each repo.
#    Worktrees share the same .git object store as ~/src/<repo>, so they're cheap
#    and fast. Each gets its own branch (brbrown/<workspace-name>), its own files,
#    and its own index. You can commit/push from either the worktree or the original.
#
# 2. BEND_WORKTREE — HubSpot's bend tool supports a BEND_WORKTREE env var that gives
#    each serve instance a unique subdomain URL. Setting BEND_WORKTREE=my-feature
#    makes the app available at https://my-feature.local.app.hubspotqa.com instead
#    of https://local.hubspotqa.com. This lets multiple serves run without conflict.
#
# 3. tmux sessions — each workspace gets its own tmux session with windows for the
#    bend serve process, a general shell, and a Claude Code instance.
#
# FILESYSTEM LAYOUT:
#
#   ~/workspaces/<name>/          Workspace root, contains all worktrees
#   ~/workspaces/<name>/<repo>/   Git worktree for one repo (created by git worktree add)
#   ~/.local/share/ws/<name>      Metadata file — just a newline-separated list of repo names
#
# The repos themselves live in ~/src/<repo>/ as the "main" worktree. The workspace
# worktrees in ~/workspaces/ are linked worktrees that share the same git history.
#
# TMUX SESSION LAYOUT:
#
#   [serve]   — runs bend yarn in each worktree, then bend reactor serve with all
#               worktree paths and BEND_WORKTREE set. This is the long-running process.
#   [shell]   — a general-purpose shell at the workspace root. Runs `ws info <name>`
#               on startup to show workspace details (repos, URLs, commands).
#   [claude]  — a Claude Code session started at the workspace root.
#
# PROCESS CLEANUP (important!):
#
# bend reactor serve spawns many child processes: tsc --watch for each package,
# rspack/webpack dev servers, etc. These child processes detach from the terminal
# (they show up with `??` as terminal in `ps aux`). This means `tmux kill-session`
# alone does NOT kill them — it only sends SIGHUP to the shell in each pane, but
# the detached node processes survive as orphans.
#
# To handle this, `ws down` uses pkill -f with the workspace path
# (~/workspaces/<name>) to find and kill ALL processes whose command line references
# files in the workspace. This catches the detached tsc watchers, rspack servers,
# etc. because they all have workspace paths in their arguments (tsconfig paths,
# config paths, etc.). It sends SIGTERM first (graceful), waits 2 seconds, then
# SIGKILL for any survivors.
#
# GIT BRANCH STRATEGY:
#
# Each workspace creates branches named brbrown/<workspace-name> in every repo.
# If the branch already exists (e.g., you already pushed it), the worktree checks
# out the existing branch instead of creating a new one. When tearing down a
# workspace, the branches are NOT deleted — they may have commits you want to push.
#
# URL MAPPING (_ws_url):
#
# The _ws_url function contains a hardcoded map of repo names to their local dev
# URLs (the kitchen sink or app path you'd actually visit in a browser). These are
# specific to brbrown's workflow — add new entries to the switch statement as needed.
# The base URL (https://<name>.local.app.hubspotqa.com) comes from BEND_WORKTREE.
#
# EXAMPLE SESSION:
#
#   $ ws up table-refactor crm-index-ui crm-object-table customer-data-table
#   # Creates worktrees, starts bend serve, opens tmux with 3 windows
#   # Visit https://table-refactor.local.app.hubspotqa.com/contacts/...
#
#   $ ws up sidebar-fix crm-index-ui sidebar-lib
#   # A second workspace — crm-index-ui gets a SECOND worktree on a different branch
#   # Visit https://sidebar-fix.local.app.hubspotqa.com/contacts/...
#
#   $ ws ls
#   # table-refactor [running]
#   #   crm-index-ui
#   #   crm-object-table
#   #   customer-data-table
#   # sidebar-fix [running]
#   #   crm-index-ui
#   #   sidebar-lib
#
#   $ ws down table-refactor
#   # Kills all processes, tmux session, removes worktrees. Branches kept.

function ws --description 'Workspace manager for parallel multi-repo development'
    if test (count $argv) -lt 1
        _ws_help
        return 1
    end
    switch $argv[1]
        case up
            _ws_up $argv[2..-1]
        case down
            _ws_down $argv[2..-1]
        case ls
            _ws_ls
        case attach
            _ws_attach $argv[2..-1]
        case info
            _ws_info $argv[2..-1]
        case help
            _ws_help
        case '*'
            echo "Unknown command: $argv[1]"
            _ws_help
            return 1
    end
end

function _ws_help
    echo ""
    set_color --bold
    echo "ws - parallel multi-repo development with git worktrees"
    set_color normal
    echo ""
    echo "Spins up isolated workspaces so you can work on multiple features at once."
    echo "Each workspace gets its own git worktrees, bend serve (with unique URL),"
    echo "tmux session, and Claude Code instance."
    echo ""
    set_color --bold
    echo "Commands:"
    set_color normal
    echo ""
    set_color cyan
    echo -n "  ws up <name> <repo...>"
    set_color normal
    echo ""
    echo "    Create a workspace. Makes a git worktree (branch brbrown/<name>) for each"
    echo "    repo, starts bend reactor serve with BEND_WORKTREE=<name>, and launches"
    echo "    a tmux session with [serve], [shell], and [claude] windows."
    echo ""
    set_color cyan
    echo -n "  ws down <name>"
    set_color normal
    echo ""
    echo "    Tear down a workspace. Kills the tmux session, removes git worktrees,"
    echo "    and cleans up ~/workspaces/<name>/. Branches are kept."
    echo ""
    set_color cyan
    echo -n "  ws ls"
    set_color normal
    echo ""
    echo "    List all workspaces and whether their tmux session is running."
    echo ""
    set_color cyan
    echo -n "  ws attach <name>"
    set_color normal
    echo ""
    echo "    Switch to (or attach to) a workspace's tmux session."
    echo ""
    set_color cyan
    echo -n "  ws info <name>"
    set_color normal
    echo ""
    echo "    Show workspace details: repos, branch, URLs, and helpful commands."
    echo ""
    set_color --bold
    echo "Examples:"
    set_color normal
    echo ""
    set_color brblack
    echo "  # Work on a table refactor across three repos"
    set_color normal
    echo "  ws up table-refactor crm-index-ui crm-object-table customer-data-table"
    echo ""
    set_color brblack
    echo "  # Spin up a second workspace in parallel"
    set_color normal
    echo "  ws up sidebar-fix crm-index-ui sidebar-lib"
    echo ""
    set_color brblack
    echo "  # Done with the refactor"
    set_color normal
    echo "  ws down table-refactor"
    echo ""
    set_color --bold
    echo "Layout:"
    set_color normal
    echo "  Worktrees:  ~/workspaces/<name>/<repo>/"
    echo "  Metadata:   ~/.local/share/ws/<name>"
    echo "  Serve URL:  https://<name>.local.app.hubspotqa.com"
    echo ""
end

function _ws_up
    if test (count $argv) -lt 2
        echo "Usage: ws up <name> <repo...>"
        return 1
    end

    set -l name $argv[1]
    set -l repos $argv[2..-1]
    set -l src ~/src
    set -l ws_root ~/workspaces/$name
    set -l branch "brbrown/$name"
    set -l meta_dir ~/.local/share/ws

    if tmux has-session -t "$name" 2>/dev/null
        echo "Workspace '$name' already exists. Use 'ws attach $name' or 'ws down $name' first."
        return 1
    end

    echo "Creating workspace: $name"
    mkdir -p $ws_root
    mkdir -p $meta_dir

    for repo in $repos
        set -l repo_dir "$src/$repo"

        if not test -d "$repo_dir"
            echo "  Error: repo not found at $repo_dir"
            return 1
        end

        set -l wt_path "$ws_root/$repo"

        if test -d "$wt_path"
            echo "  Exists: $repo"
            continue
        end

        if git -C "$repo_dir" worktree add -b "$branch" "$wt_path" 2>/dev/null
            echo "  Created: $repo (new branch $branch)"
        else if git -C "$repo_dir" worktree add "$wt_path" "$branch" 2>/dev/null
            echo "  Created: $repo (existing branch $branch)"
        else
            echo "  Error: could not create worktree for $repo"
            echo "  (branch '$branch' may already be checked out elsewhere)"
            return 1
        end
    end

    printf '%s\n' $repos > "$meta_dir/$name"

    set -l yarn_cmds
    for repo in $repos
        set -a yarn_cmds "cd $ws_root/$repo && bend yarn"
    end
    set -a yarn_cmds "cd ~"
    set -a yarn_cmds "BEND_WORKTREE=$name NODE_ARGS=--max_old_space_size=16384 bend reactor serve $ws_root/* --update --ts-watch --enable-tools --run-tests"
    set -l serve_cmd (string join " && " $yarn_cmds)

    tmux new-session -d -s "$name" -n serve -c "$ws_root"
    tmux send-keys -t "$name:serve" "$serve_cmd" Enter

    tmux new-window -t "$name" -n shell -c "$ws_root"
    tmux send-keys -t "$name:shell" "ws info $name" Enter

    tmux new-window -t "$name" -n claude -c "$ws_root"
    tmux send-keys -t "$name:claude" "claude" Enter

    tmux select-window -t "$name:shell"

    echo ""
    echo "Workspace '$name' ready."
    set -l base "https://$name.local.app.hubspotqa.com"
    for repo in $repos
        set -l url (_ws_app_url $repo $base)
        if test -n "$url"
            echo "  $repo: $url"
        end
    end
    echo "  Tmux: $name"

    if test -n "$TMUX"
        tmux switch-client -t "$name"
    else
        tmux attach -t "$name"
    end
end

function _ws_down
    if test (count $argv) -lt 1
        echo "Usage: ws down <name>"
        return 1
    end

    set -l name $argv[1]
    set -l src ~/src
    set -l ws_root ~/workspaces/$name
    set -l meta_file ~/.local/share/ws/$name

    set -l killed_count (pgrep -f "$ws_root" | count)
    if test $killed_count -gt 0
        pkill -TERM -f "$ws_root" 2>/dev/null
        echo "Sent SIGTERM to $killed_count processes"
        sleep 2
        pkill -9 -f "$ws_root" 2>/dev/null
    end

    if tmux has-session -t "$name" 2>/dev/null
        tmux kill-session -t "$name"
        echo "Killed tmux session: $name"
    end

    if test -f "$meta_file"
        for repo in (cat "$meta_file")
            set -l repo_dir "$src/$repo"
            set -l wt_path "$ws_root/$repo"
            if test -d "$wt_path"
                git -C "$repo_dir" worktree remove "$wt_path" --force 2>/dev/null
                echo "Removed worktree: $repo"
            end
        end
        rm -f "$meta_file"
    end

    if test -d "$ws_root"
        rm -rf "$ws_root"
    end

    echo "Workspace '$name' torn down."
end

function _ws_ls
    set -l meta_dir ~/.local/share/ws

    if not test -d "$meta_dir"
        echo "No workspaces."
        return
    end

    set -l files $meta_dir/*
    if test (count $files) -eq 0
        echo "No workspaces."
        return
    end

    for meta_file in $files
        set -l name (basename $meta_file)
        set -l repos (cat $meta_file)
        if tmux has-session -t "$name" 2>/dev/null
            set_color green
            echo "$name [running]"
            set_color normal
        else
            set_color yellow
            echo "$name [stopped]"
            set_color normal
        end
        for repo in $repos
            echo "  $repo"
        end
    end
end

function _ws_info
    if test (count $argv) -lt 1
        echo "Usage: ws info <name>"
        return 1
    end

    set -l name $argv[1]
    set -l ws_root ~/workspaces/$name
    set -l meta_file ~/.local/share/ws/$name

    if not test -f "$meta_file"
        echo "No workspace named '$name'"
        return 1
    end

    set -l repos (cat $meta_file)
    set -l branch "brbrown/$name"

    echo ""
    set_color brblack; echo -n "  ── "; set_color normal
    set_color --bold cyan; echo -n "$name"; set_color normal
    set_color brblack; echo " ──────────────────────────────────────────────"; set_color normal
    echo ""
    set_color brblack; echo -n "  branch "; set_color yellow; echo "$branch"; set_color normal
    set_color brblack; echo -n "  root   "; set_color normal; echo "$ws_root"
    echo ""

    set -l app_base "https://$name.local.app.hubspotqa.com"
    set -l test_base "https://$name.local.hsappstatic.net"

    for repo in $repos
        set_color green; echo "  $repo"; set_color normal
        set -l app (_ws_app_url $repo $app_base)
        if test -n "$app"
            set_color brblack; echo "    app   $app"; set_color normal
        end
        set -l tests (_ws_test_urls $repo $test_base)
        if test -n "$tests"
            for t in $tests
                set_color brblack; echo "    test  $t"; set_color normal
            end
        end
    end
    echo ""

    set_color brblack; echo "  ────────────────────────────────────────────────────"; set_color normal
    echo ""
    echo -n "  ws down $name"; set_color brblack; echo "      tear down this workspace"; set_color normal
    echo -n "  ws ls"; set_color brblack; echo "                    list all workspaces"; set_color normal
    echo -n "  ws attach $name"; set_color brblack; echo "    rejoin this session"; set_color normal
    echo ""
end

function _ws_app_url
    set -l repo $argv[1]
    set -l base $argv[2]
    switch $repo
        case crm-index-ui
            echo "$base/contacts/103830646/objects/0-1/views/all/list"
        case crm-object-table
            echo "$base/crm-object-table-kitchen-sink/103830646/"
        case customer-data-table
            echo "$base/framework-data-table-kitchen-sink/103830646/"
        case crm-object-board
            echo "$base/crm-object-board-kitchen-sink/103830646/"
        case customer-data-bulk-actions
            echo "$base/customer-data-bulk-actions-kitchen-sink/103830646/"
        case customer-data-properties
            echo "$base/customer-data-properties-kitchen-sink/99632791/"
        case crm-index-view-components
            echo "$base/crm-index-toolbar-sandbox-ui/103830646"
        case crm-object-gantt
            echo "$base/crm-object-gantt-kitchen-sink/103830646/"
    end
end

function _ws_test_urls
    set -l repo $argv[1]
    set -l base $argv[2]
    switch $repo
        case crm-index-ui
            echo "$base/crm-index-ui/static/test/test.html?spec="
        case crm-object-table
            echo "$base/crm-object-table/static/test/test.html?spec="
        case customer-data-table
            echo "$base/framework-data-table/static/test/test.html?spec="
        case crm-object-search-query-libs
            echo "$base/crm-object-search-query-utilities/static/test/test.html?spec="
        case customer-data-bulk-actions
            echo "$base/customer-data-bulk-actions-container/static/test/test.html?spec="
            echo "$base/customer-data-bulk-actions/static/test/test.html?spec="
        case customer-data-tracking
            echo "$base/customer-data-tracking/static/test/test.html?spec="
        case customer-data-sidebar
            echo "$base/customer-data-sidebar/static/test/test.html?spec="
        case customer-data-properties
            echo "$base/customer-data-properties/static/test/test.html?spec="
        case crm-settings
            echo "$base/crm-settings/static/test/test.html"
        case crm-records-ui
            echo "$base/crm-records-ui/static/test/test.html?spec="
        case reference-resolvers-lite
            echo "$base/reference-resolvers-lite/static/test/test.html?spec="
        case customer-data-associations
            echo "$base/customer-data-associations/static/test/test.html?spec="
        case customer-data-views-management
            echo "$base/customer-data-views-management/static/test/test.html?spec="
            echo "$base/views-management-ui/static/test/test.html?spec="
        case crm-index-view-components
            echo "$base/crm-index-view-components-main/static/test/test.html?spec="
            echo "$base/crm-index-view-table-edit-columns-modal/static/test/test.html?spec="
            echo "$base/crm-index-visualization-toolbar/static/test/test.html"
        case crm-index-associations-lib
            echo "$base/crm-index-associations-lib/static/test/test.html?spec="
        case reporting
            echo "$base/reporting-crm-object-table/static/test/test.html"
            echo "$base/reporting-enablement/static/test/test.html?spec="
        case crm-links
            echo "$base/crm-links/static/test/test.html"
        case pulse
            echo "$base/pulse/static/test/test.html"
    end
end

function _ws_attach
    if test (count $argv) -lt 1
        echo "Usage: ws attach <name>"
        return 1
    end

    set -l name $argv[1]

    if not tmux has-session -t "$name" 2>/dev/null
        echo "No tmux session for workspace '$name'"
        return 1
    end

    if test -n "$TMUX"
        tmux switch-client -t "$name"
    else
        tmux attach -t "$name"
    end
end
