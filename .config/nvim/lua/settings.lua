vim.g.mapleader = " "
vim.g.noesckeys = true
vim.g.updatetime = 200
vim.g.noswapfile = true
vim.o.termguicolors = true
vim.opt.list = true
vim.opt.listchars = { space = "·" }
vim.opt.scrolloff = 8
-- vim.o.colorcolumn = 80
-- vim.o.signcolumn = yes
vim.o.hidden = true
vim.wo.wrap = false
vim.o.encoding = "utf-8"
vim.o.fileencoding = "utf-8"
vim.o.ruler = true
vim.o.cmdheight = 0
vim.o.mouse = "a"
vim.o.splitbelow = true
vim.o.splitright = true
vim.o.conceallevel = 0
vim.o.tabstop = 2
vim.o.shiftwidth = 2
vim.o.smarttab = true
vim.o.expandtab = true
vim.o.smartindent = true
vim.o.autoindent = true
vim.o.number = true
vim.o.relativenumber = true
vim.o.cursorline = true
vim.g.nobackup = true
vim.g.nowritebackup = true
vim.o.timeoutlen = 500
vim.o.ttimeoutlen = 50
vim.o.clipboard = "unnamedplus"
vim.o.laststatus = 3 -- have a single global statusline, rather than one for every window
vim.o.winbar = "%=%m %f"

-- " Use leader and hjkl to navigate windows
vim.api.nvim_set_keymap("n", "<leader>h", "<cmd> wincmd h <CR>", { noremap = true, silent = true })
vim.api.nvim_set_keymap("n", "<leader>j", "<cmd> wincmd j <CR>", { noremap = true, silent = true })
vim.api.nvim_set_keymap("n", "<leader>k", "<cmd> wincmd k <CR>", { noremap = true, silent = true })
vim.api.nvim_set_keymap("n", "<leader>l", "<cmd> wincmd l <CR>", { noremap = true, silent = true })

-- " disable arrow keys
vim.api.nvim_set_keymap("n", "<Up>", "<nop>", { noremap = true, silent = true })
vim.api.nvim_set_keymap("n", "<Down>", "<nop>", { noremap = true, silent = true })
vim.api.nvim_set_keymap("n", "<Left>", "<nop>", { noremap = true, silent = true })
vim.api.nvim_set_keymap("n", "<Right>", "<nop>", { noremap = true, silent = true })

vim.api.nvim_set_keymap(
	"n",
	"<leader>_",
	"<cmd> lua vim.api.nvim_win_set_width(vim.api.nvim_get_current_win(), vim.api.nvim_win_get_width(vim.api.nvim_get_current_win()) - 5)<CR>",
	{ noremap = true, silent = true }
)

vim.api.nvim_set_keymap(
	"n",
	"<leader>+",
	"<cmd> lua vim.api.nvim_win_set_width(vim.api.nvim_get_current_win(), vim.api.nvim_win_get_width(vim.api.nvim_get_current_win()) + 5)<CR>",
	{ noremap = true, silent = true }
)

-- disable unused builtin plugins
vim.g.loaded_gzip = 1
vim.g.loaded_zip = 1
vim.g.loaded_zipPlugin = 1
vim.g.loaded_tar = 1
vim.g.loaded_tarPlugin = 1

vim.g.loaded_getscript = 1
vim.g.loaded_getscriptPlugin = 1
vim.g.loaded_vimball = 1
vim.g.loaded_vimballPlugin = 1
vim.g.loaded_2html_plugin = 1

vim.g.loaded_matchit = 1
vim.g.loaded_matchparen = 1
vim.g.loaded_logiPat = 1
vim.g.loaded_rrhelper = 1

vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1
vim.g.loaded_netrwSettings = 1
