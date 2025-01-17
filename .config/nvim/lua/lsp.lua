local log = require("vim.lsp.log")
local Job = require("plenary.job")
local find_node_modules_ancestor = require("lspconfig").util.find_node_modules_ancestor
local path_join = require("lspconfig").util.path.join
local getTsServerPathForCurrentFile = require("asset-bender").getTsServerPathForCurrentFile
local check_start_javascript_lsp = require("asset-bender").check_start_javascript_lsp

require("neodev").setup({})
require("lspconfig").lua_ls.setup({})

local tsserverpath = getTsServerPathForCurrentFile()

print("Initializing lsp with tsserver version found from package.json:" .. tsserverpath)

require("typescript-tools").setup({
    settings = {
        separate_diagnostic_server = true,
        publish_diagnostic_on = "insert_leave",
        expose_as_code_action = {},
        tsserver_path = tsserverpath,
        tsserver_logs = "terse",
        -- specify a list of plugins to load by tsserver, e.g., for support `styled-components`
        -- (see 💅 `styled-components` support section)
        tsserver_plugins = {},
        tsserver_max_memory = "auto",
        tsserver_format_options = {},
        tsserver_file_preferences = {},
        complete_function_calls = false,
        include_completions_with_insert_text = true,
        disable_member_code_lens = true,
    },
    handlers = {
        ["textDocument/signatureHelp"] = vim.lsp.with(vim.lsp.handlers.signature_help, { border = "single" }),
        ["textDocument/hover"] = vim.lsp.with(vim.lsp.handlers.hover, { border = "single" }),
    },
    on_attach = function()
        print("lsp attached")
        local tsserverVersionForThisFile = getTsServerPathForCurrentFile()

        check_start_javascript_lsp()

        if tsserverVersionForThisFile ~= tsserverpath then
            vim.notify(
                "You opened a file that requires a different tsserver version than what is currently being used The file wants :"
                    .. tsserverVersionForThisFile
                    .. " and the current version is "
                    .. tsserverpath
            )
        end
    end,
})

-- FAQ
-- [ERROR][2022-02-22 11:10:04] ...lsp/handlers.lua:454 "[tsserver] /bin/sh: /usr/local/Cellar/node/17.5.0/bin/npm: No such file or directory\n"
--    ln -s (which npm) /usr/local/Cellar/node/17.5.0/bin/npm
--
--
-- vim.lsp.handlers["textDocument/signatureHelp"] = vim.lsp.with(vim.lsp.handlers.signature_help, { border = "single" })
--
-- vim.lsp.handlers["textDocument/hover"] = vim.lsp.with(vim.lsp.handlers.hover, { border = "single" })

vim.api.nvim_set_keymap("n", "<space>gd", "<cmd>lua vim.lsp.buf.definition()<CR>", { noremap = true, silent = true })
vim.api.nvim_set_keymap(
    "n",
    "<space>gi",
    "<cmd>lua vim.lsp.buf.implementation()<CR>",
    { noremap = true, silent = true }
)
vim.api.nvim_set_keymap("n", "<space>gr", "<cmd>lua vim.lsp.buf.references()<CR>", { noremap = true, silent = true })
vim.api.nvim_set_keymap("n", "<space>rn", "<cmd>lua vim.lsp.buf.rename()<CR>", { noremap = true, silent = true })
vim.api.nvim_set_keymap("n", "K", "<cmd>lua vim.lsp.buf.hover()<CR>", { noremap = true, silent = true })
vim.api.nvim_set_keymap("n", "<space>ga", "<cmd>Lspsaga code_action<CR>", { noremap = true, silent = true })
-- vim.api.nvim_set_keymap("n", "<space>ga", "<cmd>lua vim.lsp.buf.code_action()<CR>", { noremap = true, silent = true })
vim.api.nvim_set_keymap(
    "n",
    "<space>gsd",
    "<cmd>lua vim.lsp.buf.show_line_diagnostics({ focusable = false })<CR>",
    { noremap = true, silent = true }
)
