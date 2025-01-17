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
    {
        "yetone/avante.nvim",
        event = "VeryLazy",
        lazy = false,
        version = false, -- set this to "*" if you want to always pull the latest change, false to update on release
        opts = {
            provider = "copilot",
            -- add any opts here
        },
        -- if you want to build from source then do `make BUILD_FROM_SOURCE=true`
        build = "make BUILD_FROM_SOURCE=true",
        -- build = "powershell -ExecutionPolicy Bypass -File Build.ps1 -BuildFromSource false" -- for windows
        dependencies = {
            "stevearc/dressing.nvim",
            "nvim-lua/plenary.nvim",
            "MunifTanjim/nui.nvim",
            --- The below dependencies are optional,
            "hrsh7th/nvim-cmp", -- autocompletion for avante commands and mentions
            "nvim-tree/nvim-web-devicons", -- or echasnovski/mini.icons
            "zbirenbaum/copilot.lua", -- for providers='copilot'
            {
                -- support for image pasting
                "HakonHarnes/img-clip.nvim",
                event = "VeryLazy",
                opts = {
                    -- recommended settings
                    default = {
                        embed_image_as_base64 = false,
                        prompt_for_file_name = false,
                        drag_and_drop = {
                            insert_mode = true,
                        },
                        -- required for Windows users
                        use_absolute_path = true,
                    },
                },
            },
            {
                -- Make sure to set this up properly if you have lazy=true
                "MeanderingProgrammer/render-markdown.nvim",
                opts = {
                    file_types = { "markdown", "Avante" },
                },
                ft = { "markdown", "Avante" },
            },
        },
    },
    -- {
    --     "github/copilot.vim",
    -- },
    -- {
    --     "CopilotC-Nvim/CopilotChat.nvim",
    --     branch = "main",
    --     dependencies = {
    --         { "zbirenbaum/copilot.lua" }, -- or github/copilot.vim
    --         { "nvim-lua/plenary.nvim" }, -- for curl, log wrapper
    --     },
    --     build = "make tiktoken", -- Only on MacOS or Linux
    --     opts = {
    --         debug = true, -- Enable debugging
    --         -- See Configuration section for rest
    --     },
    --     -- See Commands section for default commands if you want to lazy load on them
    -- },
    { "folke/neodev.nvim", opts = {} },
    {
        "folke/tokyonight.nvim",
        lazy = false, -- make sure we load this during startup if it is your main colorscheme
        day_brightness = 1, -- Adjusts the brightness of the colors of the **Day** style. Number between 0 and 1, from dull to vibrant colors
        priority = 1001, -- make sure to load this before all the other start plugins
        config = function()
            require("tokyonight").setup({
                -- style = "night", -- The theme comes in three styles, `storm`, `moon`, a darker variant `night` and `day`
                style = "day", -- The theme comes in three styles, `storm`, `moon`, a darker variant `night` and `day`
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
        "stevearc/oil.nvim",
        ---@module 'oil'
        ---@type oil.SetupOpts
        opts = {},
        -- Optional dependencies
        dependencies = { "nvim-tree/nvim-web-devicons" }, -- use if prefer nvim-web-devicons
        config = function()
            require("oil").setup({
                view_options = {
                    show_hidden = true,
                },
            })
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
    {
        "folke/which-key.nvim",
        config = function()
            local wk = require("which-key")
            wk.add({
                { "<leader>d", group = "Diagnostics" },
                {
                    "<leader>dd",
                    function()
                        vim.diagnostic.open_float()
                    end,
                    desc = "Open diagnostic float",
                },
                { "<leader>f", group = "file" },
                {
                    "<leader>ff",
                    function()
                        require("telescope.builtin").find_files({
                            layout_config = { height = 0.9, width = 0.9 },
                            hidden = true,
                        })
                    end,
                    desc = "Find File",
                },
                {
                    "<leader>gb",
                    function()
                        vim.cmd("BlameToggle")
                    end,
                    desc = "Git Blame",
                },
                {
                    "<leader>gt",
                    function()
                        require("hubspot-js-utils").test_file()
                    end,
                    desc = "Test File",
                },
                { "<leader>s", group = "Search" },
                {
                    "<leader>sh",
                    function()
                        vim.cmd("split")
                    end,
                    desc = "Split Horizontal",
                },
                {
                    "<leader>ss",
                    function()
                        require("telescope.builtin").live_grep( --
                            { layout_config = { height = 0.9, width = 0.9 } }
                        )
                    end,
                    desc = "Search String",
                },
                {
                    "<leader>sv",
                    function()
                        vim.cmd("vsplit")
                    end,
                    desc = "Split Vertical",
                },
                {
                    mode = "n",
                    {
                        "_",
                        function()
                            vim.cmd("term ")
                            vim.cmd("startinsert")
                        end,
                        desc = "Terminal",
                    },
                    {
                        "-",
                        function()
                            vim.cmd("Oil")
                        end,
                        desc = "File browser",
                    },
                    {
                        "<tab>",
                        function()
                            require("telescope.builtin").buffers( --
                                require("telescope.themes").get_dropdown({
                                    sort_lastused = true,
                                    layout_config = { height = 0.3, width = 0.9 },
                                })
                            )
                        end,
                        desc = "open up buffers list",
                    },
                },
                {
                    mode = "t",
                    {
                        "<esc><esc>",
                        function()
                            vim.cmd("stopinsert")
                        end,
                        desc = "Escape terminal insert mode",
                    },
                },
            })
        end,
    },
    {
        "bobrown101/hubspot-js-utils.nvim",
        requires = { "bobrown101/plugin-utils.nvim" },
        config = function()
            require("hubspot-js-utils").setup({})
        end,
    },
    {
        "FabijanZulj/blame.nvim",
        config = function()
            require("blame").setup({
                mappings = {
                    commit_info = "K",
                    stack_push = "l",
                    stack_pop = "h",
                    show_commit = "<CR>",
                    close = { "<esc>", "q" },
                },
            })
        end,
    },
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
    {
        "nvimdev/lspsaga.nvim",
        config = function()
            require("lspsaga").setup({
                code_action = {
                    extend_gitsigns = true,
                    num_shortcut = true,
                    keys = {
                        quit = "<esc>",
                        exec = "<CR>",
                    },
                },
                symbol_in_winbar = {
                    enable = false,
                },
            })
        end,
        dependencies = {
            "nvim-treesitter/nvim-treesitter", -- optional
            "nvim-tree/nvim-web-devicons", -- optional
        },
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
        "folke/ts-comments.nvim",
        opts = {},
        event = "VeryLazy",
    },
    {
        "goolord/alpha-nvim",
        requires = { "kyazdani42/nvim-web-devicons" },
        config = function()
            require("alpha").setup(require("alpha.themes.startify").config)
        end,
    },
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
                    timeout_ms = 2500,
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
