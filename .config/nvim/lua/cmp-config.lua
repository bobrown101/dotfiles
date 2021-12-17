-- Setup nvim-cmp.
local cmp = require 'cmp'
local lspkind = require 'lspkind'
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

    return return_val == 0
end

local sources = {}
if getIsHubspotMachine() then
    sources = {
        {name = 'path'}, {name = "nvim_cmp_hs_translation_source"},
        {name = 'nvim_lsp'}, {name = 'luasnip'}, {name = 'buffer'},
        {name = 'nvim_lua'}, {name = 'treesitter'}
    }
else
    sources = {
        {name = 'path'}, {name = 'nvim_lsp'}, {name = 'luasnip'},
        {name = 'buffer'}, {name = 'nvim_lua'}, {name = 'treesitter'}
    }

end

cmp.setup({
    snippet = {
        expand = function(args) require('luasnip').lsp_expand(args.body) end
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
    sources = sources,
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

