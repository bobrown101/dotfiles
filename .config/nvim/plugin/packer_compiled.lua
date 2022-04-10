-- Automatically generated packer.nvim plugin loader code

if vim.api.nvim_call_function('has', {'nvim-0.5'}) ~= 1 then
  vim.api.nvim_command('echohl WarningMsg | echom "Invalid Neovim version for packer.nvim! | echohl None"')
  return
end

vim.api.nvim_command('packadd packer.nvim')

local no_errors, error_msg = pcall(function()

  local time
  local profile_info
  local should_profile = false
  if should_profile then
    local hrtime = vim.loop.hrtime
    profile_info = {}
    time = function(chunk, start)
      if start then
        profile_info[chunk] = hrtime()
      else
        profile_info[chunk] = (hrtime() - profile_info[chunk]) / 1e6
      end
    end
  else
    time = function(chunk, start) end
  end
  
local function save_profiles(threshold)
  local sorted_times = {}
  for chunk_name, time_taken in pairs(profile_info) do
    sorted_times[#sorted_times + 1] = {chunk_name, time_taken}
  end
  table.sort(sorted_times, function(a, b) return a[2] > b[2] end)
  local results = {}
  for i, elem in ipairs(sorted_times) do
    if not threshold or threshold and elem[2] > threshold then
      results[i] = elem[1] .. ' took ' .. elem[2] .. 'ms'
    end
  end

  _G._packer = _G._packer or {}
  _G._packer.profile_output = results
end

time([[Luarocks path setup]], true)
local package_path_str = "/Users/brbrown/.cache/nvim/packer_hererocks/2.1.0-beta3/share/lua/5.1/?.lua;/Users/brbrown/.cache/nvim/packer_hererocks/2.1.0-beta3/share/lua/5.1/?/init.lua;/Users/brbrown/.cache/nvim/packer_hererocks/2.1.0-beta3/lib/luarocks/rocks-5.1/?.lua;/Users/brbrown/.cache/nvim/packer_hererocks/2.1.0-beta3/lib/luarocks/rocks-5.1/?/init.lua"
local install_cpath_pattern = "/Users/brbrown/.cache/nvim/packer_hererocks/2.1.0-beta3/lib/lua/5.1/?.so"
if not string.find(package.path, package_path_str, 1, true) then
  package.path = package.path .. ';' .. package_path_str
end

if not string.find(package.cpath, install_cpath_pattern, 1, true) then
  package.cpath = package.cpath .. ';' .. install_cpath_pattern
end

time([[Luarocks path setup]], false)
time([[try_loadstring definition]], true)
local function try_loadstring(s, component, name)
  local success, result = pcall(loadstring(s), name, _G.packer_plugins[name])
  if not success then
    vim.schedule(function()
      vim.api.nvim_notify('packer.nvim: Error running ' .. component .. ' for ' .. name .. ': ' .. result, vim.log.levels.ERROR, {})
    end)
  end
  return result
end

time([[try_loadstring definition]], false)
time([[Defining packer_plugins]], true)
_G.packer_plugins = {
  ["Comment.nvim"] = {
    config = { "\27LJ\2\n§\3\0\1\b\0\18\00006\1\0\0'\3\1\0B\1\2\2+\2\0\0009\3\2\0009\4\2\0019\4\3\4\5\3\4\0X\3\a€6\3\0\0'\5\4\0B\3\2\0029\3\5\3B\3\1\2\18\2\3\0X\3\16€9\3\6\0009\4\6\0019\4\a\4\4\3\4\0X\3\5€9\3\6\0009\4\6\0019\4\b\4\5\3\4\0X\3\6€6\3\0\0'\5\4\0B\3\2\0029\3\t\3B\3\1\2\18\2\3\0006\3\0\0'\5\n\0B\3\2\0029\3\v\0035\5\14\0009\6\2\0009\a\2\0019\a\f\a\5\6\a\0X\6\2€'\6\r\0X\a\1€'\6\15\0=\6\16\5=\2\17\5D\3\2\0\rlocation\bkey\16__multiline\1\0\0\14__default\tline\28calculate_commentstring&ts_context_commentstring.internal\30get_visual_start_location\6V\6v\fcmotion\24get_cursor_location#ts_context_commentstring.utils\nblock\nctype\18Comment.utils\frequireN\1\0\4\0\6\0\t6\0\0\0'\2\1\0B\0\2\0029\0\2\0005\2\4\0003\3\3\0=\3\5\2B\0\2\1K\0\1\0\rpre_hook\1\0\0\0\nsetup\fComment\frequire\0" },
    loaded = true,
    path = "/Users/brbrown/.local/share/nvim/site/pack/packer/start/Comment.nvim",
    url = "https://github.com/numToStr/Comment.nvim"
  },
  ["FTerm.nvim"] = {
    config = { "\27LJ\2\nè\2\0\0\6\0\16\0\0256\0\0\0'\2\1\0B\0\2\0029\0\2\0005\2\3\0005\3\4\0=\3\5\2B\0\2\0016\0\6\0009\0\a\0009\0\b\0'\2\t\0'\3\n\0'\4\v\0005\5\f\0B\0\5\0016\0\6\0009\0\a\0009\0\b\0'\2\r\0'\3\n\0'\4\14\0005\5\15\0B\0\5\1K\0\1\0\1\0\2\vsilent\2\fnoremap\0025<C-\\><C-n><CMD>lua require('FTERM').toggle()<CR>\6t\1\0\2\vsilent\2\fnoremap\2+<CMD>lua require('FTERM').toggle()<CR>\14<leader>1\6n\20nvim_set_keymap\bapi\bvim\16dimmensions\1\0\2\nwidth\4Í™³æ\fÌ™³ÿ\3\vheight\4Í™³æ\fÌ™³ÿ\3\1\0\1\vborder\vdouble\nsetup\nFTerm\frequire\0" },
    loaded = true,
    path = "/Users/brbrown/.local/share/nvim/site/pack/packer/start/FTerm.nvim",
    url = "https://github.com/numToStr/FTerm.nvim"
  },
  LuaSnip = {
    loaded = true,
    path = "/Users/brbrown/.local/share/nvim/site/pack/packer/start/LuaSnip",
    url = "https://github.com/L3MON4D3/LuaSnip"
  },
  ["alpha-nvim"] = {
    config = { "\27LJ\2\n`\0\0\5\0\5\0\n6\0\0\0'\2\1\0B\0\2\0029\0\2\0006\2\0\0'\4\3\0B\2\2\0029\2\4\2B\0\2\1K\0\1\0\vconfig\26alpha.themes.startify\nsetup\nalpha\frequire\0" },
    loaded = true,
    path = "/Users/brbrown/.local/share/nvim/site/pack/packer/start/alpha-nvim",
    url = "https://github.com/goolord/alpha-nvim"
  },
  ["asset-bender.nvim"] = {
    config = { "\27LJ\2\n>\0\0\3\0\3\0\a6\0\0\0'\2\1\0B\0\2\0029\0\2\0004\2\0\0B\0\2\1K\0\1\0\nsetup\17asset-bender\frequire\0" },
    loaded = true,
    path = "/Users/brbrown/.local/share/nvim/site/pack/packer/start/asset-bender.nvim",
    url = "https://github.com/bobrown101/asset-bender.nvim"
  },
  ["cmp-buffer"] = {
    loaded = true,
    path = "/Users/brbrown/.local/share/nvim/site/pack/packer/start/cmp-buffer",
    url = "https://github.com/hrsh7th/cmp-buffer"
  },
  ["cmp-nvim-lsp"] = {
    loaded = true,
    path = "/Users/brbrown/.local/share/nvim/site/pack/packer/start/cmp-nvim-lsp",
    url = "https://github.com/hrsh7th/cmp-nvim-lsp"
  },
  ["cmp-nvim-lua"] = {
    loaded = true,
    path = "/Users/brbrown/.local/share/nvim/site/pack/packer/start/cmp-nvim-lua",
    url = "https://github.com/hrsh7th/cmp-nvim-lua"
  },
  cmp_luasnip = {
    loaded = true,
    path = "/Users/brbrown/.local/share/nvim/site/pack/packer/start/cmp_luasnip",
    url = "https://github.com/saadparwaiz1/cmp_luasnip"
  },
  ["formatter.nvim"] = {
    loaded = true,
    path = "/Users/brbrown/.local/share/nvim/site/pack/packer/start/formatter.nvim",
    url = "https://github.com/mhartington/formatter.nvim"
  },
  ["gitsigns.nvim"] = {
    config = { "\27LJ\2\n6\0\0\3\0\3\0\0066\0\0\0'\2\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\nsetup\rgitsigns\frequire\0" },
    loaded = true,
    path = "/Users/brbrown/.local/share/nvim/site/pack/packer/start/gitsigns.nvim",
    url = "https://github.com/lewis6991/gitsigns.nvim"
  },
  ["hubspot-js-utils.nvim"] = {
    config = { "\27LJ\2\nB\0\0\3\0\3\0\a6\0\0\0'\2\1\0B\0\2\0029\0\2\0004\2\0\0B\0\2\1K\0\1\0\nsetup\21hubspot-js-utils\frequire\0" },
    loaded = true,
    path = "/Users/brbrown/.local/share/nvim/site/pack/packer/start/hubspot-js-utils.nvim",
    url = "https://github.com/bobrown101/hubspot-js-utils.nvim"
  },
  ["indent-blankline.nvim"] = {
    config = { "\27LJ\2\n\1\0\0\4\0\b\0\0146\0\0\0009\0\1\0009\0\2\0\18\2\0\0009\0\3\0'\3\4\0B\0\3\0016\0\5\0'\2\6\0B\0\2\0029\0\a\0004\2\0\0B\0\2\1K\0\1\0\nsetup\21indent_blankline\frequire\14space:â‹…\vappend\14listchars\bopt\bvim\0" },
    loaded = true,
    path = "/Users/brbrown/.local/share/nvim/site/pack/packer/start/indent-blankline.nvim",
    url = "https://github.com/lukas-reineke/indent-blankline.nvim"
  },
  ["lspkind-nvim"] = {
    loaded = true,
    path = "/Users/brbrown/.local/share/nvim/site/pack/packer/start/lspkind-nvim",
    url = "https://github.com/onsails/lspkind-nvim"
  },
  ["lualine.nvim"] = {
    config = { "\27LJ\2\n/\0\0\3\0\4\0\0056\0\0\0009\0\1\0009\0\2\0'\2\3\0D\0\2\0\n%:~:.\vexpand\afn\bvimà\4\1\0\b\0\30\00053\0\0\0006\1\1\0'\3\2\0B\1\2\0029\1\3\0015\3\a\0005\4\4\0005\5\5\0=\5\6\4=\4\b\0035\4\f\0004\5\3\0005\6\t\0005\a\n\0=\a\v\6>\6\1\5=\5\r\0045\5\14\0=\5\15\0044\5\3\0>\0\1\5=\5\16\0044\5\0\0=\5\17\0045\5\18\0=\5\19\0044\5\3\0005\6\20\0005\a\21\0=\a\v\6>\6\1\5=\5\22\4=\4\23\0035\4\25\0005\5\24\0=\5\r\0044\5\0\0=\5\15\0044\5\0\0=\5\16\0044\5\0\0=\5\17\0044\5\0\0=\5\19\0045\5\26\0=\5\22\4=\4\27\0034\4\0\0=\4\28\0034\4\0\0=\4\29\3B\1\2\1K\0\1\0\15extensions\ftabline\22inactive_sections\1\2\0\0\rlocation\1\0\0\1\2\0\0\rfilename\rsections\14lualine_z\1\0\1\nright\bî‚´\1\2\1\0\rlocation\17left_padding\3\2\14lualine_y\1\4\0\0\rfiletype\tdiff\rprogress\14lualine_x\14lualine_c\14lualine_b\1\3\0\0\rfilename\vbranch\14lualine_a\1\0\0\14separator\1\0\1\tleft\bî‚¶\1\2\1\0\tmode\18right_padding\3\2\foptions\1\0\0\23section_separators\1\0\2\nright\bî‚¶\tleft\bî‚´\1\0\2\25component_separators\6|\ntheme\ronelight\nsetup\flualine\frequire\0\0" },
    loaded = true,
    path = "/Users/brbrown/.local/share/nvim/site/pack/packer/start/lualine.nvim",
    url = "https://github.com/nvim-lualine/lualine.nvim"
  },
  ["nnn.nvim"] = {
    config = { "\27LJ\2\nä\1\0\0\6\0\r\0\0176\0\0\0'\2\1\0B\0\2\0029\0\2\0005\2\4\0005\3\3\0=\3\5\2B\0\2\0016\0\6\0009\0\a\0009\0\b\0'\2\t\0'\3\n\0'\4\v\0005\5\f\0B\0\5\1K\0\1\0\1\0\2\vsilent\2\fnoremap\0026:lua require('nnn').toggle('picker', '%:p:h')<CR>\6-\6n\20nvim_set_keymap\bapi\bvim\vpicker\1\0\0\1\0\1\bcmd\24EDITOR=nvim nnn -Pp\nsetup\bnnn\frequire\0" },
    loaded = true,
    path = "/Users/brbrown/.local/share/nvim/site/pack/packer/start/nnn.nvim",
    url = "https://github.com/luukvbaal/nnn.nvim"
  },
  ["null-ls.nvim"] = {
    config = { "\27LJ\2\n´\1\0\0\a\0\n\0\0236\0\0\0'\2\1\0B\0\2\0029\0\2\0005\2\b\0004\3\3\0006\4\0\0'\6\1\0B\4\2\0029\4\3\0049\4\4\0049\4\5\4>\4\1\0036\4\0\0'\6\1\0B\4\2\0029\4\3\0049\4\6\0049\4\a\4>\4\2\3=\3\t\2B\0\2\1K\0\1\0\fsources\1\0\0\vstylua\15formatting\reslint_d\16diagnostics\rbuiltins\nsetup\fnull-ls\frequire\0" },
    loaded = true,
    path = "/Users/brbrown/.local/share/nvim/site/pack/packer/start/null-ls.nvim",
    url = "https://github.com/jose-elias-alvarez/null-ls.nvim"
  },
  ["nvim-cmp"] = {
    loaded = true,
    path = "/Users/brbrown/.local/share/nvim/site/pack/packer/start/nvim-cmp",
    url = "https://github.com/hrsh7th/nvim-cmp"
  },
  ["nvim-lspconfig"] = {
    loaded = true,
    path = "/Users/brbrown/.local/share/nvim/site/pack/packer/start/nvim-lspconfig",
    url = "https://github.com/neovim/nvim-lspconfig"
  },
  ["nvim-treesitter"] = {
    config = { "\27LJ\2\nÊ\1\0\0\5\0\n\0\r6\0\0\0'\2\1\0B\0\2\0029\1\2\0005\3\3\0005\4\4\0=\4\5\0035\4\6\0=\4\a\0035\4\b\0=\4\t\3B\1\2\1K\0\1\0\26context_commentstring\1\0\1\venable\2\14highlight\1\0\1\venable\2\19ignore_install\1\2\0\0\fhaskell\1\0\1\21ensure_installed\ball\nsetup\28nvim-treesitter.configs\frequire\0" },
    loaded = true,
    path = "/Users/brbrown/.local/share/nvim/site/pack/packer/start/nvim-treesitter",
    url = "https://github.com/nvim-treesitter/nvim-treesitter"
  },
  ["nvim-ts-context-commentstring"] = {
    config = { "\27LJ\2\n…\1\0\0\4\0\6\0\t6\0\0\0'\2\1\0B\0\2\0029\0\2\0005\2\4\0005\3\3\0=\3\5\2B\0\2\1K\0\1\0\26context_commentstring\1\0\0\1\0\2\venable\2\19enable_autocmd\1\nsetup\28nvim-treesitter.configs\frequire\0" },
    loaded = true,
    path = "/Users/brbrown/.local/share/nvim/site/pack/packer/start/nvim-ts-context-commentstring",
    url = "https://github.com/JoosepAlviste/nvim-ts-context-commentstring"
  },
  ["nvim-web-devicons"] = {
    loaded = true,
    path = "/Users/brbrown/.local/share/nvim/site/pack/packer/start/nvim-web-devicons",
    url = "https://github.com/kyazdani42/nvim-web-devicons"
  },
  ["packer.nvim"] = {
    loaded = true,
    path = "/Users/brbrown/.local/share/nvim/site/pack/packer/start/packer.nvim",
    url = "https://github.com/wbthomason/packer.nvim"
  },
  ["plenary.nvim"] = {
    loaded = true,
    path = "/Users/brbrown/.local/share/nvim/site/pack/packer/start/plenary.nvim",
    url = "https://github.com/nvim-lua/plenary.nvim"
  },
  ["plugin-utils.nvim"] = {
    loaded = true,
    path = "/Users/brbrown/.local/share/nvim/site/pack/packer/start/plugin-utils.nvim",
    url = "https://github.com/bobrown101/plugin-utils.nvim"
  },
  ["telescope.nvim"] = {
    config = { "\27LJ\2\n¤\a\0\0\6\0\27\0?6\0\0\0'\2\1\0B\0\2\0029\0\2\0004\2\0\0B\0\2\0016\0\3\0009\0\4\0009\0\5\0'\2\6\0'\3\a\0'\4\b\0005\5\t\0B\0\5\0016\0\3\0009\0\4\0009\0\5\0'\2\6\0'\3\n\0'\4\v\0005\5\f\0B\0\5\0016\0\3\0009\0\4\0009\0\5\0'\2\6\0'\3\r\0'\4\14\0005\5\15\0B\0\5\0016\0\3\0009\0\4\0009\0\5\0'\2\6\0'\3\a\0'\4\16\0005\5\17\0B\0\5\0016\0\3\0009\0\4\0009\0\5\0'\2\6\0'\3\18\0'\4\19\0005\5\20\0B\0\5\0016\0\3\0009\0\4\0009\0\5\0'\2\6\0'\3\21\0'\4\22\0005\5\23\0B\0\5\0016\0\3\0009\0\4\0009\0\5\0'\2\6\0'\3\24\0'\4\25\0005\5\26\0B\0\5\1K\0\1\0\1\0\2\vsilent\2\fnoremap\2\21<cmd>:vsplit<CR>\14<space>sv\1\0\2\vsilent\2\fnoremap\2\20<cmd>:split<CR>\14<space>sh\1\0\2\vsilent\2\fnoremap\2-<cmd>lua vim.diagnostic.open_float()<cr>\r<space>d\1\0\2\vsilent\2\fnoremap\2¥\1<cmd>lua require('telescope.builtin').buffers(require('telescope.themes').get_dropdown({sort_lastused = true, layout_config = {height = 0.3, width = 0.9}}))<cr>\1\0\2\vsilent\2\fnoremap\0023<cmd>lua require('tools').telescope_grep()<cr>\14<space>ss\1\0\2\vsilent\2\fnoremap\0024<cmd>lua require('tools').telescope_files()<cr>\14<space>ff\1\0\2\vsilent\2\fnoremap\2e<cmd> lua require'telescope.builtin'.buffers(require('telescope.themes').get_dropdown({ })) <CR>\n<tab>\6n\20nvim_set_keymap\bapi\bvim\nsetup\14telescope\frequire\0" },
    loaded = true,
    path = "/Users/brbrown/.local/share/nvim/site/pack/packer/start/telescope.nvim",
    url = "https://github.com/nvim-telescope/telescope.nvim"
  },
  ["todo-comments.nvim"] = {
    config = { "\27LJ\2\n?\0\0\3\0\3\0\a6\0\0\0'\2\1\0B\0\2\0029\0\2\0004\2\0\0B\0\2\1K\0\1\0\nsetup\18todo-comments\frequire\0" },
    loaded = true,
    path = "/Users/brbrown/.local/share/nvim/site/pack/packer/start/todo-comments.nvim",
    url = "https://github.com/folke/todo-comments.nvim"
  },
  ["tokyonight.nvim"] = {
    loaded = true,
    path = "/Users/brbrown/.local/share/nvim/site/pack/packer/start/tokyonight.nvim",
    url = "https://github.com/folke/tokyonight.nvim"
  }
}

time([[Defining packer_plugins]], false)
-- Config for: FTerm.nvim
time([[Config for FTerm.nvim]], true)
try_loadstring("\27LJ\2\nè\2\0\0\6\0\16\0\0256\0\0\0'\2\1\0B\0\2\0029\0\2\0005\2\3\0005\3\4\0=\3\5\2B\0\2\0016\0\6\0009\0\a\0009\0\b\0'\2\t\0'\3\n\0'\4\v\0005\5\f\0B\0\5\0016\0\6\0009\0\a\0009\0\b\0'\2\r\0'\3\n\0'\4\14\0005\5\15\0B\0\5\1K\0\1\0\1\0\2\vsilent\2\fnoremap\0025<C-\\><C-n><CMD>lua require('FTERM').toggle()<CR>\6t\1\0\2\vsilent\2\fnoremap\2+<CMD>lua require('FTERM').toggle()<CR>\14<leader>1\6n\20nvim_set_keymap\bapi\bvim\16dimmensions\1\0\2\nwidth\4Í™³æ\fÌ™³ÿ\3\vheight\4Í™³æ\fÌ™³ÿ\3\1\0\1\vborder\vdouble\nsetup\nFTerm\frequire\0", "config", "FTerm.nvim")
time([[Config for FTerm.nvim]], false)
-- Config for: nnn.nvim
time([[Config for nnn.nvim]], true)
try_loadstring("\27LJ\2\nä\1\0\0\6\0\r\0\0176\0\0\0'\2\1\0B\0\2\0029\0\2\0005\2\4\0005\3\3\0=\3\5\2B\0\2\0016\0\6\0009\0\a\0009\0\b\0'\2\t\0'\3\n\0'\4\v\0005\5\f\0B\0\5\1K\0\1\0\1\0\2\vsilent\2\fnoremap\0026:lua require('nnn').toggle('picker', '%:p:h')<CR>\6-\6n\20nvim_set_keymap\bapi\bvim\vpicker\1\0\0\1\0\1\bcmd\24EDITOR=nvim nnn -Pp\nsetup\bnnn\frequire\0", "config", "nnn.nvim")
time([[Config for nnn.nvim]], false)
-- Config for: hubspot-js-utils.nvim
time([[Config for hubspot-js-utils.nvim]], true)
try_loadstring("\27LJ\2\nB\0\0\3\0\3\0\a6\0\0\0'\2\1\0B\0\2\0029\0\2\0004\2\0\0B\0\2\1K\0\1\0\nsetup\21hubspot-js-utils\frequire\0", "config", "hubspot-js-utils.nvim")
time([[Config for hubspot-js-utils.nvim]], false)
-- Config for: nvim-treesitter
time([[Config for nvim-treesitter]], true)
try_loadstring("\27LJ\2\nÊ\1\0\0\5\0\n\0\r6\0\0\0'\2\1\0B\0\2\0029\1\2\0005\3\3\0005\4\4\0=\4\5\0035\4\6\0=\4\a\0035\4\b\0=\4\t\3B\1\2\1K\0\1\0\26context_commentstring\1\0\1\venable\2\14highlight\1\0\1\venable\2\19ignore_install\1\2\0\0\fhaskell\1\0\1\21ensure_installed\ball\nsetup\28nvim-treesitter.configs\frequire\0", "config", "nvim-treesitter")
time([[Config for nvim-treesitter]], false)
-- Config for: telescope.nvim
time([[Config for telescope.nvim]], true)
try_loadstring("\27LJ\2\n¤\a\0\0\6\0\27\0?6\0\0\0'\2\1\0B\0\2\0029\0\2\0004\2\0\0B\0\2\0016\0\3\0009\0\4\0009\0\5\0'\2\6\0'\3\a\0'\4\b\0005\5\t\0B\0\5\0016\0\3\0009\0\4\0009\0\5\0'\2\6\0'\3\n\0'\4\v\0005\5\f\0B\0\5\0016\0\3\0009\0\4\0009\0\5\0'\2\6\0'\3\r\0'\4\14\0005\5\15\0B\0\5\0016\0\3\0009\0\4\0009\0\5\0'\2\6\0'\3\a\0'\4\16\0005\5\17\0B\0\5\0016\0\3\0009\0\4\0009\0\5\0'\2\6\0'\3\18\0'\4\19\0005\5\20\0B\0\5\0016\0\3\0009\0\4\0009\0\5\0'\2\6\0'\3\21\0'\4\22\0005\5\23\0B\0\5\0016\0\3\0009\0\4\0009\0\5\0'\2\6\0'\3\24\0'\4\25\0005\5\26\0B\0\5\1K\0\1\0\1\0\2\vsilent\2\fnoremap\2\21<cmd>:vsplit<CR>\14<space>sv\1\0\2\vsilent\2\fnoremap\2\20<cmd>:split<CR>\14<space>sh\1\0\2\vsilent\2\fnoremap\2-<cmd>lua vim.diagnostic.open_float()<cr>\r<space>d\1\0\2\vsilent\2\fnoremap\2¥\1<cmd>lua require('telescope.builtin').buffers(require('telescope.themes').get_dropdown({sort_lastused = true, layout_config = {height = 0.3, width = 0.9}}))<cr>\1\0\2\vsilent\2\fnoremap\0023<cmd>lua require('tools').telescope_grep()<cr>\14<space>ss\1\0\2\vsilent\2\fnoremap\0024<cmd>lua require('tools').telescope_files()<cr>\14<space>ff\1\0\2\vsilent\2\fnoremap\2e<cmd> lua require'telescope.builtin'.buffers(require('telescope.themes').get_dropdown({ })) <CR>\n<tab>\6n\20nvim_set_keymap\bapi\bvim\nsetup\14telescope\frequire\0", "config", "telescope.nvim")
time([[Config for telescope.nvim]], false)
-- Config for: null-ls.nvim
time([[Config for null-ls.nvim]], true)
try_loadstring("\27LJ\2\n´\1\0\0\a\0\n\0\0236\0\0\0'\2\1\0B\0\2\0029\0\2\0005\2\b\0004\3\3\0006\4\0\0'\6\1\0B\4\2\0029\4\3\0049\4\4\0049\4\5\4>\4\1\0036\4\0\0'\6\1\0B\4\2\0029\4\3\0049\4\6\0049\4\a\4>\4\2\3=\3\t\2B\0\2\1K\0\1\0\fsources\1\0\0\vstylua\15formatting\reslint_d\16diagnostics\rbuiltins\nsetup\fnull-ls\frequire\0", "config", "null-ls.nvim")
time([[Config for null-ls.nvim]], false)
-- Config for: indent-blankline.nvim
time([[Config for indent-blankline.nvim]], true)
try_loadstring("\27LJ\2\n\1\0\0\4\0\b\0\0146\0\0\0009\0\1\0009\0\2\0\18\2\0\0009\0\3\0'\3\4\0B\0\3\0016\0\5\0'\2\6\0B\0\2\0029\0\a\0004\2\0\0B\0\2\1K\0\1\0\nsetup\21indent_blankline\frequire\14space:â‹…\vappend\14listchars\bopt\bvim\0", "config", "indent-blankline.nvim")
time([[Config for indent-blankline.nvim]], false)
-- Config for: alpha-nvim
time([[Config for alpha-nvim]], true)
try_loadstring("\27LJ\2\n`\0\0\5\0\5\0\n6\0\0\0'\2\1\0B\0\2\0029\0\2\0006\2\0\0'\4\3\0B\2\2\0029\2\4\2B\0\2\1K\0\1\0\vconfig\26alpha.themes.startify\nsetup\nalpha\frequire\0", "config", "alpha-nvim")
time([[Config for alpha-nvim]], false)
-- Config for: todo-comments.nvim
time([[Config for todo-comments.nvim]], true)
try_loadstring("\27LJ\2\n?\0\0\3\0\3\0\a6\0\0\0'\2\1\0B\0\2\0029\0\2\0004\2\0\0B\0\2\1K\0\1\0\nsetup\18todo-comments\frequire\0", "config", "todo-comments.nvim")
time([[Config for todo-comments.nvim]], false)
-- Config for: asset-bender.nvim
time([[Config for asset-bender.nvim]], true)
try_loadstring("\27LJ\2\n>\0\0\3\0\3\0\a6\0\0\0'\2\1\0B\0\2\0029\0\2\0004\2\0\0B\0\2\1K\0\1\0\nsetup\17asset-bender\frequire\0", "config", "asset-bender.nvim")
time([[Config for asset-bender.nvim]], false)
-- Config for: Comment.nvim
time([[Config for Comment.nvim]], true)
try_loadstring("\27LJ\2\n§\3\0\1\b\0\18\00006\1\0\0'\3\1\0B\1\2\2+\2\0\0009\3\2\0009\4\2\0019\4\3\4\5\3\4\0X\3\a€6\3\0\0'\5\4\0B\3\2\0029\3\5\3B\3\1\2\18\2\3\0X\3\16€9\3\6\0009\4\6\0019\4\a\4\4\3\4\0X\3\5€9\3\6\0009\4\6\0019\4\b\4\5\3\4\0X\3\6€6\3\0\0'\5\4\0B\3\2\0029\3\t\3B\3\1\2\18\2\3\0006\3\0\0'\5\n\0B\3\2\0029\3\v\0035\5\14\0009\6\2\0009\a\2\0019\a\f\a\5\6\a\0X\6\2€'\6\r\0X\a\1€'\6\15\0=\6\16\5=\2\17\5D\3\2\0\rlocation\bkey\16__multiline\1\0\0\14__default\tline\28calculate_commentstring&ts_context_commentstring.internal\30get_visual_start_location\6V\6v\fcmotion\24get_cursor_location#ts_context_commentstring.utils\nblock\nctype\18Comment.utils\frequireN\1\0\4\0\6\0\t6\0\0\0'\2\1\0B\0\2\0029\0\2\0005\2\4\0003\3\3\0=\3\5\2B\0\2\1K\0\1\0\rpre_hook\1\0\0\0\nsetup\fComment\frequire\0", "config", "Comment.nvim")
time([[Config for Comment.nvim]], false)
-- Config for: lualine.nvim
time([[Config for lualine.nvim]], true)
try_loadstring("\27LJ\2\n/\0\0\3\0\4\0\0056\0\0\0009\0\1\0009\0\2\0'\2\3\0D\0\2\0\n%:~:.\vexpand\afn\bvimà\4\1\0\b\0\30\00053\0\0\0006\1\1\0'\3\2\0B\1\2\0029\1\3\0015\3\a\0005\4\4\0005\5\5\0=\5\6\4=\4\b\0035\4\f\0004\5\3\0005\6\t\0005\a\n\0=\a\v\6>\6\1\5=\5\r\0045\5\14\0=\5\15\0044\5\3\0>\0\1\5=\5\16\0044\5\0\0=\5\17\0045\5\18\0=\5\19\0044\5\3\0005\6\20\0005\a\21\0=\a\v\6>\6\1\5=\5\22\4=\4\23\0035\4\25\0005\5\24\0=\5\r\0044\5\0\0=\5\15\0044\5\0\0=\5\16\0044\5\0\0=\5\17\0044\5\0\0=\5\19\0045\5\26\0=\5\22\4=\4\27\0034\4\0\0=\4\28\0034\4\0\0=\4\29\3B\1\2\1K\0\1\0\15extensions\ftabline\22inactive_sections\1\2\0\0\rlocation\1\0\0\1\2\0\0\rfilename\rsections\14lualine_z\1\0\1\nright\bî‚´\1\2\1\0\rlocation\17left_padding\3\2\14lualine_y\1\4\0\0\rfiletype\tdiff\rprogress\14lualine_x\14lualine_c\14lualine_b\1\3\0\0\rfilename\vbranch\14lualine_a\1\0\0\14separator\1\0\1\tleft\bî‚¶\1\2\1\0\tmode\18right_padding\3\2\foptions\1\0\0\23section_separators\1\0\2\nright\bî‚¶\tleft\bî‚´\1\0\2\25component_separators\6|\ntheme\ronelight\nsetup\flualine\frequire\0\0", "config", "lualine.nvim")
time([[Config for lualine.nvim]], false)
-- Config for: gitsigns.nvim
time([[Config for gitsigns.nvim]], true)
try_loadstring("\27LJ\2\n6\0\0\3\0\3\0\0066\0\0\0'\2\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\nsetup\rgitsigns\frequire\0", "config", "gitsigns.nvim")
time([[Config for gitsigns.nvim]], false)
-- Config for: nvim-ts-context-commentstring
time([[Config for nvim-ts-context-commentstring]], true)
try_loadstring("\27LJ\2\n…\1\0\0\4\0\6\0\t6\0\0\0'\2\1\0B\0\2\0029\0\2\0005\2\4\0005\3\3\0=\3\5\2B\0\2\1K\0\1\0\26context_commentstring\1\0\0\1\0\2\venable\2\19enable_autocmd\1\nsetup\28nvim-treesitter.configs\frequire\0", "config", "nvim-ts-context-commentstring")
time([[Config for nvim-ts-context-commentstring]], false)
if should_profile then save_profiles() end

end)

if not no_errors then
  error_msg = error_msg:gsub('"', '\\"')
  vim.api.nvim_command('echohl ErrorMsg | echom "Error in packer_compiled: '..error_msg..'" | echom "Please check your config for correctness" | echohl None')
end
