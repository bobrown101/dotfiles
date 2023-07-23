#!/bin/bash
# cleanup
rm -rf ~/neovim
rm -rf ~/Developer/neovim
rm -rf ~/.local/share/nvim
rm -rf ~/.local/state/nvim
rm -rf /usr/local/share/nvim
rm -rf /usr/local/bin/nvim
rm -rf /usr/local/lib/nvim

cargo install bob-nvim

bob use nightly
bob complete fish > ~/.config/fish/completions/bob.fish


# clone neovim source
#git clone https://github.com/neovim/neovim ~/Developer/neovim
#cd ~/Developer/neovim ## neovim source should be located here

# update node
#nvm install node
#npm install -g tree-sitter tree-sitter-cli neovim

# update system and neovim build deps
#sudo apt full-upgrade
#sudo apt-get install ninja-build gettext libtool libtool-bin autoconf automake cmake g++ pkg-config unzip

#make CMAKE_BUILD_TYPE=RelWithDebInfo
#make install

#export PATH="$HOME/neovim/bin:$PATH"
export PATH=".local/share/bob/nvim-bin:$PATH"
nvim --headless "+Lazy! sync" +qa
nvim -c "TSUpdate"
