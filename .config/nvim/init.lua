vim.g.mapleader = " "

local execute = vim.api.nvim_command
local fn = vim.fn
local install_path = fn.stdpath("data") .. "/site/pack/packer/start/packer.nvim"

if fn.empty(fn.glob(install_path)) > 0 then
    fn.system({
        "git", "clone", "https://github.com/wbthomason/packer.nvim",
        install_path
    })
    execute("packadd packer.nvim")
end

require("packer").startup(function()

    use({"wbthomason/packer.nvim"})

    use({"bobrown101/plugin-utils.nvim"})

    use({"bobrown101/fff.nvim"})

    use({
        "folke/which-key.nvim",
        config = function()
            local wk = require("which-key")
            wk.setup({})
            wk.register({
                d = {
                    name = "Diagnostics",
                    d = {
                        function()
                            vim.diagnostic.open_float()
                        end, "Open diagnostic float"
                    }
                },
                f = {
                    name = "file", -- optional group name
                    f = {
                        function()
                            require('tools').telescope_files()
                        end, "Find File"
                    }
                },
                s = {
                    name = "Search",
                    s = {
                        function()
                            require('tools').telescope_grep()
                        end, "Search String"
                    },
                    h = {function() vim.cmd("split") end, "Split Horizontal"},
                    v = {function() vim.cmd("vsplit") end, "Split Vertical"}
                },
                g = {
                    b = {function()
                        require('git_blame').run()
                    end, "Git Blame"}
                }
            }, {prefix = "<leader>"})

            wk.register({
                ["_"] = {
                    function()
                        vim.cmd('term ')
                        vim.cmd('startinsert')
                        -- require("minimal-nnn").start()
                    end, "NNN"
                },
                ["-"] = {
                    function()

                        -- vim.cmd('term tt .. | cat')
                        -- vim.cmd('startinsert')
                        require("fff").start()
                    end, "NNN"
                },
                ["<tab>"] = {
                    function()
                        require('telescope.builtin').buffers( --
                        require('telescope.themes').get_dropdown({
                            sort_lastused = true,
                            layout_config = {height = 0.3, width = 0.9}
                        }))
                    end, "toggle floating terminal"
                }
            }, {mode = "n"})
            wk.register({
                ['<esc>'] = {
                    function() vim.cmd('stopinsert') end,
                    "Escape terminal insert mode"
                }
            }, {mode = "t", prefix = "<esc>"})
        end
    })

    use({
        "bobrown101/asset-bender.nvim",
        requires = {"bobrown101/plugin-utils.nvim"},
        config = function() require("asset-bender").setup({}) end
    })

    use({
        "bobrown101/hubspot-js-utils.nvim",
        requires = {"bobrown101/plugin-utils.nvim"},
        config = function() require("hubspot-js-utils").setup({}) end
    })

    use {
        'bobrown101/nvim_cmp_hs_translation_source',
        config = function()
            require('nvim_cmp_hs_translation_source').setup()
        end
    }

    use({"bobrown101/git_blame.nvim"})

    use({"nvim-lua/plenary.nvim"})
    use({
        "lewis6991/gitsigns.nvim",
        requires = {"nvim-lua/plenary.nvim"},
        config = function() require("gitsigns").setup() end
    })

    use("L3MON4D3/LuaSnip")
    use("saadparwaiz1/cmp_luasnip")

    use("folke/tokyonight.nvim")
    --
    use({
        "nvim-treesitter/nvim-treesitter",
        config = function()

            local treesitter = require('nvim-treesitter.configs')

            treesitter.setup({
                ensure_installed = "all",
                ignore_install = {"haskell"},
                highlight = {enable = true},
                context_commentstring = {enable = true}
            })
        end
    })
    use({"neovim/nvim-lspconfig"})

    use({"onsails/lspkind-nvim"})
    use({"hrsh7th/cmp-nvim-lsp"})
    use({"hrsh7th/cmp-nvim-lua"})
    use({"hrsh7th/cmp-buffer"})

    use({
        "hrsh7th/nvim-cmp",
        config = function()
            local cmp = require('cmp')
            local lspkind = require('lspkind')
            vim.opt.completeopt = {"menu", "menuone", "noselect"}
            local sources = {
                {name = 'path'}, {name = 'nvim_lsp'}, {name = 'luasnip'},
                {name = 'buffer'}, {name = 'nvim_lua'}, {name = 'treesitter'},
                {name = "nvim_cmp_hs_translation_source"}
            }

            cmp.setup({
                snippet = {
                    expand = function(args)
                        require('luasnip').lsp_expand(args.body)
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
                    ['<C-Space>'] = cmp.mapping(cmp.mapping.complete(),
                                                {'i', 's'}),
                    ['<CR>'] = cmp.mapping(cmp.mapping.confirm({select = true}),
                                           {'i', 's'})
                },
                sources = sources,
                formatting = {
                    format = function(entry, vim_item)
                        vim_item.kind =
                            lspkind.presets.default[vim_item.kind] .. " " ..
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
        end
    })

    use({"kyazdani42/nvim-web-devicons"})

    use {
        "nvim-lualine/lualine.nvim",
        requires = {"kyazdani42/nvim-web-devicons", opt = true},
        config = function()
            local function fileLocationRelativeToGitRoot()
                return vim.fn.expand('%:~:.')
            end
            require('lualine').setup {
                options = {
                    theme = 'onelight',
                    component_separators = '|',
                    section_separators = {left = '', right = ''}
                },
                sections = {
                    lualine_a = {
                        {'mode', separator = {left = ''}, right_padding = 2}
                    },
                    lualine_b = {fileLocationRelativeToGitRoot, 'branch'},
                    lualine_x = {},
                    lualine_y = {'filetype', 'diff', 'progress'},
                    lualine_z = {
                        {
                            'location',
                            separator = {right = ''},
                            left_padding = 2
                        }
                    }
                },
                inactive_sections = {
                    lualine_a = {'filename'},
                    lualine_b = {},
                    lualine_c = {},
                    lualine_x = {},
                    lualine_y = {},
                    lualine_z = {'location'}
                },
                tabline = {},
                extensions = {}
            }
        end
    }

    use({
        "numToStr/Comment.nvim",
        config = function()
            require('Comment').setup {
                pre_hook = function(ctx)
                    local U = require 'Comment.utils'
                    local location = nil
                    if ctx.ctype == U.ctype.block then
                        location =
                            require('ts_context_commentstring.utils').get_cursor_location()
                    elseif ctx.cmotion == U.cmotion.v or ctx.cmotion ==
                        U.cmotion.V then
                        location =
                            require('ts_context_commentstring.utils').get_visual_start_location()
                    end
                    return
                        require('ts_context_commentstring.internal').calculate_commentstring {
                            key = ctx.ctype == U.ctype.line and '__default' or
                                '__multiline',
                            location = location
                        }
                end
            }
        end
    })
    use({
        "JoosepAlviste/nvim-ts-context-commentstring",
        config = function()
            require("nvim-treesitter.configs").setup({
                context_commentstring = {enable = true, enable_autocmd = false}
            })
        end
    })
    use {
        'goolord/alpha-nvim',
        requires = {'kyazdani42/nvim-web-devicons'},
        config = function()
            require'alpha'.setup(require'alpha.themes.startify'.config)
        end
    }
    use({"mhartington/formatter.nvim"})

    use({"nvim-lua/plenary.nvim"})

    use({
        "nvim-telescope/telescope.nvim",
        config = function()
            require("telescope").setup({defaults = {path_display = {"smart"}}})
        end
    })
    use({
        "folke/todo-comments.nvim",
        config = function() require("todo-comments").setup({}) end
    })
    use({
        "jose-elias-alvarez/null-ls.nvim",
        config = function()
            require("null-ls").setup({
                sources = {
                    require("null-ls").builtins.diagnostics.eslint_d,
                    require("null-ls").builtins.formatting.stylua
                }
            })
        end
    })

    use({
        "lukas-reineke/indent-blankline.nvim",
        config = function()
            vim.opt.listchars:append("space:⋅")

            require("indent_blankline").setup({})
        end
    })
end)

require("settings")
require("theme")
require("lsp")
require("formatter-config")
