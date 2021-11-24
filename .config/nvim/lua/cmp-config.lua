-- Setup nvim-cmp.
local cmp = require 'cmp'
local lspkind = require 'lspkind'

cmp.setup({
    snippet = {
        expand = function(args)
            -- For `vsnip` user.
            -- vim.fn["vsnip#anonymous"](args.body) -- For `vsnip` user.

            -- For `luasnip` user.
            require('luasnip').lsp_expand(args.body)

            -- For `ultisnips` user.
            -- vim.fn["UltiSnips#Anon"](args.body)
        end
    },
    mapping = {
        ["<Tab>"] = function(fallback)
            if cmp.visible() then
                cmp.select_next_item()
            else
                fallback()
            end
        end,
        ["<S-Tab>"] = function(fallback)
            if cmp.visible() then
                cmp.select_prev_item()
            else
                fallback()
            end
        end,
        ['<C-Space>'] = cmp.mapping(cmp.mapping.complete(), {'i', 's'}),
        ['<CR>'] = cmp.mapping(cmp.mapping.confirm({select = true}), {'i', 's'})
    },
    sources = {
        {name = "nvim_cmp_hs_translation_source"}, {name = 'nvim_lsp'},
        {name = 'luasnip'}, {name = 'buffer'}, {name = 'path'},
        {name = 'nvim_lua'}, {name = 'treesitter'}
    },
    formatting = {
        format = function(entry, vim_item)
            vim_item.kind = lspkind.presets.default[vim_item.kind] .. " " ..
                                vim_item.kind

            -- set a name for each source
            vim_item.menu = ({
                buffer = "[Buffer]",
                nvim_lsp = "[LSP]",
                luasnip = "[LuaSnip]",
                nvim_lua = "[Lua]",
                latex_symbols = "[Latex]",
                nvim_cmp_hs_translation_source = "[Translation]"
            })[entry.source.name]
            return vim_item
        end
    }
})

