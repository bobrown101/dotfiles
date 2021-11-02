set PATH /usr/local/bin $PATH
set PATH /usr/sbin $PATH
set PATH $HOME/neovim/bin $PATH
set PATH $HOME/.yarn/bin $PATH
set PATH $HOME/.config/yarn/global/node_modules/.bin $PATH

set EDITOR nvim


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
  bpx hs-prettier --write (git diff --name-only --cached)
end

#. ~/.hubspot/shellrc



