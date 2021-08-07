#!/bin/bash
cd ~/Developer/neovim ## neovim source should be located here
nvm install node
npm install -g tree-sitter tree-sitter-cli neovim
git pull
sudo apt full-upgrade
sudo apt-get install ninja-build gettext libtool libtool-bin autoconf automake cmake g++ pkg-config unzip
make CMAKE_BUILD_TYPE=Release
sudo make install
rm -r build/  # clear the CMake cache
make CMAKE_EXTRA_FLAGS="-DCMAKE_INSTALL_PREFIX=$HOME/neovim"
make install
export PATH="$HOME/neovim/bin:$PATH"
