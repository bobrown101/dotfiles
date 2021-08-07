local util = require 'lspconfig/util'
local Job = require'plenary.job'

function getLogPath()
    return vim.lsp.get_log_path()
end

function getTsserverPath()
    local result = "/lib/tsserver.js"
    Job:new({
      command = 'bpx',
      args = { '--path', 'hs-typescript'},
      on_exit = function(j, return_val)
        local path = j:result()[1]
        result = path .. result
      end,
    }):sync()

    return result
end

local function organize_imports()
  local params = {
    command = "_typescript.organizeImports",
    arguments = {vim.api.nvim_buf_get_name(0)},
    title = ""
  }
  vim.lsp.buf.execute_command(params)
end

local on_attach = function(client, bufnr)
  require'lsp_signature'.on_attach(client, bufnr)
  local function buf_set_keymap(...) vim.api.nvim_buf_set_keymap(bufnr, ...) end
  local function buf_set_option(...) vim.api.nvim_buf_set_option(bufnr, ...) end

  buf_set_keymap("n", "<space>gd", "<cmd>lua vim.lsp.buf.definition()<CR>", {noremap = true, silent = true})
  buf_set_keymap("n", "<space>gi", "<cmd>lua vim.lsp.buf.implementation()<CR>", {noremap = true, silent = true})
  buf_set_keymap("n", "<space>gr", "<cmd>lua vim.lsp.buf.references()<CR>", {noremap = true, silent = true})
  buf_set_keymap("n", "<space>rn", "<cmd>lua vim.lsp.buf.rename()<CR>", {noremap = true, silent = true})
  buf_set_keymap("n", "K", "<cmd>lua vim.lsp.buf.hover()<CR>", {noremap = true, silent = true})
  buf_set_keymap("n", "<space>gca", "<cmd>lua vim.lsp.buf.code_action()<CR>", {noremap = true, silent = true})
  buf_set_keymap("n", "<space>gsd", "<cmd>lua vim.lsp.buf.show_line_diagnostics({ focusable = false })<CR>", {noremap = true, silent = true})


end

require'lspconfig'.tsserver.setup{ 
    cmd = {
        "typescript-language-server", 
        "--tsserver-log-file", getLogPath(),  
        "--tsserver-path",  getTsserverPath(), 
        "--stdio"
    },
    on_attach=on_attach,
    -- root_dir = util.root_pattern("package.json"),
    root_dir = util.root_pattern(".git"),
    filetypes = { "javascript", "javascriptreact", "javascript.jsx", "typescript", "typescriptreact", "typescript.tsx" },
    commands = {
      OrganizeImports = {
        organize_imports,
        description = "Organize Imports"
      }
    }
}


require('lspkind').init({

-- commented options are defaults
    -- with_text = true,
    -- symbol_map = {
    --   Text = '',
    --   Method = 'ƒ',
    --   Function = '',
    --   Constructor = '',
    --   Variable = '',
    --   Class = '',
    --   Interface = 'ﰮ',
    --   Module = '',
    --   Property = '',
    --   Unit = '',
    --   Value = '',
    --   Enum = '了',
    --   Keyword = '',
    --   Snippet = '﬌',
    --   Color = '',
    --   File = '',
    --   Folder = '',
    --   EnumMember = '',
    --   Constant = '',
    --   Struct = ''
    -- },
})
