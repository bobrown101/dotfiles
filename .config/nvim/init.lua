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

    use({"bobrown101/git_blame.nvim"})

    use({
        "lewis6991/gitsigns.nvim",
        requires = {"nvim-lua/plenary.nvim"},
        config = function() require("gitsigns").setup() end
    })

    use("L3MON4D3/LuaSnip")
    use("saadparwaiz1/cmp_luasnip")

    use("folke/tokyonight.nvim")

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

    use({"hrsh7th/nvim-cmp"})

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
                    lualine_b = {'filename', 'branch'},
                    lualine_c = {fileLocationRelativeToGitRoot},

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
        config = function() require("telescope").setup({}) end
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
require("cmp-config")
require("formatter-config")
