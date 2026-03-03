# bendstart - Start bend reactor serve with multiple repos and git worktree support
#
# This is the original zsh/bash version. A fish port lives at
# .config/fish/functions/bendstart.fish
#
# Usage:
#   start [workspace-name] [repo@worktree|repo] ...
#
# If the first argument matches a directory in ~/src/, all arguments are treated
# as repo specs (backwards-compatible mode). Otherwise the first argument is
# used as a workspace name — it gets passed as the BEND_WORKTREE env var to
# bend reactor serve.
#
# Repo spec formats:
#   repo            Plain repo name — resolves to ~/src/<repo>
#   repo@worktree   Resolves the worktree path by running `git worktree list`
#                   inside ~/src/<repo> and matching the worktree name
#
# What it does:
#   1. Resolves all repo paths (including worktree lookups)
#   2. Runs `bend yarn` in each repo's parent directory
#   3. Runs `bend reactor serve --enable-tools --update --ts-watch --run-tests`
#      with all resolved paths (and BEND_WORKTREE if a workspace name was given)
#
# Examples:
#   # Serve two repos from ~/src/ (no worktrees, no BEND_WORKTREE)
#   start crm-index-ui crm-object-board
#
#   # Serve with a workspace name and mixed worktree / non-worktree repos
#   start BendDomain hs-entities@dallas crm-object-board@rome crm-index-ui
#
function start(){
  if [ $# -lt 1 ]; then
    echo "Usage: start [workspace-name] [repo@worktree|repo] ..."
    echo "Examples:"
    echo "  start myworkspace framework-data-schema-resolvers@curitiba crm-index-ui"
    echo "  start framework-data-schema-resolvers crm-index-ui"
    return 1
  fi

  home="$HOME"
  src="${home}/src"

  # Check if first arg is a repo (backwards compatibility)
  local first_arg=$1
  local workspace_name=""
  local use_worktree_env=false

  if [[ -d "${src}/${first_arg}" ]]; then
    # First arg is a repo, backwards compatible mode
    command="echo 'starting'"
  else
    # First arg is workspace name
    workspace_name=$1
    use_worktree_env=true
    shift
    command="echo 'starting with BEND_WORKTREE=${workspace_name}'"
  fi

  args=$#

  # Helper function to find worktree path
  find_worktree_path() {
    local repo=$1
    local worktree_name=$2
    local main_repo="${src}/${repo}"

    if [[ ! -d "$main_repo" ]]; then
      echo "Error: Main repo not found at ${main_repo}" >&2
      return 1
    fi

    # Get worktree list and find the one ending with our worktree name
    local worktree_path=$(git -C "$main_repo" worktree list --porcelain | grep "^worktree " | cut -d' ' -f2- | grep "/${worktree_name}$")

    if [[ -z "$worktree_path" ]]; then
      echo "Error: Worktree '${worktree_name}' not found for repo '${repo}'" >&2
      return 1
    fi

    echo "$worktree_path"
  }

  # Collect paths for yarn
  for (( i=1; i<=$args; i++ )); do
    repo_spec=$@[$i]

    # Check if it contains @
    if [[ "$repo_spec" == *@* ]]; then
      # Split on @
      repo="${repo_spec%@*}"
      worktree="${repo_spec#*@}"
      full_path=$(find_worktree_path "$repo" "$worktree")
      if [[ $? -ne 0 ]]; then
        echo "$full_path"
        return 1
      fi
    else
      # Regular repo in src
      repo="$repo_spec"
      full_path="${src}/${repo}"
    fi

    command="${command} && cd ${full_path}/../ && bend yarn"
  done

  # Start reactor serve with or without BEND_WORKTREE
  if $use_worktree_env; then
    command="${command} && cd ${home} && BEND_WORKTREE=${workspace_name} NODE_ARGS=--max_old_space_size=8192 bend reactor serve --enable-tools --update --ts-watch --run-tests"
  else
    command="${command} && cd ${home} && NODE_ARGS=--max_old_space_size=8192 bend reactor serve --enable-tools --update --ts-watch --run-tests"
  fi

  # Add all paths to serve command
  for (( i=1; i<=$args; i++ )); do
    repo_spec=$@[$i]

    if [[ "$repo_spec" == *@* ]]; then
      repo="${repo_spec%@*}"
      worktree="${repo_spec#*@}"
      full_path=$(find_worktree_path "$repo" "$worktree")
      if [[ $? -ne 0 ]]; then
        echo "$full_path"
        return 1
      fi
    else
      repo="$repo_spec"
      full_path="${src}/${repo}"
    fi

    command="${command} ${full_path}"
  done

  eval $command
}
