vim.cmd('syntax enable')
vim.o.termguicolors = true

-- vim.o.background = 'light'
-- vim.g.tokyonight_style = "day"
vim.g.tokyonight_style = "day"
vim.g.tokyonight_italic_functions = true
vim.g.tokyonight_sidebars = {
    "qf", "vista_kind", "terminal", "packer", "TelescopePrompt"
}

-- -- Change the "hint" color to the "orange" color, and make the "error" color bright red
-- vim.g.tokyonight_colors = {hint = "orange", error = "#ff0000"}

-- Load the colorscheme
vim.cmd [[colorscheme tokyonight]]

