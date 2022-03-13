local util = require("lspconfig/util")
local Job = require("plenary.job")

function getIsHubspotMachine()
    local result = ""
    local testing = {}
    Job:new({
        command = "ls",
        args = {vim.env.HOME .. '/.isHubspotMachine'},
        on_exit = function(j, return_val)
            result = return_val
            testing = j
        end
    }):sync()
    return result == 0
end

function getLogPath() return vim.lsp.get_log_path() end
-- function getLogPath() return '/Users/brbrown/.cache/nvim/tsserver.log' end

function getTsserverLogPath() return "/Users/brbrown/.cache/nvim/tsserver.log" end

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

local on_attach = function(client, bufnr) end

-- The nvim-cmp almost supports LSP's capabilities so You should advertise it to LSP servers..
local capabilities = vim.lsp.protocol.make_client_capabilities()
capabilities = require('cmp_nvim_lsp').update_capabilities(capabilities)

local isHubspotMachine = getIsHubspotMachine()

if isHubspotMachine then
    print('Configuring tsserver for hubspot ecosystem')
    -- this is for debugging
    --     "typescript-language-server", "--log-level", -- A number indicating the log level (4 = log, 3 = info, 2 = warn, 1 = error). Defaults to `2`.
    -- "4", "--tsserver-log-verbosity", "verbose", -- Specify tsserver log verbosity (off, terse, normal, verbose). Defaults to `normal`. example: --tsserver-log-verbosity=verbose
    -- "--tsserver-log-file", getTsserverLogPath(), "--tsserver-path",
    -- getTsserverPath(), "--stdio"

    require("lspconfig").tsserver.setup({
        flags = {debounce_text_changes = 500},
        cmd = {
            "typescript-language-server", "--log-level", "1", -- A number indicating the log level (4 = log, 3 = info, 2 = warn, 1 = error). Defaults to `2`.
            "--tsserver-log-verbosity", "off", -- Specify tsserver log verbosity (off, terse, normal, verbose). Defaults to `normal`. example: --tsserver-log-verbosity=verbose
            "--tsserver-log-file", getTsserverLogPath(), "--tsserver-path",
            getTsserverPath(), "--stdio"
        },
        on_attach = on_attach,
        root_dir = util.root_pattern(".git"),
        handlers = {
            ["textDocument/publishDiagnostics"] = vim.lsp.with(
                customPublishDiagnosticFunction, {})
        },
        init_options = {hostInfo = "neovim"},
        filetypes = {
            "javascript", "javascriptreact", "javascript.jsx", "typescript",
            "typescriptreact", "typescript.tsx"
        },
        capabilities = capabilities

    })
else
    require("lspconfig").tsserver.setup({})
end

-- npm install -g graphql-language-service-cli
-- require'lspconfig'.graphql.setup {}

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

-- FAQ
-- [ERROR][2022-02-22 11:10:04] ...lsp/handlers.lua:454 "[tsserver] /bin/sh: /usr/local/Cellar/node/17.5.0/bin/npm: No such file or directory\n"
--    ln -s (which npm) /usr/local/Cellar/node/17.5.0/bin/npm
--      
