
--[[ nnoremap <space>p <cmd>lua require('tools').telescope_files()<cr>
nnoremap <space>f <cmd>lua require('tools').telescope_grep()<cr> ]]
require('telescope').setup {
    extensions = {
        fzy_native = {
            override_generic_sorter = false,
            override_file_sorter = true,
        }
    }
}
require('telescope').load_extension('fzy_native')

vim.api.nvim_set_keymap('n', '<space>p', "<cmd>lua require('tools').telescope_files()<cr>", { noremap = true, silent = true })
vim.api.nvim_set_keymap('n', '<space>f', "<cmd>lua require('tools').telescope_grep()<cr>", { noremap = true, silent = true })
vim.api.nvim_set_keymap('n', '<space>b', "<cmd>lua require('telescope.builtin').buffers()<cr>", { noremap = true, silent = true })

