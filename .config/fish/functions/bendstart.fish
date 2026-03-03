function bendstart --description 'Start bend reactor serve with multiple repos and optional git worktree resolution'
    if test (count $argv) -lt 1
        echo "Usage: bendstart [workspace-name] [repo@worktree|repo] ..."
        echo ""
        echo "Starts bend reactor serve for one or more repositories, with automatic"
        echo "git worktree path resolution. If the first argument is NOT an existing"
        echo "directory in ~/src/, it is treated as a workspace name and sets"
        echo "BEND_WORKTREE for the serve command."
        echo ""
        echo "Repo specs:"
        echo "  repo            Uses ~/src/repo"
        echo "  repo@worktree   Looks up the worktree path via git worktree list"
        echo ""
        echo "Examples:"
        echo "  bendstart crm-index-ui crm-object-board"
        echo "  bendstart BendDomain hs-entities@dallas crm-object-board@rome crm-index-ui"
        return 1
    end

    set -l src "$HOME/src"
    set -l first_arg $argv[1]
    set -l workspace_name ""
    set -l use_worktree_env false
    set -l repo_args

    if test -d "$src/$first_arg"
        set repo_args $argv
    else
        set workspace_name $first_arg
        set use_worktree_env true
        set repo_args $argv[2..-1]
    end

    if test (count $repo_args) -eq 0
        echo "Error: No repositories specified"
        return 1
    end

    set -l full_paths
    for repo_spec in $repo_args
        if string match -q '*@*' -- $repo_spec
            set -l repo (string replace -r '@.*' '' -- $repo_spec)
            set -l worktree (string replace -r '.*@' '' -- $repo_spec)
            set -l main_repo "$src/$repo"

            if not test -d "$main_repo"
                echo "Error: Main repo not found at $main_repo"
                return 1
            end

            set -l worktree_path (git -C "$main_repo" worktree list --porcelain | string match 'worktree *' | string replace 'worktree ' '' | string match "*/$worktree")

            if test -z "$worktree_path"
                echo "Error: Worktree '$worktree' not found for repo '$repo'"
                return 1
            end

            set -a full_paths $worktree_path
        else
            set -a full_paths "$src/$repo_spec"
        end
    end

    if test "$use_worktree_env" = true
        echo "starting with BEND_WORKTREE=$workspace_name"
    else
        echo "starting"
    end

    for p in $full_paths
        echo "Running bend yarn in "(dirname $p)
        if not cd (dirname $p)
            echo "Error: Could not cd to "(dirname $p)
            return 1
        end
        bend yarn; or return 1
    end

    cd $HOME

    if test "$use_worktree_env" = true
        env BEND_WORKTREE=$workspace_name NODE_ARGS=--max_old_space_size=8192 bend reactor serve --enable-tools --update --ts-watch --run-tests $full_paths
    else
        env NODE_ARGS=--max_old_space_size=8192 bend reactor serve --enable-tools --update --ts-watch --run-tests $full_paths
    end
end
