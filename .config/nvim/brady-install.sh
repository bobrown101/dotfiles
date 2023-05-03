#!/bin/bash -ex
brew update 
brew upgrade
rm -rf ~/neovim
rm -rf /usr/local/share/nvim/
rm -rf ~/Developer/neovim
git clone https://github.com/neovim/neovim ~/Developer/neovim
cd ~/Developer/neovim
#brew uninstall luarocks
brew install libtool automake cmake pkg-config gettext
#make CMAKE_INSTALL_PREFIX=$HOME/neovim
make CMAKE_BUILD_TYPE=RelWithDebInfo
make install
export PATH="$HOME/neovim/bin:$PATH"
nvim --headless "+Lazy! sync" +qa
nvim -c "TSUpdate"
