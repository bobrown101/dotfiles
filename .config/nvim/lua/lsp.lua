local util = require("lspconfig/util")
local Job = require("plenary.job")

function getLogPath() return vim.lsp.get_log_path() end

function getTsserverPath()
    local result = "/lib/tsserver.js"
    Job:new({
        command = "bpx",
        args = {"--path", "hs-typescript"},
        on_exit = function(j, return_val)
            local path = j:result()[1]
            result = path .. result
        end
    }):sync()

    return result
end

--[[ local function organize_imports()
    local params = {
        command = "_typescript.organizeImports",
        arguments = {vim.api.nvim_buf_get_name(0)},
        title = ""
    }
    vim.lsp.buf.execute_command(params)
end ]]

local on_attach = function(client, bufnr)
    -- local function buf_set_keymap(...)
    --     vim.api.nvim_buf_set_keymap(bufnr, ...)
    -- end
    -- local function buf_set_option(...)
    --     vim.api.nvim_buf_set_option(bufnr, ...)
    -- end
    --
    -- buf_set_keymap("n", "<space>gd", "<cmd>lua vim.lsp.buf.definition()<CR>",
    --                {noremap = true, silent = true})
    -- buf_set_keymap("n", "<space>gi",
    --                "<cmd>lua vim.lsp.buf.implementation()<CR>",
    --                {noremap = true, silent = true})
    -- buf_set_keymap("n", "<space>gr", "<cmd>lua vim.lsp.buf.references()<CR>",
    --                {noremap = true, silent = true})
    -- buf_set_keymap("n", "<space>rn", "<cmd>lua vim.lsp.buf.rename()<CR>",
    --                {noremap = true, silent = true})
    -- buf_set_keymap("n", "K", "<cmd>lua vim.lsp.buf.hover()<CR>",
    --                {noremap = true, silent = true})
    -- buf_set_keymap("n", "<space>ga", "<cmd>lua vim.lsp.buf.code_action()<CR>",
    --                {noremap = true, silent = true})
    -- buf_set_keymap("n", "<space>gsd",
    --                "<cmd>lua vim.lsp.buf.show_line_diagnostics({ focusable = false })<CR>",
    --                {noremap = true, silent = true})
end

-- The nvim-cmp almost supports LSP's capabilities so You should advertise it to LSP servers..
local capabilities = vim.lsp.protocol.make_client_capabilities()
capabilities = require('cmp_nvim_lsp').update_capabilities(capabilities)

local customPublishDiagnosticFunction = function(_, result, ctx, config)
    local filter = function(fun, t)
        local res = {}
        for _, item in ipairs(t) do
            if fun(item) then res[#res + 1] = item end
        end

        return res
    end
    local raw_diagnostics = result.diagnostics

    local filtered_diagnostics = filter(function(diagnostic)
        local diagnostic_code = diagnostic.code
        local diagnostic_source = diagnostic.source
        return not (diagnostic_code == 7016 and diagnostic_source ==
                   "typescript")
    end, raw_diagnostics)

    result.diagnostics = filtered_diagnostics

    return vim.lsp.diagnostic.on_publish_diagnostics(_, result, ctx, config)
end

require("lspconfig").tsserver.setup({
    cmd = {
        "typescript-language-server", "--log-level", -- A number indicating the log level (4 = log, 3 = info, 2 = warn, 1 = error). Defaults to `2`.
        "2", "--tsserver-log-verbosity", "terse", -- Specify tsserver log verbosity (off, terse, normal, verbose). Defaults to `normal`. example: --tsserver-log-verbosity=verbose
        "--tsserver-log-file", getLogPath(), "--tsserver-path",
        getTsserverPath(), "--stdio"
    },
    on_attach = on_attach,
    root_dir = util.root_pattern(".git"),
    filetypes = {
        "javascript", "javascriptreact", "javascript.jsx", "typescript",
        "typescriptreact", "typescript.tsx"
    },
    handlers = {
        ["textDocument/publishDiagnostics"] = vim.lsp.with(
            customPublishDiagnosticFunction, {
                -- Disable virtual_text
                -- virtual_text = false
            })
    },
    capabilities = capabilities

})

-- npm install -g graphql-language-service-cli
require'lspconfig'.graphql.setup {}

-- yarn global add yaml-language-server
require'lspconfig'.yamlls.setup {}
require("lspkind").init({})

vim.lsp.handlers['textDocument/signatureHelp'] =
    vim.lsp.with(vim.lsp.handlers.signature_help, {border = 'single'})

vim.lsp.handlers['textDocument/hover'] =
    vim.lsp.with(vim.lsp.handlers.hover, {border = 'single'})

vim.api.nvim_set_keymap("n", "<space>gd",
                        "<cmd>lua vim.lsp.buf.definition()<CR>",
                        {noremap = true, silent = true})
vim.api.nvim_set_keymap("n", "<space>gi",
                        "<cmd>lua vim.lsp.buf.implementation()<CR>",
                        {noremap = true, silent = true})
vim.api.nvim_set_keymap("n", "<space>gr",
                        "<cmd>lua vim.lsp.buf.references()<CR>",
                        {noremap = true, silent = true})
vim.api.nvim_set_keymap("n", "<space>rn", "<cmd>lua vim.lsp.buf.rename()<CR>",
                        {noremap = true, silent = true})
vim.api.nvim_set_keymap("n", "K", "<cmd>lua vim.lsp.buf.hover()<CR>",
                        {noremap = true, silent = true})
vim.api.nvim_set_keymap("n", "<space>ga",
                        "<cmd>lua vim.lsp.buf.code_action()<CR>",
                        {noremap = true, silent = true})
vim.api.nvim_set_keymap("n", "<space>gsd",
                        "<cmd>lua vim.lsp.buf.show_line_diagnostics({ focusable = false })<CR>",
                        {noremap = true, silent = true})
