vim.g.mapleader = " "

vim.pack.add({
    -- Theme (load first so colors apply everywhere)
    "https://github.com/folke/tokyonight.nvim",

    -- Core libs (deps for many others)
    "https://github.com/nvim-lua/plenary.nvim",
    "https://github.com/nvim-tree/nvim-web-devicons",

    -- Treesitter (dep for lspsaga, ts-comments)
    { src = "https://github.com/nvim-treesitter/nvim-treesitter", version = "main" },

    -- UI
    "https://github.com/stevearc/oil.nvim",
    "https://github.com/nvim-lualine/lualine.nvim",
    "https://github.com/goolord/alpha-nvim",
    "https://github.com/folke/which-key.nvim",
    "https://github.com/nvim-telescope/telescope.nvim",
    "https://github.com/folke/todo-comments.nvim",
    "https://github.com/folke/ts-comments.nvim",

    -- Git
    "https://github.com/lewis6991/gitsigns.nvim",
    "https://github.com/FabijanZulj/blame.nvim",

    -- LSP
    "https://github.com/neovim/nvim-lspconfig",
    { src = "https://github.com/j-hui/fidget.nvim", version = "legacy" },
    "https://github.com/nvimdev/lspsaga.nvim",

    -- Completion
    "https://github.com/hrsh7th/nvim-cmp",
    "https://github.com/hrsh7th/cmp-nvim-lsp",
    "https://github.com/hrsh7th/cmp-nvim-lua",
    "https://github.com/hrsh7th/cmp-buffer",
    "https://github.com/onsails/lspkind-nvim",

    -- Formatting
    "https://github.com/stevearc/conform.nvim",

    -- HubSpot
    "https://github.com/bobrown101/plugin-utils.nvim",
    "https://github.com/bobrown101/hubspot-js-utils.nvim",
    "https://github.com/HubSpotEngineering/bend.nvim",
    "https://github.com/pmizio/typescript-tools.nvim",
})

require("tokyonight").setup({
    style = "day",
    transparent = false,
    terminal_colors = true,
    on_highlights = function(highlights, colors)
        highlights.WinSeparator = { fg = colors.border_highlight, bg = colors.border_highlight }
        highlights.CursorLine = { bg = "#ffe6e6" }
        highlights.Cursor = { bg = "#cc6666", fg = "#ffffff" }
    end,
})
vim.cmd.colorscheme("tokyonight")

require("oil").setup({
    view_options = { show_hidden = true },
})

require("fidget").setup({})

require("which-key").add({
    { "<leader>d", group = "Diagnostics" },
    { "<leader>dd", vim.diagnostic.open_float, desc = "Open diagnostic float" },
    { "<leader>f", group = "file" },
    {
        "<leader>ff",
        function()
            require("telescope.builtin").find_files({
                layout_config = { height = 0.9, width = 0.9 },
                hidden = true,
            })
        end,
        desc = "Find File",
    },
    { "<leader>gb", "<cmd>BlameToggle<cr>", desc = "Git Blame" },
    {
        "<leader>gt",
        function() require("hubspot-js-utils").test_file() end,
        desc = "Test File",
    },
    { "<leader>s", group = "Search" },
    { "<leader>sh", "<cmd>split<cr>", desc = "Split Horizontal" },
    {
        "<leader>ss",
        function()
            require("telescope.builtin").live_grep({ layout_config = { height = 0.9, width = 0.9 } })
        end,
        desc = "Search String",
    },
    { "<leader>sv", "<cmd>vsplit<cr>", desc = "Split Vertical" },
    {
        mode = "n",
        {
            "_",
            function()
                vim.cmd("term ")
                vim.cmd("startinsert")
            end,
            desc = "Terminal",
        },
        { "-", "<cmd>Oil<cr>", desc = "File browser" },
        {
            "<tab>",
            function()
                require("telescope.builtin").buffers(require("telescope.themes").get_dropdown({
                    sort_lastused = true,
                    layout_config = { height = 0.3, width = 0.9 },
                }))
            end,
            desc = "open up buffers list",
        },
    },
    {
        mode = "t",
        { "<esc><esc>", "<cmd>stopinsert<cr>", desc = "Escape terminal insert mode" },
    },
})

require("hubspot-js-utils").setup({})

require("blame").setup({
    mappings = {
        commit_info = "K",
        stack_push = "l",
        stack_pop = "h",
        show_commit = "<CR>",
        close = { "<esc>", "q" },
    },
})

require("gitsigns").setup()

require("nvim-treesitter").install({
    "bash", "c", "css", "fish", "html", "java", "javascript", "json",
    "lua", "markdown", "markdown_inline", "python", "query", "regex",
    "tsx", "typescript", "vim", "vimdoc", "yaml",
})
vim.api.nvim_create_autocmd("FileType", {
    pattern = {
        "bash", "c", "css", "fish", "html", "java", "javascript",
        "javascriptreact", "json", "lua", "markdown", "python",
        "typescript", "typescriptreact", "vim", "yaml",
    },
    callback = function() pcall(vim.treesitter.start) end,
})

local cmp = require("cmp")
local lspkind = require("lspkind")
cmp.setup({
    snippet = { expand = function() end },
    mapping = {
        ["<Tab>"] = function(fallback)
            if cmp.visible() then
                cmp.select_next_item()
            else
                fallback()
            end
        end,
        ["<S-Tab>"] = function(fallback)
            if cmp.visible() then
                cmp.select_prev_item()
            else
                fallback()
            end
        end,
        ["<C-Space>"] = cmp.mapping(cmp.mapping.complete(), { "i", "s" }),
        ["<CR>"] = cmp.mapping(cmp.mapping.confirm({ select = true }), { "i", "s" }),
    },
    sources = {
        { name = "path" },
        { name = "nvim_lsp" },
        { name = "buffer" },
        { name = "nvim_lua" },
        { name = "treesitter" },
    },
    formatting = {
        format = function(entry, vim_item)
            vim_item.kind = lspkind.presets.default[vim_item.kind] .. " " .. vim_item.kind
            vim_item.menu = ({
                buffer = "[Buffer]",
                nvim_lsp = "[LSP]",
                nvim_lua = "[Lua]",
                latex_symbols = "[Latex]",
                nvim_cmp_hs_translation_source = "[Translation]",
            })[entry.source.name]
            return vim_item
        end,
    },
})

require("lspsaga").setup({
    code_action = {
        extend_gitsigns = true,
        num_shortcut = true,
        keys = { quit = "<esc>", exec = "<CR>" },
    },
    symbol_in_winbar = { enable = false },
})

require("lualine").setup({
    options = {
        theme = "onedark",
        component_separators = "|",
        section_separators = { left = "", right = "" },
    },
    sections = {
        lualine_a = { { "mode", separator = { left = "" }, right_padding = 2 } },
        lualine_b = { function() return vim.fn.expand("%:~:.") end, "branch" },
        lualine_x = {},
        lualine_y = { "filetype", "diff", "progress" },
        lualine_z = { { "location", separator = { right = "" }, left_padding = 2 } },
    },
    inactive_sections = {
        lualine_a = { "filename" },
        lualine_b = {},
        lualine_c = {},
        lualine_x = {},
        lualine_y = {},
        lualine_z = { "location" },
    },
    tabline = {},
    extensions = {},
})

require("ts-comments").setup({})

require("alpha").setup(require("alpha.themes.startify").config)

require("telescope").setup({
    defaults = { wrap_results = true },
})

require("todo-comments").setup({})

-- bend.nvim MUST be set up before typescript-tools
local bend = require("bend")
bend.setup({ v2 = true })
require("typescript-tools").setup({
    settings = {
        tsserver_path = bend.getTsServerPathForCurrentFile(),
    },
})
vim.keymap.set("n", "<space>gd", vim.lsp.buf.definition, { silent = true })

require("conform").formatters.stylua = {
    prepend_args = { "--indent-type", "spaces" },
}
local frontendSetup = { "prettier" }
require("conform").setup({
    format_on_save = {
        timeout_ms = 2500,
        lsp_fallback = true,
    },
    formatters_by_ft = {
        lua = { "stylua" },
        javascript = frontendSetup,
        typescript = frontendSetup,
        typescriptreact = frontendSetup,
        javascriptreact = frontendSetup,
    },
})

vim.api.nvim_create_user_command("ClaudeFile", function()
    local file_path = vim.fn.expand("%:p")
    local cmd = "claude " .. vim.fn.shellescape("I am looking at file: " .. file_path)
    vim.cmd("vsplit")
    vim.cmd("terminal " .. cmd)
    vim.cmd("startinsert")
end, {})

vim.api.nvim_create_user_command("ClaudeLines", function()
    local start_line = vim.fn.line("'<")
    local end_line = vim.fn.line("'>")
    local file_path = vim.fn.expand("%:p")
    local msg = "I am looking at file: " .. file_path .. ", from line " .. start_line .. " to line " .. end_line
    local cmd = "claude " .. vim.fn.shellescape(msg)
    vim.cmd("vsplit")
    vim.cmd("terminal " .. cmd)
    vim.cmd("startinsert")
end, { range = true })

require("settings")
