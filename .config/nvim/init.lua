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

-- noinsert: auto-highlights the first item in the menu (so hover fires immediately)
-- but doesn't insert its text until confirmed. noselect would require a manual
-- Tab press before anything is highlighted. fuzzy enables fuzzy matching.
-- popup is here but unused in practice — the hover doc below supersedes it.
vim.o.completeopt = "menu,menuone,noinsert,fuzzy,popup"

-- Replace the text kind labels (e.g. "Property") with Nerd Font icons.
-- vim.lsp.protocol.CompletionItemKind is a bidirectional map:
--   ["Method"] = 2  and  [2] = "Method"
-- Neovim reads the numeric->string direction when rendering the kind column,
-- so overwriting those entries is all that's needed — no plugin required.
do
    local icons = {
        Text = "󰉿", Method = "󰆧", Function = "󰊕", Constructor = "",
        Field = "󰜢", Variable = "󰀫", Class = "󰠱", Interface = "",
        Module = "", Property = "󰜢", Unit = "󰑭", Value = "󰎠",
        Enum = "", Keyword = "󰌋", Snippet = "", Color = "󰏘",
        File = "󰈙", Reference = "󰈇", Folder = "󰉋", EnumMember = "",
        Constant = "󰏿", Struct = "󰙅", Event = "", Operator = "󰆕",
        TypeParameter = "",
    }
    for kind, icon in pairs(icons) do
        local idx = vim.lsp.protocol.CompletionItemKind[kind]
        if idx then
            vim.lsp.protocol.CompletionItemKind[idx] = icon
        end
    end
end

vim.diagnostic.config({
    severity_sort = true,
    virtual_text = { prefix = "●" },
})

-- Neovim 0.11 native LSP completion — replaces the old nvim-cmp stack.
-- autotrigger fires completion automatically as you type (no manual invoke needed).
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
    end,
})

-- Tab/S-Tab navigate the completion menu; fall through to literal tab otherwise.
-- <C-Space> manually triggers completion via omnifunc (<C-x><C-o>).
vim.keymap.set("i", "<Tab>", function()
    return vim.fn.pumvisible() == 1 and "<C-n>" or "<Tab>"
end, { expr = true })
vim.keymap.set("i", "<S-Tab>", function()
    return vim.fn.pumvisible() == 1 and "<C-p>" or "<S-Tab>"
end, { expr = true })
vim.keymap.set("i", "<C-Space>", "<C-x><C-o>")

-- Hover doc alongside the completion menu.
--
-- The native completion popup only shows the item's `info` field, which LSP leaves
-- empty until a completionItem/resolve round-trip. Rather than wiring up resolve,
-- we fire a full textDocument/hover request on every selection change — this is the
-- same data K shows in normal mode.
--
-- Two-step render: open_floating_preview handles markdown/treesitter highlighting,
-- then nvim_win_set_config repositions the window to sit right of the pum.
-- We can't pass absolute row/col through vim.lsp.buf.hover() because the lsp utility
-- treats them as cursor-relative offsets, not editor-absolute coordinates.
--
-- The augroup (clear=true) ensures :source $MYVIMRC doesn't register duplicate autocmds.
local _hover_win = nil
local _hover_aug = vim.api.nvim_create_augroup("CompletionHover", { clear = true })
vim.api.nvim_create_autocmd("CompleteChanged", {
    group = _hover_aug,
    callback = function()
        local item = vim.v.completed_item
        if type(item) ~= "table" or (item.word or "") == "" then return end
        -- capture pum position synchronously before the async LSP request,
        -- since the pum may move or close by the time the response arrives
        local pum = vim.fn.pum_getpos()
        if vim.tbl_isempty(pum) then return end
        local bufnr = vim.api.nvim_get_current_buf()
        local params = vim.lsp.util.make_position_params()
        vim.lsp.buf_request(bufnr, "textDocument/hover", params, function(err, result)
            if _hover_win and vim.api.nvim_win_is_valid(_hover_win) then
                vim.api.nvim_win_close(_hover_win, true)
                _hover_win = nil
            end
            if err or not result or not result.contents then return end
            local lines = vim.lsp.util.convert_input_to_markdown_lines(result.contents)
            lines = vim.lsp.util.trim_empty_lines(lines)
            if not lines or #lines == 0 then return end
            local _, fwin = vim.lsp.util.open_floating_preview(lines, "markdown", {
                border = "rounded",
                focusable = false,
                max_width = 60,
            })
            _hover_win = fwin
            -- pum.col + pum.width lands at the right edge; +1 more if scrollbar is shown
            local col = pum.col + pum.width + (pum.scrollbar == 1 and 1 or 0)
            vim.api.nvim_win_set_config(fwin, {
                relative = "editor",
                anchor = "NW",
                row = pum.row,
                col = col,
            })
        end)
    end,
})
vim.api.nvim_create_autocmd("CompleteDone", {
    group = _hover_aug,
    callback = function()
        if _hover_win and vim.api.nvim_win_is_valid(_hover_win) then
            vim.api.nvim_win_close(_hover_win, true)
            _hover_win = nil
        end
    end,
})

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
