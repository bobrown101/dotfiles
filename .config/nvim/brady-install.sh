#!/bin/bash
brew update 
brew upgrade
rm -rf ~/Developer/neovim
git clone https://github.com/neovim/neovim ~/Developer/neovim
cd ~/Developer/neovim
brew install libtool automake cmake pkg-config gettext
# brew install ninja libtool automake cmake pkg-config gettext
make CMAKE_EXTRA_FLAGS="-DCMAKE_INSTALL_PREFIX=$HOME/neovim" CMAKE_BUILD_TYPE=Release
make install
export PATH="$HOME/neovim/bin:$PATH"
nvim -c "PackerInstall"
nvim -c "PackerUpdate"
nvim -c "TSUpdate"
