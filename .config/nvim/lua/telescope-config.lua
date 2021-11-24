require('telescope').setup {
    extensions = {
        fzy_native = {
            override_generic_sorter = false,
            override_file_sorter = true
        }
    }
}
require('telescope').load_extension('fzy_native')

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
                        "<cmd>lua require('tools').telescope_diagnostics()<cr>",
                        {noremap = true, silent = true})

vim.api.nvim_set_keymap('n', '<space>p', "<cmd>:Rex<cr>",
                        {noremap = true, silent = true})

vim.api.nvim_set_keymap('n', '<space>sh', "<cmd>:split<CR>",
                        {noremap = true, silent = true})

vim.api.nvim_set_keymap('n', '<space>sv', "<cmd>:vsplit<CR>",
                        {noremap = true, silent = true})

-- TODO - figure out these things
vim.api.nvim_set_keymap('n', '<space>+', ':res +5 <CR>',
                        {noremap = true, silent = true})

vim.api.nvim_set_keymap('n', '<space>-', ':res -5<CR>',
                        {noremap = true, silent = true})
