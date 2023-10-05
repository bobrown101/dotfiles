-- local util = require("lspconfig/util")
--
require("neodev").setup({})
-- example to setup lua_ls and enable call snippets
require("lspconfig").lua_ls.setup({
	settings = {
		Lua = {
			completion = {
				callSnippet = "Replace",
			},
		},
	},
})

local tsserverpath = vim.env.TSSERVER_PATH
print("tsserverpath being calculated now: " .. tsserverpath)
require("typescript-tools").setup({
	settings = {
		-- spawn additional tsserver instance to calculate diagnostics on it
		separate_diagnostic_server = true,
		-- "change"|"insert_leave" determine when the client asks the server about diagnostic
		publish_diagnostic_on = "insert_leave",
		-- array of strings("fix_all"|"add_missing_imports"|"remove_unused"|
		-- "remove_unused_imports"|"organize_imports") -- or string "all"
		-- to include all supported code actions
		-- specify commands exposed as code_actions
		expose_as_code_action = {},
		-- string|nil - specify a custom path to `tsserver.js` file, if this is nil or file under path
		-- not exists then standard path resolution strategy is applied

		tsserver_path = tsserverpath,
		tsserver_logs = "terse",
		-- specify a list of plugins to load by tsserver, e.g., for support `styled-components`
		-- (see 💅 `styled-components` support section)
		tsserver_plugins = {},
		-- this value is passed to: https://nodejs.org/api/cli.html#--max-old-space-sizesize-in-megabytes
		-- memory limit in megabytes or "auto"(basically no limit)
		tsserver_max_memory = "auto",
		-- described below
		tsserver_format_options = {},
		tsserver_file_preferences = {},
		-- mirror of VSCode's `typescript.suggest.completeFunctionCalls`
		complete_function_calls = false,
		include_completions_with_insert_text = true,
		-- CodeLens
		-- WARNING: Experimental feature also in VSCode, because it might hit performance of server.
		-- possible values: ("off"|"all"|"implementations_only"|"references_only")
		code_lens = "off",
		-- by default code lenses are displayed on all referencable values and for some of you it can
		-- be too much this option reduce count of them by removing member references from lenses
		disable_member_code_lens = true,
	},
	on_attach = function()
		require("asset-bender").check_start_javascript_lsp()
	end,
})

-- FAQ
-- [ERROR][2022-02-22 11:10:04] ...lsp/handlers.lua:454 "[tsserver] /bin/sh: /usr/local/Cellar/node/17.5.0/bin/npm: No such file or directory\n"
--    ln -s (which npm) /usr/local/Cellar/node/17.5.0/bin/npm
--

vim.lsp.handlers["textDocument/signatureHelp"] = vim.lsp.with(vim.lsp.handlers.signature_help, { border = "single" })

vim.lsp.handlers["textDocument/hover"] = vim.lsp.with(vim.lsp.handlers.hover, { border = "single" })

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
vim.api.nvim_set_keymap("n", "<space>ga", "<cmd>lua vim.lsp.buf.code_action()<CR>", { noremap = true, silent = true })
vim.api.nvim_set_keymap(
	"n",
	"<space>gsd",
	"<cmd>lua vim.lsp.buf.show_line_diagnostics({ focusable = false })<CR>",
	{ noremap = true, silent = true }
)
