local h = require("null-ls.helpers")
local methods = require("null-ls.methods")

local FORMATTING = methods.internal.FORMATTING
local RANGE_FORMATTING = methods.internal.RANGE_FORMATTING

require("null-ls").config({
    sources = {
        require("null-ls").builtins.diagnostics.eslint_d,
        stylua = h.make_builtin({
            method = { FORMATTING, RANGE_FORMATTING },
            filetypes = { "lua" },
            generator_opts = {
                command = "stylua",
                args = h.range_formatting_args_factory({
                    "--search-parent-directories",
                    "--indent-type",
                    "Spaces",
                    "--stdin-filepath",
                    "$FILENAME",
                    "-",
                }),
                to_stdin = true,
            },
            factory = h.formatter_factory,
        }),
    },
    debug = false,
})

require("lspconfig")["null-ls"].setup({})
