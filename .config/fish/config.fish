set PATH /usr/local/bin $PATH
set PATH /usr/sbin $PATH
set PATH $HOME/neovim/bin $PATH
set PATH $HOME/.yarn/bin $PATH
set PATH $HOME/.config/yarn/global/node_modules/.bin $PATH

set EDITOR nvim

set NODE_ARGS --max_old_space_size=8192
set IS_HUBSPOT_MACHINE "yes"

function brewup
  brew update; brew upgrade; brew cleanup; brew doctor
end

function ll
	ls -al $argv
end

function v
  nvim $argv
end

function t
  tmuxinator $argv
end

function pretty
  bpx hs-prettier --write (git diff --name-only --cached) && git add (git diff --name-only --cached)
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
