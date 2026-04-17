vim.o.updatetime = 200
vim.o.swapfile = false
vim.opt.list = true
vim.opt.listchars = { space = "·" }
vim.opt.scrolloff = 8
vim.o.signcolumn = "yes"
vim.o.wrap = false
vim.o.splitbelow = true
vim.o.splitright = true
vim.o.conceallevel = 0
vim.o.tabstop = 2
vim.o.shiftwidth = 2
vim.o.expandtab = true
vim.o.number = true
vim.o.relativenumber = true
vim.o.cursorline = true
-- guicursor configures cursor shape and appearance for different modes:
-- - n-v-c:block = normal/visual/command modes use block cursor
-- - i-ci-ve:ver25 = insert modes use vertical bar (25% width)
-- - The "Cursor/lCursor" part tells Neovim to use the Cursor highlight group
--   which we define in init.lua with custom colors (dark red background)
vim.o.guicursor = "n-v-c:block,i-ci-ve:ver25,r-cr:hor20,o:hor50,a:blinkwait700-blinkoff400-blinkon250-Cursor/lCursor,sm:block-blinkwait175-blinkoff150-blinkon175"
vim.o.backup = false
vim.o.writebackup = false
vim.o.timeoutlen = 500
vim.o.ttimeoutlen = 50
vim.o.clipboard = "unnamedplus"
vim.o.winbar = "%=%m %f"
vim.o.winborder = "single"

-- Use leader and hjkl to navigate windows
vim.keymap.set("n", "<leader>h", "<cmd>wincmd h<cr>", { silent = true })
vim.keymap.set("n", "<leader>j", "<cmd>wincmd j<cr>", { silent = true })
vim.keymap.set("n", "<leader>k", "<cmd>wincmd k<cr>", { silent = true })
vim.keymap.set("n", "<leader>l", "<cmd>wincmd l<cr>", { silent = true })

-- disable arrow keys
vim.keymap.set("n", "<Up>", "<nop>", { silent = true })
vim.keymap.set("n", "<Down>", "<nop>", { silent = true })
vim.keymap.set("n", "<Left>", "<nop>", { silent = true })
vim.keymap.set("n", "<Right>", "<nop>", { silent = true })

local function resize_width(delta)
	local win = vim.api.nvim_get_current_win()
	vim.api.nvim_win_set_width(win, vim.api.nvim_win_get_width(win) + delta)
end
vim.keymap.set("n", "<leader>_", function() resize_width(-5) end, { silent = true })
vim.keymap.set("n", "<leader>+", function() resize_width(5) end, { silent = true })

-- matchparen is load-bearing-ish; disabling skips the highlight-matching-bracket feature
vim.g.loaded_matchparen = 1
vim.g.loaded_matchit = 1
