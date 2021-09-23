local util = require("lspconfig/util")
local Job = require("plenary.job")

function getLogPath()
    return vim.lsp.get_log_path()
end

function getTsserverPath()
    local result = "/lib/tsserver.js"
    Job
        :new({
            command = "bpx",
            args = { "--path", "hs-typescript" },
            on_exit = function(j, return_val)
                local path = j:result()[1]
                result = path .. result
            end,
        })
        :sync()

    return result
end

local function organize_imports()
    local params = {
        command = "_typescript.organizeImports",
        arguments = { vim.api.nvim_buf_get_name(0) },
        title = "",
    }
    vim.lsp.buf.execute_command(params)
end

local on_attach = function(client, bufnr)
    local function buf_set_keymap(...)
        vim.api.nvim_buf_set_keymap(bufnr, ...)
    end
    local function buf_set_option(...)
        vim.api.nvim_buf_set_option(bufnr, ...)
    end

    buf_set_keymap("n", "<space>gd", "<cmd>lua vim.lsp.buf.definition()<CR>", { noremap = true, silent = true })
    buf_set_keymap("n", "<space>gi", "<cmd>lua vim.lsp.buf.implementation()<CR>", { noremap = true, silent = true })
    buf_set_keymap("n", "<space>gr", "<cmd>lua vim.lsp.buf.references()<CR>", { noremap = true, silent = true })
    buf_set_keymap("n", "<space>rn", "<cmd>lua vim.lsp.buf.rename()<CR>", { noremap = true, silent = true })
    buf_set_keymap("n", "K", "<cmd>lua vim.lsp.buf.hover()<CR>", { noremap = true, silent = true })
    buf_set_keymap("n", "<space>gca", "<cmd>lua vim.lsp.buf.code_action()<CR>", { noremap = true, silent = true })
    buf_set_keymap(
        "n",
        "<space>gsd",
        "<cmd>lua vim.lsp.buf.show_line_diagnostics({ focusable = false })<CR>",
        { noremap = true, silent = true }
    )
end

local capabilities = vim.lsp.protocol.make_client_capabilities()
capabilities.textDocument.completion.completionItem.snippetSupport = true
capabilities.textDocument.completion.completionItem.preselectSupport = true
capabilities.textDocument.completion.completionItem.insertReplaceSupport = true
capabilities.textDocument.completion.completionItem.labelDetailsSupport = true
capabilities.textDocument.completion.completionItem.deprecatedSupport = true
capabilities.textDocument.completion.completionItem.commitCharactersSupport = true
capabilities.textDocument.completion.completionItem.tagSupport = { valueSet = { 1 } }
capabilities.textDocument.completion.completionItem.resolveSupport = {
    properties = {
        "documentation",
        "detail",
        "additionalTextEdits",
    },
}
-- capabilities = require('cmp_nvim_lsp').update_capabilities(capabilities)

require("lspconfig").tsserver.setup({
    cmd = {
        "typescript-language-server",
        "--tsserver-log-file",
        getLogPath(),
        "--tsserver-path",
        getTsserverPath(),
        "--stdio",
    },
    on_attach = on_attach,
    -- root_dir = util.root_pattern("package.json"),
    root_dir = util.root_pattern(".git"),
    filetypes = { "javascript", "javascriptreact", "javascript.jsx", "typescript", "typescriptreact", "typescript.tsx" },
    commands = {
        OrganizeImports = {
            organize_imports,
            description = "Organize Imports",
        },
    },
    capabilities = capabilities,
})

require("lspkind").init({})
