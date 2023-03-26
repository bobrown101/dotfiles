local util = require("lspconfig/util")

function get_npm_path()
	return vim.env.NPM_PATH
end

function getLogPath()
	return "~/.cache/nvim/tsserver"
	-- return vim.lsp.get_log_path()
end

function getTsserverPath()
	return vim.env.TSSERVER_PATH
end

local customPublishDiagnosticFunction = function(_, result, ctx, config)
	local filter = function(fun, t)
		local res = {}
		for _, item in ipairs(t) do
			if fun(item) then
				res[#res + 1] = item
			end
		end

		return res
	end
	local raw_diagnostics = result.diagnostics

	local filtered_diagnostics = filter(function(diagnostic)
		local diagnostic_code = diagnostic.code
		local diagnostic_source = diagnostic.source
		return not (diagnostic_code == 7016 and diagnostic_source == "typescript")
	end, raw_diagnostics)

	result.diagnostics = filtered_diagnostics

	return vim.lsp.diagnostic.on_publish_diagnostics(_, result, ctx, config)
end

local on_attach = function(client, bufnr) end

local capabilities = require("cmp_nvim_lsp").default_capabilities()

-- local isHubspotMachine = getIsHubspotMachine()
local isHubspotMachine = true

if isHubspotMachine then
	local tsserverpath = getTsserverPath()
	require("lspconfig").tsserver.setup({
		flags = { debounce_text_changes = 500 },
		cmd = {
			"typescript-language-server",
			"--log-level", -- A number indicating the log level (4 = log, 3 = info, 2 = warn, 1 = error). Defaults to `2`.
			"4",
			"--stdio",
		},
		on_attach = on_attach,
		root_dir = util.root_pattern(".git"),
		-- handlers = {
		-- ["textDocument/publishDiagnostics"] = vim.lsp.with(customPublishDiagnosticFunction, {}),
		-- },
		init_options = {
			hostInfo = "neovim",
			masTsServerMemory = 16384,
			npmLocation = get_npm_path(),
			disableAutomaticTypingAcquisition = true,
			tsserver = {
				logDirectory = getLogPath(),
				-- logVerbosity?: 'off' | 'terse' | 'normal' | 'requestTime' | 'verbose';
				logVerbosity = "verbose",
				path = tsserverpath,
				lazyConfiguredProjectsFromExternalProject = true,
			},
		},
		filetypes = {
			"javascript",
			"javascriptreact",
			"javascript.jsx",
			"typescript",
			"typescriptreact",
			"typescript.tsx",
		},
		capabilities = capabilities,
	})
else
	require("lspconfig").tsserver.setup({})
end

-- npm install -g graphql-language-service-cli
-- require'lspconfig'.graphql.setup {}

-- yarn global add yaml-language-server
require("lspconfig").yamlls.setup({})

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

-- FAQ
-- [ERROR][2022-02-22 11:10:04] ...lsp/handlers.lua:454 "[tsserver] /bin/sh: /usr/local/Cellar/node/17.5.0/bin/npm: No such file or directory\n"
--    ln -s (which npm) /usr/local/Cellar/node/17.5.0/bin/npm
--
