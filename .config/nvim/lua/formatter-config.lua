
require("formatter").setup({
	logging = false,
	filetype = {
		javascript = {
			-- prettier
			function()
				return {
					exe = "prettier",
					args = {
						"--stdin-filepath",
						vim.api.nvim_buf_get_name(0),
					},
					stdin = true,
				}
			end,
		},

		javascriptreact = {
			-- prettier
			function()
				return {
					exe = "prettier",
					args = {
						"--stdin-filepath",
						vim.api.nvim_buf_get_name(0),
					},
					stdin = true,
				}
			end,
		},

		typescript = {
			-- prettier
			function()
				return {
					exe = "prettier",
					args = {
						"--stdin-filepath",
						vim.api.nvim_buf_get_name(0),
					},
					stdin = true,
				}
			end,
		},

		typescriptreact = {
			-- prettier
			function()
				return {
					exe = "prettier",
					args = {
						"--stdin-filepath",
						vim.api.nvim_buf_get_name(0),
					},
					stdin = true,
				}
			end,
		},

		mdx = {
			-- prettier
			function()
				return {
					exe = "prettier",
					args = {
						"--stdin-filepath",
						vim.api.nvim_buf_get_name(0),
					},
					stdin = true,
				}
			end,
		},

		-- https://github.com/luarocks/luarocks/wiki/Installation-instructions-for-Unix
		-- luarocks install --server=https://luarocks.org/dev luaformatter
		lua = {
			function()
				return {
					exe = "lua-format",
					args = { vim.api.nvim_buf_get_name(0) },
					stdin = true,
				}
			end,
		},
	},
})

vim.api.nvim_exec(
	[[
au! BufRead,BufNewFile *.mdx setfiletype mdx
augroup FormatAutogroup
  autocmd!
  autocmd BufWritePost *.js,*.ts,*.tsx,*.lua,*.mdx FormatWrite
augroup END
]],
	true
)
