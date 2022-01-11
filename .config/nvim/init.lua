vim.g.mapleader = ' '
local execute = vim.api.nvim_command
local fn = vim.fn

local install_path = fn.stdpath('data') .. '/site/pack/packer/start/packer.nvim'

if fn.empty(fn.glob(install_path)) > 0 then
    fn.system({
        'git', 'clone', 'https://github.com/wbthomason/packer.nvim',
        install_path
    })
    execute 'packadd packer.nvim'
end

require('packer').startup(function()

    use {'wbthomason/packer.nvim'}
    use {'~/Developer/git_blame.nvim'}

    use {
        'lewis6991/gitsigns.nvim',
        requires = {'nvim-lua/plenary.nvim'},
        config = function() require('gitsigns').setup() end
    }

    use 'L3MON4D3/LuaSnip'
    use 'saadparwaiz1/cmp_luasnip'

    use 'folke/tokyonight.nvim'

    use {'nvim-treesitter/nvim-treesitter'}
    use {'neovim/nvim-lspconfig'}

    use {'hrsh7th/cmp-nvim-lsp'}
    use {'hrsh7th/cmp-nvim-lua'}
    use {'hrsh7th/cmp-buffer'}
    use {
        'bobrown101/nvim_cmp_hs_translation_source',
        config = function()
            require('nvim_cmp_hs_translation_source').setup()
        end
    }

    use {'hrsh7th/nvim-cmp'}

    use {'glepnir/galaxyline.nvim'}
    use {'kyazdani42/nvim-web-devicons'}

    use {'numToStr/Comment.nvim'}

    use {
        'JoosepAlviste/nvim-ts-context-commentstring',
        config = function()
            require'nvim-treesitter.configs'.setup {
                context_commentstring = {enable = true, enable_autocmd = false}
            }

        end
    }
    use {'mhinz/vim-startify'}
    use {'mhartington/formatter.nvim'}
    use {'onsails/lspkind-nvim'}

    use {'nvim-lua/popup.nvim'}
    use {'nvim-lua/plenary.nvim'}

    use {
        'nvim-telescope/telescope.nvim',
        config = function()
            require('telescope').setup {}

            vim.api.nvim_set_keymap('n', '<space>ff',
                                    "<cmd>lua require('tools').telescope_files()<cr>",
                                    {noremap = true, silent = true})
            vim.api.nvim_set_keymap('n', '<space>ss',
                                    "<cmd>lua require('tools').telescope_grep()<cr>",
                                    {noremap = true, silent = true})
            vim.api.nvim_set_keymap('n', '<space>aa',
                                    "<cmd>lua require('tools').telescope_buffers()<cr>",
                                    {noremap = true, silent = true})
            vim.api.nvim_set_keymap('n', '<space>d',
                                    "<cmd>lua vim.diagnostic.open_float()<cr>",
                                    {noremap = true, silent = true})
            vim.api.nvim_set_keymap('n', '<space>sh', "<cmd>:split<CR>",
                                    {noremap = true, silent = true})
            vim.api.nvim_set_keymap('n', '<space>sv', "<cmd>:vsplit<CR>",
                                    {noremap = true, silent = true})
        end
    }

    use {
        'folke/todo-comments.nvim',
        config = function() require("todo-comments").setup {} end
    }

    use {
        "akinsho/nvim-toggleterm.lua",
        config = function()
            require'toggleterm'.setup {
                shading_factor = '1',
                shade_terminals = true,
                direction = 'float',
                float_opts = {border = 'double'}
            }

            vim.api.nvim_set_keymap("n", "<leader>q", "<cmd>:ToggleTerm <CR>",
                                    {noremap = true, silent = true})
            vim.api.nvim_set_keymap("t", "<leader>q", "<cmd>:ToggleTerm <CR>",
                                    {noremap = true, silent = true})
        end
    }

    use {
        'jose-elias-alvarez/null-ls.nvim',
        config = function()
            require("null-ls").setup({
                sources = {
                    require("null-ls").builtins.diagnostics.eslint_d,
                    require("null-ls").builtins.formatting.stylua
                }
            })
        end
    }

    use {"luukvbaal/nnn.nvim", config = function() require("nnn").setup() end}

    use {
        "lukas-reineke/indent-blankline.nvim",
        config = function()
            vim.opt.listchars:append("space:⋅")
            vim.opt.listchars:append("eol:↴")

            require("indent_blankline").setup {}

        end
    }
end)

require('settings')
require('theme')
require('lsp')
require('asset-bender')
require('hubspot-js-utils')
require("comment-nvim-config")
require('cmp-config')
require('bubbles-line')
require('treesitter-config')
require('formatter-config')

