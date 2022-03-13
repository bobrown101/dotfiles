vim.g.mapleader = ' '
vim.o.termguicolors = true
vim.opt.list = true
vim.opt.listchars = {space = '·'}
vim.opt.scrolloff = 8
-- vim.o.colorcolumn = 80
-- vim.o.signcolumn = yes
vim.o.hidden = true
vim.wo.wrap = false
vim.o.encoding = 'utf-8'
vim.o.fileencoding = 'utf-8'
vim.o.ruler = true
vim.o.cmdheight = 2
vim.o.mouse = 'a'
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
vim.o.background = 'light'
vim.g.nobackup = true
vim.g.nowritebackup = true
vim.o.updatetime = 200
vim.o.timeoutlen = 500
vim.o.clipboard = 'unnamedplus'

-- vim.api.nvim_set_keymap("n", "<tab>",
-- ":if &modifiable && !&readonly && &modified <CR> :write<CR> :endif<CR>:bnext<CR>",
-- {noremap = true, silent = true})

-- vim.api.nvim_set_keymap("n", "<s-tab>",
-- ":if &modifiable && !&readonly && &modified <CR> :write<CR> :endif<CR>:bprevious<CR>",
-- {noremap = true, silent = true})

-- vim.api.nvim_set_keymap("n", "<tab>",
--                         "<cmd> lua require'telescope.builtin'.buffers(require('telescope.themes').get_dropdown({ })) <CR>",
--                         {noremap = true, silent = true})

-- " Use leader and hjkl to navigate windows
vim.api.nvim_set_keymap("n", "<leader>h", "<cmd> wincmd h <CR>",
                        {noremap = true, silent = true})
vim.api.nvim_set_keymap("n", "<leader>j", "<cmd> wincmd j <CR>",
                        {noremap = true, silent = true})
vim.api.nvim_set_keymap("n", "<leader>k", "<cmd> wincmd k <CR>",
                        {noremap = true, silent = true})
vim.api.nvim_set_keymap("n", "<leader>l", "<cmd> wincmd l <CR>",
                        {noremap = true, silent = true})

-- " disable arrow keys
vim.api.nvim_set_keymap("n", "<Up>", "<nop>", {noremap = true, silent = true})
vim.api.nvim_set_keymap("n", "<Down>", "<nop>", {noremap = true, silent = true})
vim.api.nvim_set_keymap("n", "<Left>", "<nop>", {noremap = true, silent = true})
vim.api
    .nvim_set_keymap("n", "<Right>", "<nop>", {noremap = true, silent = true})

vim.api.nvim_set_keymap("n", "_",
                        "<cmd> lua vim.api.nvim_win_set_width(vim.api.nvim_get_current_win(), vim.api.nvim_win_get_width(vim.api.nvim_get_current_win()) - 5)<CR>",
                        {noremap = true, silent = true})

vim.api.nvim_set_keymap("n", "+",
                        "<cmd> lua vim.api.nvim_win_set_width(vim.api.nvim_get_current_win(), vim.api.nvim_win_get_width(vim.api.nvim_get_current_win()) + 5)<CR>",
                        {noremap = true, silent = true})

-- vim.api.nvim_set_keymap("n", "-", ":lua require('tools').FileExplorer()<CR>", {noremap = true, silent = true})
vim.api.nvim_set_keymap("n", "-",
                        ":lua require('nnn').toggle('picker', '%:p:h')<CR>", -- the second arg is to represent "open in the current directory"
                        {noremap = true, silent = true})
