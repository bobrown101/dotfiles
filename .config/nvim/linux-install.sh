#!/bin/bash -ex
sudo apt update
sudo apt upgrade
rm -rf ~/neovim
rm -rf /usr/local/share/nvim/
rm -rf ~/Developer/neovim
git clone https://github.com/neovim/neovim ~/Developer/neovim
cd ~/Developer/neovim
curl -LO https://github.com/neovim/neovim/releases/latest/download/nvim-linux64.tar.gz
sudo rm -rf /opt/nvim
sudo tar -C /opt -xzf nvim-linux64.tar.gz
export PATH="$PATH:/opt/nvim-linux64/bin"
nvim --headless "+Lazy! sync" +qa
nvim -c "TSUpdate"
