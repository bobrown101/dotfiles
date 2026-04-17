vim.g.mapleader = " "

vim.pack.add({
    -- Theme (load first so colors apply everywhere)
    "https://github.com/folke/tokyonight.nvim",

    -- Core libs (deps for many others)
    "https://github.com/nvim-lua/plenary.nvim",
    "https://github.com/nvim-tree/nvim-web-devicons",

    -- Treesitter (dep for ts-comments)
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

    -- LSP
    { src = "https://github.com/j-hui/fidget.nvim", version = "legacy" },

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
    { "<leader>gb", "<cmd>Gitsigns blame<cr>", desc = "Git Blame" },
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

require("gitsigns").setup({
    current_line_blame = true,
    current_line_blame_opts = { delay = 500 },
})

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

vim.o.completeopt = "menu,menuone,noselect,fuzzy,popup"
vim.diagnostic.config({
    severity_sort = true,
    virtual_text = { prefix = "●" },
})
vim.api.nvim_create_autocmd("LspAttach", {
    callback = function(ev)
        local client = vim.lsp.get_client_by_id(ev.data.client_id)
        if not client then return end
        if client:supports_method("textDocument/completion") then
            vim.lsp.completion.enable(true, client.id, ev.buf, { autotrigger = true })
        end
        if client:supports_method("textDocument/inlayHint") then
            vim.lsp.inlay_hint.enable(true, { bufnr = ev.buf })
        end
        if client:supports_method("textDocument/foldingRange") then
            vim.wo[0][0].foldexpr = "v:lua.vim.lsp.foldexpr()"
            vim.wo[0][0].foldmethod = "expr"
        end
    end,
})
vim.keymap.set("i", "<Tab>", function()
    return vim.fn.pumvisible() == 1 and "<C-n>" or "<Tab>"
end, { expr = true })
vim.keymap.set("i", "<S-Tab>", function()
    return vim.fn.pumvisible() == 1 and "<C-p>" or "<S-Tab>"
end, { expr = true })

require("lualine").setup({
    options = {
        theme = "auto",
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
        lsp_format = "fallback",
    },
    formatters_by_ft = {
        lua = { "stylua" },
        javascript = frontendSetup,
        typescript = frontendSetup,
        typescriptreact = frontendSetup,
        javascriptreact = frontendSetup,
    },
})

vim.api.nvim_create_user_command("PackUpdate", function() vim.pack.update() end, {})

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
