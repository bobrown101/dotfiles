vim.g.mapleader = " "

local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
    vim.fn.system({
        "git",
        "clone",
        "--filter=blob:none",
        "https://github.com/folke/lazy.nvim.git",
        "--branch=stable", -- latest stable release
        lazypath,
    })
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup({
    -- {
    --     "folke/noice.nvim",
    --     event = "VeryLazy",
    --     dependencies = {
    --         -- if you lazy-load any plugin below, make sure to add proper `module="..."` entries
    --         "MunifTanjim/nui.nvim",
    --         -- OPTIONAL:
    --         --   `nvim-notify` is only needed, if you want to use the notification view.
    --         --   If not available, we use `mini` as the fallback
    --         "rcarriga/nvim-notify",
    --     },
    --     config = function()
    --         require("noice").setup({
    --             cmdline = {
    --                 enabled = true, -- enables the Noice cmdline UI
    --                 view = "cmdline", -- view for rendering the cmdline. Change to `cmdline` to get a classic cmdline at the bottom
    --             },
    --             lsp = {
    --                 -- override markdown rendering so that **cmp** and other plugins use **Treesitter**
    --                 override = {
    --                     ["vim.lsp.util.convert_input_to_markdown_lines"] = true,
    --                     ["vim.lsp.util.stylize_markdown"] = true,
    --                     ["cmp.entry.get_documentation"] = true,
    --                 },
    --             },
    --             -- you can enable a preset for easier configuration
    --             presets = {
    --                 bottom_search = true, -- use a classic bottom cmdline for search
    --                 command_palette = true, -- position the cmdline and popupmenu together
    --                 long_message_to_split = true, -- long messages will be sent to a split
    --                 inc_rename = false, -- enables an input dialog for inc-rename.nvim
    --                 lsp_doc_border = false, -- add a border to hover docs and signature help
    --             },
    --         })
    --     end,
    -- },
    { "folke/neodev.nvim", opts = {} },
    {
        "folke/tokyonight.nvim",
        lazy = false, -- make sure we load this during startup if it is your main colorscheme
        priority = 1001, -- make sure to load this before all the other start plugins
        config = function()
            require("tokyonight").setup({
                style = "night", -- The theme comes in three styles, `storm`, `moon`, a darker variant `night` and `day`
                transparent = false, -- Enable this to disable setting the background color
                terminal_colors = true, -- Configure the colors used when opening a `:terminal` in Neovim
                on_highlights = function(highlights, colors)
                    highlights.WinSeparator = { fg = colors.border_highlight, bg = colors.border_highlight }
                end,
            })
            vim.cmd([[colorscheme tokyonight]])
        end,
    },
    {
        "j-hui/fidget.nvim",
        tag = "legacy",
        event = "LspAttach",
        opts = {
            -- options
        },
    },
    "wbthomason/packer.nvim",
    "bobrown101/plugin-utils.nvim",
    "bobrown101/fff.nvim",
    {
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
                        end,
                        "Open diagnostic float",
                    },
                },
                f = {
                    name = "file", -- optional group name
                    f = {
                        function()
                            require("tools").telescope_files()
                        end,
                        "Find File",
                    },
                },
                s = {
                    name = "Search",
                    s = {
                        function()
                            require("tools").telescope_grep()
                        end,
                        "Search String",
                    },
                    h = {
                        function()
                            vim.cmd("split")
                        end,
                        "Split Horizontal",
                    },
                    v = {
                        function()
                            vim.cmd("vsplit")
                        end,
                        "Split Vertical",
                    },
                },
                g = {
                    b = {
                        function()
                            require("git_blame").run()
                        end,
                        "Git Blame",
                    },
                    t = {
                        function()
                            require("hubspot-js-utils").test_file()
                        end,
                        "Test File",
                    },
                },
            }, { prefix = "<leader>" })

            wk.register({
                ["_"] = {
                    function()
                        vim.cmd("term ")
                        vim.cmd("startinsert")
                    end,
                    "Terminal",
                },
                ["-"] = {
                    function()
                        -- vim.cmd('term tt .. | cat')
                        -- vim.cmd('startinsert')
                        require("fff").start()
                    end,
                    "file browser",
                },
                ["<tab>"] = {
                    function()
                        require("telescope.builtin").buffers( --
                            require("telescope.themes").get_dropdown({
                                sort_lastused = true,
                                layout_config = { height = 0.3, width = 0.9 },
                            })
                        )
                    end,
                    "open up buffers list",
                },
            }, { mode = "n" })
            wk.register({
                ["<esc>"] = {
                    function()
                        vim.cmd("stopinsert")
                    end,
                    "Escape terminal insert mode",
                },
            }, { mode = "t", prefix = "<esc>" })
        end,
    },
    {
        "bobrown101/hubspot-js-utils.nvim",
        requires = { "bobrown101/plugin-utils.nvim" },
        config = function()
            require("hubspot-js-utils").setup({})
        end,
    },

    "bobrown101/git_blame.nvim",

    "nvim-lua/plenary.nvim",
    {
        "lewis6991/gitsigns.nvim",
        requires = { "nvim-lua/plenary.nvim" },
        config = function()
            require("gitsigns").setup()
        end,
    },

    {
        "nvim-treesitter/nvim-treesitter",
        config = function()
            local treesitter = require("nvim-treesitter.configs")

            treesitter.setup({
                ensure_installed = "all",
                ignore_install = { "haskell" },
                highlight = { enable = true },
                context_commentstring = { enable = true },
            })
        end,
    },
    "onsails/lspkind-nvim",
    "hrsh7th/cmp-nvim-lsp",
    "hrsh7th/cmp-nvim-lua",
    "hrsh7th/cmp-buffer",

    {
        "hrsh7th/nvim-cmp",
        config = function()
            local cmp = require("cmp")
            local lspkind = require("lspkind")
            local sources = {
                { name = "path" },
                { name = "nvim_lsp" },
                { name = "buffer" },
                { name = "nvim_lua" },
                { name = "treesitter" },
                --[[ { name = "nvim_cmp_hs_translation_source" }, ]]
            }

            cmp.setup({
                snippet = { expand = function() end },
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
                    ["<C-Space>"] = cmp.mapping(cmp.mapping.complete(), { "i", "s" }),
                    ["<CR>"] = cmp.mapping(cmp.mapping.confirm({ select = true }), { "i", "s" }),
                },
                sources = sources,
                formatting = {
                    format = function(entry, vim_item)
                        vim_item.kind = lspkind.presets.default[vim_item.kind] .. " " .. vim_item.kind

                        -- set a name for each source
                        vim_item.menu = ({
                            buffer = "[Buffer]",
                            nvim_lsp = "[LSP]",
                            nvim_lua = "[Lua]",
                            latex_symbols = "[Latex]",
                            nvim_cmp_hs_translation_source = "[Translation]",
                        })[entry.source.name]
                        return vim_item
                    end,
                },
            })
        end,
    },

    "nvim-tree/nvim-web-devicons",
    {
        "nvim-lualine/lualine.nvim",
        requires = { "kyazdani42/nvim-web-devicons", opt = true },
        config = function()
            local function fileLocationRelativeToGitRoot()
                return vim.fn.expand("%:~:.")
            end
            require("lualine").setup({
                options = {
                    theme = "onedark",
                    component_separators = "|",
                    -- section_separators = { left = "", right = "" },
                    section_separators = { left = "", right = "" },
                },
                sections = {
                    lualine_a = {
                        -- { "mode", separator = { left = "" }, right_padding = 2 },
                        { "mode", separator = { left = "" }, right_padding = 2 },
                    },
                    lualine_b = { fileLocationRelativeToGitRoot, "branch" },
                    lualine_x = {},
                    lualine_y = { "filetype", "diff", "progress" },
                    lualine_z = {
                        {
                            "location",
                            -- separator = { right = "" },
                            separator = { right = "" },
                            left_padding = 2,
                        },
                    },
                },
                inactive_sections = {
                    lualine_a = { "filename" },
                    lualine_b = {},
                    lualine_c = {},
                    lualine_x = {},
                    lualine_y = {},
                    lualine_z = { "location" },
                },
                tabline = {},
                extensions = {},
            })
        end,
    },

    {
        "numToStr/Comment.nvim",
        config = function()
            require("Comment").setup({
                pre_hook = require("ts_context_commentstring.integrations.comment_nvim").create_pre_hook(),
            })
        end,
    },
    {
        "JoosepAlviste/nvim-ts-context-commentstring",
        config = function()
            require("nvim-treesitter.configs").setup({
                context_commentstring = {
                    enable = true,
                    enable_autocmd = false,
                },
                incremental_selection = {
                    enable = true,
                    keymaps = {
                        init_selection = "<CR>", -- maps in normal mode to init the node/scope selection
                        node_decremental = "0", -- decrement to the previous node
                        node_incremental = "9", -- increment to the upper named parent
                        scope_incremental = "-", -- increment to the upper scope (as defined in locals.scm)
                    },
                },
            })
        end,
    },
    {
        "goolord/alpha-nvim",
        requires = { "kyazdani42/nvim-web-devicons" },
        config = function()
            require("alpha").setup(require("alpha.themes.startify").config)
        end,
    },
    -- "mhartington/formatter.nvim",

    {
        "nvim-telescope/telescope.nvim",
        config = function()
            require("telescope").setup({
                defaults = {
                    wrap_results = true,
                },
            })
        end,
    },
    {
        "folke/todo-comments.nvim",
        config = function()
            require("todo-comments").setup({})
        end,
    },
    {
        "neovim/nvim-lspconfig",
        config = function()
            require("lspconfig").eslint.setup({})
        end,
    },
    {
        "pmizio/typescript-tools.nvim",
        dependencies = { "nvim-lua/plenary.nvim", "neovim/nvim-lspconfig", "bobrown101/asset-bender.nvim" },
        event = { "BufReadPost *.ts", "BufReadPost *.js", "BufReadPost *.tsx", "BufReadPost *.jsx" },
        config = function()
            require("lsp")
        end,
    },
    {

        "stevearc/conform.nvim",
        config = function()
            require("conform").formatters.stylua = {
                prepend_args = { "--indent-type", "spaces" },
            }
            local frontendSetup = { "prettier" }
            require("conform").setup({
                format_on_save = {
                    timeout_ms = 500,
                    lsp_fallback = true,
                },
                formatters_by_ft = {
                    lua = { "stylua" },
                    -- Use a sub-list to run only the first available formatter
                    javascript = frontendSetup,
                    typescript = frontendSetup,
                    typescriptreact = frontendSetup,
                    javascriptreact = frontendSetup,
                },
            })
        end,
    },
})

vim.lsp.set_log_level("trace")

require("settings")
-- require("formatter-config")
