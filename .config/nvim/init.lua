vim.g.mapleader = ' '
local execute = vim.api.nvim_command
local fn = vim.fn

local install_path = fn.stdpath('data')..'/site/pack/packer/start/packer.nvim'

if fn.empty(fn.glob(install_path)) > 0 then
  fn.system({'git', 'clone', 'https://github.com/wbthomason/packer.nvim', install_path})
  execute 'packadd packer.nvim'
end


require('packer').startup( function()
  use { 'bobrown101/git-blame.nvim' }
  use { 'wbthomason/packer.nvim'}
  use 'folke/tokyonight.nvim'
-- use {"npxbr/gruvbox.nvim", requires = {"rktjmp/lush.nvim"}}
  use { 'morhetz/gruvbox'}
  use { 'nvim-treesitter/nvim-treesitter'}
  use { 'neovim/nvim-lspconfig'}
  use { 'hrsh7th/nvim-compe'}
  use { 'glepnir/galaxyline.nvim'}
  use { 'kyazdani42/nvim-web-devicons'}
  use { 'b3nj5m1n/kommentary'}
  use { 'kyazdani42/nvim-tree.lua' }
  use { 'mhinz/vim-startify'}
  use { 'mhartington/formatter.nvim'}
  use { 'JoosepAlviste/nvim-ts-context-commentstring'}
  use { 'ray-x/lsp_signature.nvim'}
  use { 'onsails/lspkind-nvim'}
  use { 'nvim-lua/popup.nvim'}
  use { 'nvim-lua/plenary.nvim'}
  use { 'nvim-telescope/telescope.nvim'}
  use { 'nvim-telescope/telescope-fzy-native.nvim'}
  use { 'romgrk/barbar.nvim'}
  use { 'folke/lsp-colors.nvim'}
  use { 'folke/todo-comments.nvim'}
  use {"akinsho/nvim-toggleterm.lua"}
  use { 'jose-elias-alvarez/null-ls.nvim' }
end)

require('settings')
require('theme')
require('lsp')
require('asset-bender')
require('hubspot-js-utils')
require('null-ls-config')
require("toggleterm-config")
require("nvim-tree-config")
require('compe-config')
require('kommentary_config')
require('bubbles-line')
require('telescope-config')
require('treesitter-config')
require('todo-comments-config')
require('formatter-config')

