require'toggleterm'.setup{
  shading_factor = '1',

  shade_terminals = true,
  direction = 'float',
  float_opts = {
    border = 'double',
  }
}

vim.api.nvim_set_keymap("n", "<leader>q", "<cmd>:ToggleTerm <CR>", {noremap = true, silent = true})

vim.api.nvim_set_keymap("t", "<leader>q", "<cmd>:ToggleTerm <CR>", {noremap = true, silent = true})
