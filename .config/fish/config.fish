
# -gx means `--global` `--export` - a globally exported enviornment variable

set -q XDG_CACHE_HOME; or set XDG_CACHE_HOME $HOME/.cache


set -gx NPM_PATH (which npm)
set -gx EDITOR nvim


function ll
	eza -al $argv
end

function v
  nvim $argv
end

function t
  tmuxinator $argv
end


switch (uname)
    case Linux
      echo Hello bradys non-work-pc
	    
	    set PATH /opt/nvim-linux64/bin $PATH
    case Darwin
      echo Hello bradys work pc

      set PATH /usr/local/bin $PATH
	    set PATH /usr/sbin $PATH
	    set PATH $HOME/neovim/bin $PATH
	    set PATH $HOME/.yarn/bin $PATH
	    set PATH $HOME/.config/yarn/global/node_modules/.bin $PATH
	    set PATH $HOME/.cargo/bin $PATH
	    set PATH $HOME/Developer/alacritty/target/release $PATH
	    set -gx TSSERVER_PATH (bpx --path hs-typescript)
	    set -gx NODE_ARGS --max_old_space_size=8192
	    
	    function pretty
	        bend hs-prettier --write (git diff --name-only --cached) && git add (git diff --name-only --cached)
	    end
    case '*'
            echo ERR - your fish config did not recognize the OS type
end

#. ~/.hubspot/shellrc

