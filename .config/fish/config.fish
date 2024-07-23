set PATH /usr/local/bin $PATH
set PATH /usr/sbin $PATH
set PATH $HOME/neovim/bin $PATH
set PATH $HOME/.yarn/bin $PATH
set PATH $HOME/.config/yarn/global/node_modules/.bin $PATH
set PATH $HOME/.cargo/bin $PATH
set PATH $HOME/Developer/alacritty/target/release $PATH
set PATH $HOME/.local/share/bob/nvim-bin $PATH

# -gx means `--global` `--export` - a globally exported enviornment variable

set -q XDG_CACHE_HOME; or set XDG_CACHE_HOME $HOME/.cache

set -gx TSSERVER_PATH (bpx --path hs-typescript)
#set -gx TSSERVER_PATH "/Users/brbrown/.bpm/packages/hs-typescript/static-1-pinned-09-2023.1/"

set -gx NPM_PATH (which npm)
set -gx EDITOR nvim

set -gx NODE_ARGS --max_old_space_size=8192

function brewup
  brew update; brew upgrade; brew cleanup; brew doctor
end

function ll
	exa -al $argv
end

function f
    fff $argv
    set -q XDG_CACHE_HOME; or set XDG_CACHE_HOME $HOME/.cache
    cd (cat $XDG_CACHE_HOME/fff/.fff_d)
end

function v
  nvim $argv
end

function mm
 qmv --editor=nvim --format=destination-only -a $argv
end

function t
  tmuxinator $argv
end

function pretty
  bend hs-prettier --write (git diff --name-only --cached) && git add (git diff --name-only --cached)
end

function gr
  set -lx TOPLEVEL (git rev-parse --show-toplevel 2> /dev/null)
    if test $status -eq 0
      cd $TOPLEVEL
  end
end

# will require "brew install coreutils"
function open_location_of
  open (dirname (greadlink -f (which $argv)))
end

#. ~/.hubspot/shellrc


# this will take the install paths of luarocks and add them to fishs path
# installation docs https://github.com/luarocks/luarocks/wiki/Installation-instructions-for-Unix
# https://github.com/Koihik/LuaFormatter
#for i in (luarocks path | awk '{sub(/PATH=/, "PATH ", $2); print "set -gx "$2}'); eval $i; end
