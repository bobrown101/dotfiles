-- Automatically generated packer.nvim plugin loader code

if vim.api.nvim_call_function('has', {'nvim-0.5'}) ~= 1 then
  vim.api.nvim_command('echohl WarningMsg | echom "Invalid Neovim version for packer.nvim! | echohl None"')
  return
end

vim.api.nvim_command('packadd packer.nvim')

local no_errors, error_msg = pcall(function()

_G._packer = _G._packer or {}
_G._packer.inside_compile = true

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
  if threshold then
    table.insert(results, '(Only showing plugins that took longer than ' .. threshold .. ' ms ' .. 'to load)')
  end

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
    config = { "\27LJ\2\nß\3\0\1\b\0\18\00006\1\0\0'\3\1\0B\1\2\2+\2\0\0009\3\2\0009\4\2\0019\4\3\4\5\3\4\0X\3\aÄ6\3\0\0'\5\4\0B\3\2\0029\3\5\3B\3\1\2\18\2\3\0X\3\16Ä9\3\6\0009\4\6\0019\4\a\4\4\3\4\0X\3\5Ä9\3\6\0009\4\6\0019\4\b\4\5\3\4\0X\3\6Ä6\3\0\0'\5\4\0B\3\2\0029\3\t\3B\3\1\2\18\2\3\0006\3\0\0'\5\n\0B\3\2\0029\3\v\0035\5\14\0009\6\2\0009\a\2\0019\a\f\a\5\6\a\0X\6\2Ä'\6\r\0X\a\1Ä'\6\15\0=\6\16\5=\2\17\5D\3\2\0\rlocation\bkey\16__multiline\1\0\0\14__default\tline\28calculate_commentstring&ts_context_commentstring.internal\30get_visual_start_location\6V\6v\fcmotion\24get_cursor_location#ts_context_commentstring.utils\nblock\nctype\18Comment.utils\frequireN\1\0\4\0\6\0\t6\0\0\0'\2\1\0B\0\2\0029\0\2\0005\2\4\0003\3\3\0=\3\5\2B\0\2\1K\0\1\0\rpre_hook\1\0\0\0\nsetup\fComment\frequire\0" },
    loaded = true,
    path = "/Users/brbrown/.local/share/nvim/site/pack/packer/start/Comment.nvim",
    url = "https://github.com/numToStr/Comment.nvim"
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
  ["fff.nvim"] = {
    loaded = true,
    path = "/Users/brbrown/.local/share/nvim/site/pack/packer/start/fff.nvim",
    url = "https://github.com/bobrown101/fff.nvim"
  },
  ["formatter.nvim"] = {
    loaded = true,
    path = "/Users/brbrown/.local/share/nvim/site/pack/packer/start/formatter.nvim",
    url = "https://github.com/mhartington/formatter.nvim"
  },
  ["git_blame.nvim"] = {
    loaded = true,
    path = "/Users/brbrown/.local/share/nvim/site/pack/packer/start/git_blame.nvim",
    url = "https://github.com/bobrown101/git_blame.nvim"
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
    url = "/Users/brbrown/Developer/hubspot-js-utils.nvim"
  },
  ["indent-blankline.nvim"] = {
    config = { "\27LJ\2\nÅ\1\0\0\4\0\b\0\0146\0\0\0009\0\1\0009\0\2\0\18\2\0\0009\0\3\0'\3\4\0B\0\3\0016\0\5\0'\2\6\0B\0\2\0029\0\a\0004\2\0\0B\0\2\1K\0\1\0\nsetup\21indent_blankline\frequire\14space:‚ãÖ\vappend\14listchars\bopt\bvim\0" },
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
    config = { "\27LJ\2\n/\0\0\3\0\4\0\0056\0\0\0009\0\1\0009\0\2\0'\2\3\0D\0\2\0\n%:~:.\vexpand\afn\bvim–\4\1\0\b\0\30\00033\0\0\0006\1\1\0'\3\2\0B\1\2\0029\1\3\0015\3\a\0005\4\4\0005\5\5\0=\5\6\4=\4\b\0035\4\f\0004\5\3\0005\6\t\0005\a\n\0=\a\v\6>\6\1\5=\5\r\0045\5\14\0>\0\1\5=\5\15\0044\5\0\0=\5\16\0045\5\17\0=\5\18\0044\5\3\0005\6\19\0005\a\20\0=\a\v\6>\6\1\5=\5\21\4=\4\22\0035\4\24\0005\5\23\0=\5\r\0044\5\0\0=\5\15\0044\5\0\0=\5\25\0044\5\0\0=\5\16\0044\5\0\0=\5\18\0045\5\26\0=\5\21\4=\4\27\0034\4\0\0=\4\28\0034\4\0\0=\4\29\3B\1\2\1K\0\1\0\15extensions\ftabline\22inactive_sections\1\2\0\0\rlocation\14lualine_c\1\0\0\1\2\0\0\rfilename\rsections\14lualine_z\1\0\1\nright\bÓÇ¥\1\2\1\0\rlocation\17left_padding\3\2\14lualine_y\1\4\0\0\rfiletype\tdiff\rprogress\14lualine_x\14lualine_b\1\3\0\0\0\vbranch\14lualine_a\1\0\0\14separator\1\0\1\tleft\bÓÇ∂\1\2\1\0\tmode\18right_padding\3\2\foptions\1\0\0\23section_separators\1\0\2\nright\bÓÇ∂\tleft\bÓÇ¥\1\0\2\ntheme\ronelight\25component_separators\6|\nsetup\flualine\frequire\0\0" },
    loaded = true,
    path = "/Users/brbrown/.local/share/nvim/site/pack/packer/start/lualine.nvim",
    url = "https://github.com/nvim-lualine/lualine.nvim"
  },
  ["null-ls.nvim"] = {
    config = { "\27LJ\2\n≤\1\0\0\a\0\n\0\0236\0\0\0'\2\1\0B\0\2\0029\0\2\0005\2\b\0004\3\3\0006\4\0\0'\6\1\0B\4\2\0029\4\3\0049\4\4\0049\4\5\4>\4\1\0036\4\0\0'\6\1\0B\4\2\0029\4\3\0049\4\6\0049\4\a\4>\4\2\3=\3\t\2B\0\2\1K\0\1\0\fsources\1\0\0\vstylua\15formatting\veslint\16diagnostics\rbuiltins\nsetup\fnull-ls\frequire\0" },
    loaded = true,
    path = "/Users/brbrown/.local/share/nvim/site/pack/packer/start/null-ls.nvim",
    url = "https://github.com/jose-elias-alvarez/null-ls.nvim"
  },
  ["nvim-cmp"] = {
    config = { "\27LJ\2\nC\0\1\4\0\4\0\a6\1\0\0'\3\1\0B\1\2\0029\1\2\0019\3\3\0B\1\2\1K\0\1\0\tbody\15lsp_expand\fluasnip\frequireR\0\1\3\1\2\0\f-\1\0\0009\1\0\1B\1\1\2\15\0\1\0X\2\4Ä-\1\0\0009\1\1\1B\1\1\1X\1\2Ä\18\1\0\0B\1\1\1K\0\1\0\0¿\21select_next_item\fvisibleR\0\1\3\1\2\0\f-\1\0\0009\1\0\1B\1\1\2\15\0\1\0X\2\4Ä-\1\0\0009\1\1\1B\1\1\1X\1\2Ä\18\1\0\0B\1\1\1K\0\1\0\0¿\21select_prev_item\fvisibleÛ\1\0\2\5\1\b\0\15-\2\0\0009\2\1\0029\2\2\0029\3\0\0018\2\3\2'\3\3\0009\4\0\1&\2\4\2=\2\0\0015\2\5\0009\3\6\0009\3\a\0038\2\3\2=\2\4\1L\1\2\0\1¿\tname\vsource\1\0\6\vbuffer\r[Buffer]\rnvim_lua\n[Lua]\fluasnip\14[LuaSnip]\rnvim_lsp\n[LSP]#nvim_cmp_hs_translation_source\18[Translation]\18latex_symbols\f[Latex]\tmenu\6 \fdefault\fpresets\tkindì\4\1\0\f\0\"\00086\0\0\0'\2\1\0B\0\2\0026\1\0\0'\3\2\0B\1\2\0024\2\b\0005\3\3\0>\3\1\0025\3\4\0>\3\2\0025\3\5\0>\3\3\0025\3\6\0>\3\4\0025\3\a\0>\3\5\0025\3\b\0>\3\6\0025\3\t\0>\3\a\0029\3\n\0005\5\14\0005\6\f\0003\a\v\0=\a\r\6=\6\15\0055\6\17\0003\a\16\0=\a\18\0063\a\19\0=\a\20\0069\a\21\0009\t\21\0009\t\22\tB\t\1\0025\n\23\0B\a\3\2=\a\24\0069\a\21\0009\t\21\0009\t\25\t5\v\26\0B\t\2\0025\n\27\0B\a\3\2=\a\28\6=\6\21\5=\2\29\0055\6\31\0003\a\30\0=\a \6=\6!\5B\3\2\0012\0\0ÄK\0\1\0\15formatting\vformat\1\0\0\0\fsources\t<CR>\1\3\0\0\6i\6s\1\0\1\vselect\2\fconfirm\14<C-Space>\1\3\0\0\6i\6s\rcomplete\fmapping\f<S-Tab>\0\n<Tab>\1\0\0\0\fsnippet\1\0\0\vexpand\1\0\0\0\nsetup\1\0\1\tname#nvim_cmp_hs_translation_source\1\0\1\tname\15treesitter\1\0\1\tname\rnvim_lua\1\0\1\tname\vbuffer\1\0\1\tname\fluasnip\1\0\1\tname\rnvim_lsp\1\0\1\tname\tpath\flspkind\bcmp\frequire\0" },
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
    config = { "\27LJ\2\n \1\0\0\5\0\n\0\r6\0\0\0'\2\1\0B\0\2\0029\1\2\0005\3\3\0005\4\4\0=\4\5\0035\4\6\0=\4\a\0035\4\b\0=\4\t\3B\1\2\1K\0\1\0\26context_commentstring\1\0\1\venable\2\14highlight\1\0\1\venable\2\19ignore_install\1\2\0\0\fhaskell\1\0\1\21ensure_installed\ball\nsetup\28nvim-treesitter.configs\frequire\0" },
    loaded = true,
    path = "/Users/brbrown/.local/share/nvim/site/pack/packer/start/nvim-treesitter",
    url = "https://github.com/nvim-treesitter/nvim-treesitter"
  },
  ["nvim-ts-context-commentstring"] = {
    config = { "\27LJ\2\nÖ\1\0\0\4\0\6\0\t6\0\0\0'\2\1\0B\0\2\0029\0\2\0005\2\4\0005\3\3\0=\3\5\2B\0\2\1K\0\1\0\26context_commentstring\1\0\0\1\0\2\venable\2\19enable_autocmd\1\nsetup\28nvim-treesitter.configs\frequire\0" },
    loaded = true,
    path = "/Users/brbrown/.local/share/nvim/site/pack/packer/start/nvim-ts-context-commentstring",
    url = "https://github.com/JoosepAlviste/nvim-ts-context-commentstring"
  },
  ["nvim-web-devicons"] = {
    loaded = true,
    path = "/Users/brbrown/.local/share/nvim/site/pack/packer/start/nvim-web-devicons",
    url = "https://github.com/kyazdani42/nvim-web-devicons"
  },
  nvim_cmp_hs_translation_source = {
    config = { "\27LJ\2\nL\0\0\3\0\3\0\0066\0\0\0'\2\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\nsetup#nvim_cmp_hs_translation_source\frequire\0" },
    loaded = true,
    path = "/Users/brbrown/.local/share/nvim/site/pack/packer/start/nvim_cmp_hs_translation_source",
    url = "https://github.com/bobrown101/nvim_cmp_hs_translation_source"
  },
  ["packer.nvim"] = {
    loaded = true,
    path = "/Users/brbrown/.local/share/nvim/site/pack/packer/start/packer.nvim",
    url = "https://github.com/wbthomason/packer.nvim"
  },
  playground = {
    loaded = true,
    path = "/Users/brbrown/.local/share/nvim/site/pack/packer/start/playground",
    url = "https://github.com/nvim-treesitter/playground"
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
    config = { "\27LJ\2\n`\0\0\4\0\6\0\t6\0\0\0'\2\1\0B\0\2\0029\0\2\0005\2\4\0005\3\3\0=\3\5\2B\0\2\1K\0\1\0\rdefaults\1\0\0\1\0\1\17wrap_results\2\nsetup\14telescope\frequire\0" },
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
  },
  ["ts-highlight-implicit-any.nvim"] = {
    loaded = true,
    path = "/Users/brbrown/.local/share/nvim/site/pack/packer/start/ts-highlight-implicit-any.nvim",
    url = "/Users/brbrown/Developer/ts-highlight-implicit-any.nvim"
  },
  ["which-key.nvim"] = {
    config = { "\27LJ\2\n5\0\0\2\0\3\0\0056\0\0\0009\0\1\0009\0\2\0B\0\1\1K\0\1\0\15open_float\15diagnostic\bvim=\0\0\3\0\3\0\0066\0\0\0'\2\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\20telescope_files\ntools\frequire<\0\0\3\0\3\0\0066\0\0\0'\2\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\19telescope_grep\ntools\frequire)\0\0\3\0\3\0\0056\0\0\0009\0\1\0'\2\2\0B\0\2\1K\0\1\0\nsplit\bcmd\bvim*\0\0\3\0\3\0\0056\0\0\0009\0\1\0'\2\2\0B\0\2\1K\0\1\0\vvsplit\bcmd\bvim5\0\0\3\0\3\0\0066\0\0\0'\2\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\brun\14git_blame\frequireB\0\0\3\0\3\0\0066\0\0\0'\2\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\14test_file\21hubspot-js-utils\frequireE\0\0\3\0\4\0\t6\0\0\0009\0\1\0'\2\2\0B\0\2\0016\0\0\0009\0\1\0'\2\3\0B\0\2\1K\0\1\0\16startinsert\nterm \bcmd\bvim1\0\0\3\0\3\0\0066\0\0\0'\2\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\nstart\bfff\frequire≈\1\0\0\6\0\b\0\0146\0\0\0'\2\1\0B\0\2\0029\0\2\0006\2\0\0'\4\3\0B\2\2\0029\2\4\0025\4\5\0005\5\6\0=\5\a\4B\2\2\0A\0\0\1K\0\1\0\18layout_config\1\0\2\nwidth\4Õô≥Ê\fÃô≥ˇ\3\vheight\4≥ÊÃô\3≥ÊÃ˛\3\1\0\1\18sort_lastused\2\17get_dropdown\21telescope.themes\fbuffers\22telescope.builtin\frequire.\0\0\3\0\3\0\0056\0\0\0009\0\1\0'\2\2\0B\0\2\1K\0\1\0\15stopinsert\bcmd\bvimµ\5\1\0\a\0000\0G6\0\0\0'\2\1\0B\0\2\0029\1\2\0004\3\0\0B\1\2\0019\1\3\0005\3\b\0005\4\4\0005\5\6\0003\6\5\0>\6\1\5=\5\a\4=\4\a\0035\4\t\0005\5\v\0003\6\n\0>\6\1\5=\5\f\4=\4\f\0035\4\r\0005\5\15\0003\6\14\0>\6\1\5=\5\16\0045\5\18\0003\6\17\0>\6\1\5=\5\19\0045\5\21\0003\6\20\0>\6\1\5=\5\22\4=\4\16\0035\4\25\0005\5\24\0003\6\23\0>\6\1\5=\5\26\0045\5\28\0003\6\27\0>\6\1\5=\5\29\4=\4\30\0035\4\31\0B\1\3\0019\1\3\0005\3\"\0005\4!\0003\5 \0>\5\1\4=\4#\0035\4%\0003\5$\0>\5\1\4=\4&\0035\4(\0003\5'\0>\5\1\4=\4)\0035\4*\0B\1\3\0019\1\3\0005\3-\0005\4,\0003\5+\0>\5\1\4=\4.\0035\4/\0B\1\3\1K\0\1\0\1\0\2\vprefix\n<esc>\tmode\6t\n<esc>\1\0\0\1\3\0\0\0 Escape terminal insert mode\0\1\0\1\tmode\6n\n<tab>\1\3\0\0\0\29toggle floating terminal\0\6-\1\3\0\0\0\bNNN\0\6_\1\0\0\1\3\0\0\0\bNNN\0\1\0\1\vprefix\r<leader>\6g\6t\1\3\0\0\0\14Test File\0\6b\1\0\0\1\3\0\0\0\14Git Blame\0\6v\1\3\0\0\0\19Split Vertical\0\6h\1\3\0\0\0\21Split Horizontal\0\6s\1\3\0\0\0\18Search String\0\1\0\1\tname\vSearch\6f\1\3\0\0\0\14Find File\0\1\0\1\tname\tfile\1\0\0\6d\1\3\0\0\0\26Open diagnostic float\0\1\0\1\tname\16Diagnostics\rregister\nsetup\14which-key\frequire\0" },
    loaded = true,
    path = "/Users/brbrown/.local/share/nvim/site/pack/packer/start/which-key.nvim",
    url = "https://github.com/folke/which-key.nvim"
  }
}

time([[Defining packer_plugins]], false)
-- Config for: asset-bender.nvim
time([[Config for asset-bender.nvim]], true)
try_loadstring("\27LJ\2\n>\0\0\3\0\3\0\a6\0\0\0'\2\1\0B\0\2\0029\0\2\0004\2\0\0B\0\2\1K\0\1\0\nsetup\17asset-bender\frequire\0", "config", "asset-bender.nvim")
time([[Config for asset-bender.nvim]], false)
-- Config for: nvim-cmp
time([[Config for nvim-cmp]], true)
try_loadstring("\27LJ\2\nC\0\1\4\0\4\0\a6\1\0\0'\3\1\0B\1\2\0029\1\2\0019\3\3\0B\1\2\1K\0\1\0\tbody\15lsp_expand\fluasnip\frequireR\0\1\3\1\2\0\f-\1\0\0009\1\0\1B\1\1\2\15\0\1\0X\2\4Ä-\1\0\0009\1\1\1B\1\1\1X\1\2Ä\18\1\0\0B\1\1\1K\0\1\0\0¿\21select_next_item\fvisibleR\0\1\3\1\2\0\f-\1\0\0009\1\0\1B\1\1\2\15\0\1\0X\2\4Ä-\1\0\0009\1\1\1B\1\1\1X\1\2Ä\18\1\0\0B\1\1\1K\0\1\0\0¿\21select_prev_item\fvisibleÛ\1\0\2\5\1\b\0\15-\2\0\0009\2\1\0029\2\2\0029\3\0\0018\2\3\2'\3\3\0009\4\0\1&\2\4\2=\2\0\0015\2\5\0009\3\6\0009\3\a\0038\2\3\2=\2\4\1L\1\2\0\1¿\tname\vsource\1\0\6\vbuffer\r[Buffer]\rnvim_lua\n[Lua]\fluasnip\14[LuaSnip]\rnvim_lsp\n[LSP]#nvim_cmp_hs_translation_source\18[Translation]\18latex_symbols\f[Latex]\tmenu\6 \fdefault\fpresets\tkindì\4\1\0\f\0\"\00086\0\0\0'\2\1\0B\0\2\0026\1\0\0'\3\2\0B\1\2\0024\2\b\0005\3\3\0>\3\1\0025\3\4\0>\3\2\0025\3\5\0>\3\3\0025\3\6\0>\3\4\0025\3\a\0>\3\5\0025\3\b\0>\3\6\0025\3\t\0>\3\a\0029\3\n\0005\5\14\0005\6\f\0003\a\v\0=\a\r\6=\6\15\0055\6\17\0003\a\16\0=\a\18\0063\a\19\0=\a\20\0069\a\21\0009\t\21\0009\t\22\tB\t\1\0025\n\23\0B\a\3\2=\a\24\0069\a\21\0009\t\21\0009\t\25\t5\v\26\0B\t\2\0025\n\27\0B\a\3\2=\a\28\6=\6\21\5=\2\29\0055\6\31\0003\a\30\0=\a \6=\6!\5B\3\2\0012\0\0ÄK\0\1\0\15formatting\vformat\1\0\0\0\fsources\t<CR>\1\3\0\0\6i\6s\1\0\1\vselect\2\fconfirm\14<C-Space>\1\3\0\0\6i\6s\rcomplete\fmapping\f<S-Tab>\0\n<Tab>\1\0\0\0\fsnippet\1\0\0\vexpand\1\0\0\0\nsetup\1\0\1\tname#nvim_cmp_hs_translation_source\1\0\1\tname\15treesitter\1\0\1\tname\rnvim_lua\1\0\1\tname\vbuffer\1\0\1\tname\fluasnip\1\0\1\tname\rnvim_lsp\1\0\1\tname\tpath\flspkind\bcmp\frequire\0", "config", "nvim-cmp")
time([[Config for nvim-cmp]], false)
-- Config for: nvim-ts-context-commentstring
time([[Config for nvim-ts-context-commentstring]], true)
try_loadstring("\27LJ\2\nÖ\1\0\0\4\0\6\0\t6\0\0\0'\2\1\0B\0\2\0029\0\2\0005\2\4\0005\3\3\0=\3\5\2B\0\2\1K\0\1\0\26context_commentstring\1\0\0\1\0\2\venable\2\19enable_autocmd\1\nsetup\28nvim-treesitter.configs\frequire\0", "config", "nvim-ts-context-commentstring")
time([[Config for nvim-ts-context-commentstring]], false)
-- Config for: null-ls.nvim
time([[Config for null-ls.nvim]], true)
try_loadstring("\27LJ\2\n≤\1\0\0\a\0\n\0\0236\0\0\0'\2\1\0B\0\2\0029\0\2\0005\2\b\0004\3\3\0006\4\0\0'\6\1\0B\4\2\0029\4\3\0049\4\4\0049\4\5\4>\4\1\0036\4\0\0'\6\1\0B\4\2\0029\4\3\0049\4\6\0049\4\a\4>\4\2\3=\3\t\2B\0\2\1K\0\1\0\fsources\1\0\0\vstylua\15formatting\veslint\16diagnostics\rbuiltins\nsetup\fnull-ls\frequire\0", "config", "null-ls.nvim")
time([[Config for null-ls.nvim]], false)
-- Config for: Comment.nvim
time([[Config for Comment.nvim]], true)
try_loadstring("\27LJ\2\nß\3\0\1\b\0\18\00006\1\0\0'\3\1\0B\1\2\2+\2\0\0009\3\2\0009\4\2\0019\4\3\4\5\3\4\0X\3\aÄ6\3\0\0'\5\4\0B\3\2\0029\3\5\3B\3\1\2\18\2\3\0X\3\16Ä9\3\6\0009\4\6\0019\4\a\4\4\3\4\0X\3\5Ä9\3\6\0009\4\6\0019\4\b\4\5\3\4\0X\3\6Ä6\3\0\0'\5\4\0B\3\2\0029\3\t\3B\3\1\2\18\2\3\0006\3\0\0'\5\n\0B\3\2\0029\3\v\0035\5\14\0009\6\2\0009\a\2\0019\a\f\a\5\6\a\0X\6\2Ä'\6\r\0X\a\1Ä'\6\15\0=\6\16\5=\2\17\5D\3\2\0\rlocation\bkey\16__multiline\1\0\0\14__default\tline\28calculate_commentstring&ts_context_commentstring.internal\30get_visual_start_location\6V\6v\fcmotion\24get_cursor_location#ts_context_commentstring.utils\nblock\nctype\18Comment.utils\frequireN\1\0\4\0\6\0\t6\0\0\0'\2\1\0B\0\2\0029\0\2\0005\2\4\0003\3\3\0=\3\5\2B\0\2\1K\0\1\0\rpre_hook\1\0\0\0\nsetup\fComment\frequire\0", "config", "Comment.nvim")
time([[Config for Comment.nvim]], false)
-- Config for: telescope.nvim
time([[Config for telescope.nvim]], true)
try_loadstring("\27LJ\2\n`\0\0\4\0\6\0\t6\0\0\0'\2\1\0B\0\2\0029\0\2\0005\2\4\0005\3\3\0=\3\5\2B\0\2\1K\0\1\0\rdefaults\1\0\0\1\0\1\17wrap_results\2\nsetup\14telescope\frequire\0", "config", "telescope.nvim")
time([[Config for telescope.nvim]], false)
-- Config for: lualine.nvim
time([[Config for lualine.nvim]], true)
try_loadstring("\27LJ\2\n/\0\0\3\0\4\0\0056\0\0\0009\0\1\0009\0\2\0'\2\3\0D\0\2\0\n%:~:.\vexpand\afn\bvim–\4\1\0\b\0\30\00033\0\0\0006\1\1\0'\3\2\0B\1\2\0029\1\3\0015\3\a\0005\4\4\0005\5\5\0=\5\6\4=\4\b\0035\4\f\0004\5\3\0005\6\t\0005\a\n\0=\a\v\6>\6\1\5=\5\r\0045\5\14\0>\0\1\5=\5\15\0044\5\0\0=\5\16\0045\5\17\0=\5\18\0044\5\3\0005\6\19\0005\a\20\0=\a\v\6>\6\1\5=\5\21\4=\4\22\0035\4\24\0005\5\23\0=\5\r\0044\5\0\0=\5\15\0044\5\0\0=\5\25\0044\5\0\0=\5\16\0044\5\0\0=\5\18\0045\5\26\0=\5\21\4=\4\27\0034\4\0\0=\4\28\0034\4\0\0=\4\29\3B\1\2\1K\0\1\0\15extensions\ftabline\22inactive_sections\1\2\0\0\rlocation\14lualine_c\1\0\0\1\2\0\0\rfilename\rsections\14lualine_z\1\0\1\nright\bÓÇ¥\1\2\1\0\rlocation\17left_padding\3\2\14lualine_y\1\4\0\0\rfiletype\tdiff\rprogress\14lualine_x\14lualine_b\1\3\0\0\0\vbranch\14lualine_a\1\0\0\14separator\1\0\1\tleft\bÓÇ∂\1\2\1\0\tmode\18right_padding\3\2\foptions\1\0\0\23section_separators\1\0\2\nright\bÓÇ∂\tleft\bÓÇ¥\1\0\2\ntheme\ronelight\25component_separators\6|\nsetup\flualine\frequire\0\0", "config", "lualine.nvim")
time([[Config for lualine.nvim]], false)
-- Config for: gitsigns.nvim
time([[Config for gitsigns.nvim]], true)
try_loadstring("\27LJ\2\n6\0\0\3\0\3\0\0066\0\0\0'\2\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\nsetup\rgitsigns\frequire\0", "config", "gitsigns.nvim")
time([[Config for gitsigns.nvim]], false)
-- Config for: nvim_cmp_hs_translation_source
time([[Config for nvim_cmp_hs_translation_source]], true)
try_loadstring("\27LJ\2\nL\0\0\3\0\3\0\0066\0\0\0'\2\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\nsetup#nvim_cmp_hs_translation_source\frequire\0", "config", "nvim_cmp_hs_translation_source")
time([[Config for nvim_cmp_hs_translation_source]], false)
-- Config for: todo-comments.nvim
time([[Config for todo-comments.nvim]], true)
try_loadstring("\27LJ\2\n?\0\0\3\0\3\0\a6\0\0\0'\2\1\0B\0\2\0029\0\2\0004\2\0\0B\0\2\1K\0\1\0\nsetup\18todo-comments\frequire\0", "config", "todo-comments.nvim")
time([[Config for todo-comments.nvim]], false)
-- Config for: which-key.nvim
time([[Config for which-key.nvim]], true)
try_loadstring("\27LJ\2\n5\0\0\2\0\3\0\0056\0\0\0009\0\1\0009\0\2\0B\0\1\1K\0\1\0\15open_float\15diagnostic\bvim=\0\0\3\0\3\0\0066\0\0\0'\2\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\20telescope_files\ntools\frequire<\0\0\3\0\3\0\0066\0\0\0'\2\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\19telescope_grep\ntools\frequire)\0\0\3\0\3\0\0056\0\0\0009\0\1\0'\2\2\0B\0\2\1K\0\1\0\nsplit\bcmd\bvim*\0\0\3\0\3\0\0056\0\0\0009\0\1\0'\2\2\0B\0\2\1K\0\1\0\vvsplit\bcmd\bvim5\0\0\3\0\3\0\0066\0\0\0'\2\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\brun\14git_blame\frequireB\0\0\3\0\3\0\0066\0\0\0'\2\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\14test_file\21hubspot-js-utils\frequireE\0\0\3\0\4\0\t6\0\0\0009\0\1\0'\2\2\0B\0\2\0016\0\0\0009\0\1\0'\2\3\0B\0\2\1K\0\1\0\16startinsert\nterm \bcmd\bvim1\0\0\3\0\3\0\0066\0\0\0'\2\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\nstart\bfff\frequire≈\1\0\0\6\0\b\0\0146\0\0\0'\2\1\0B\0\2\0029\0\2\0006\2\0\0'\4\3\0B\2\2\0029\2\4\0025\4\5\0005\5\6\0=\5\a\4B\2\2\0A\0\0\1K\0\1\0\18layout_config\1\0\2\nwidth\4Õô≥Ê\fÃô≥ˇ\3\vheight\4≥ÊÃô\3≥ÊÃ˛\3\1\0\1\18sort_lastused\2\17get_dropdown\21telescope.themes\fbuffers\22telescope.builtin\frequire.\0\0\3\0\3\0\0056\0\0\0009\0\1\0'\2\2\0B\0\2\1K\0\1\0\15stopinsert\bcmd\bvimµ\5\1\0\a\0000\0G6\0\0\0'\2\1\0B\0\2\0029\1\2\0004\3\0\0B\1\2\0019\1\3\0005\3\b\0005\4\4\0005\5\6\0003\6\5\0>\6\1\5=\5\a\4=\4\a\0035\4\t\0005\5\v\0003\6\n\0>\6\1\5=\5\f\4=\4\f\0035\4\r\0005\5\15\0003\6\14\0>\6\1\5=\5\16\0045\5\18\0003\6\17\0>\6\1\5=\5\19\0045\5\21\0003\6\20\0>\6\1\5=\5\22\4=\4\16\0035\4\25\0005\5\24\0003\6\23\0>\6\1\5=\5\26\0045\5\28\0003\6\27\0>\6\1\5=\5\29\4=\4\30\0035\4\31\0B\1\3\0019\1\3\0005\3\"\0005\4!\0003\5 \0>\5\1\4=\4#\0035\4%\0003\5$\0>\5\1\4=\4&\0035\4(\0003\5'\0>\5\1\4=\4)\0035\4*\0B\1\3\0019\1\3\0005\3-\0005\4,\0003\5+\0>\5\1\4=\4.\0035\4/\0B\1\3\1K\0\1\0\1\0\2\vprefix\n<esc>\tmode\6t\n<esc>\1\0\0\1\3\0\0\0 Escape terminal insert mode\0\1\0\1\tmode\6n\n<tab>\1\3\0\0\0\29toggle floating terminal\0\6-\1\3\0\0\0\bNNN\0\6_\1\0\0\1\3\0\0\0\bNNN\0\1\0\1\vprefix\r<leader>\6g\6t\1\3\0\0\0\14Test File\0\6b\1\0\0\1\3\0\0\0\14Git Blame\0\6v\1\3\0\0\0\19Split Vertical\0\6h\1\3\0\0\0\21Split Horizontal\0\6s\1\3\0\0\0\18Search String\0\1\0\1\tname\vSearch\6f\1\3\0\0\0\14Find File\0\1\0\1\tname\tfile\1\0\0\6d\1\3\0\0\0\26Open diagnostic float\0\1\0\1\tname\16Diagnostics\rregister\nsetup\14which-key\frequire\0", "config", "which-key.nvim")
time([[Config for which-key.nvim]], false)
-- Config for: alpha-nvim
time([[Config for alpha-nvim]], true)
try_loadstring("\27LJ\2\n`\0\0\5\0\5\0\n6\0\0\0'\2\1\0B\0\2\0029\0\2\0006\2\0\0'\4\3\0B\2\2\0029\2\4\2B\0\2\1K\0\1\0\vconfig\26alpha.themes.startify\nsetup\nalpha\frequire\0", "config", "alpha-nvim")
time([[Config for alpha-nvim]], false)
-- Config for: indent-blankline.nvim
time([[Config for indent-blankline.nvim]], true)
try_loadstring("\27LJ\2\nÅ\1\0\0\4\0\b\0\0146\0\0\0009\0\1\0009\0\2\0\18\2\0\0009\0\3\0'\3\4\0B\0\3\0016\0\5\0'\2\6\0B\0\2\0029\0\a\0004\2\0\0B\0\2\1K\0\1\0\nsetup\21indent_blankline\frequire\14space:‚ãÖ\vappend\14listchars\bopt\bvim\0", "config", "indent-blankline.nvim")
time([[Config for indent-blankline.nvim]], false)
-- Config for: hubspot-js-utils.nvim
time([[Config for hubspot-js-utils.nvim]], true)
try_loadstring("\27LJ\2\nB\0\0\3\0\3\0\a6\0\0\0'\2\1\0B\0\2\0029\0\2\0004\2\0\0B\0\2\1K\0\1\0\nsetup\21hubspot-js-utils\frequire\0", "config", "hubspot-js-utils.nvim")
time([[Config for hubspot-js-utils.nvim]], false)
-- Config for: nvim-treesitter
time([[Config for nvim-treesitter]], true)
try_loadstring("\27LJ\2\n \1\0\0\5\0\n\0\r6\0\0\0'\2\1\0B\0\2\0029\1\2\0005\3\3\0005\4\4\0=\4\5\0035\4\6\0=\4\a\0035\4\b\0=\4\t\3B\1\2\1K\0\1\0\26context_commentstring\1\0\1\venable\2\14highlight\1\0\1\venable\2\19ignore_install\1\2\0\0\fhaskell\1\0\1\21ensure_installed\ball\nsetup\28nvim-treesitter.configs\frequire\0", "config", "nvim-treesitter")
time([[Config for nvim-treesitter]], false)

_G._packer.inside_compile = false
if _G._packer.needs_bufread == true then
  vim.cmd("doautocmd BufRead")
end
_G._packer.needs_bufread = false

if should_profile then save_profiles() end

end)

if not no_errors then
  error_msg = error_msg:gsub('"', '\\"')
  vim.api.nvim_command('echohl ErrorMsg | echom "Error in packer_compiled: '..error_msg..'" | echom "Please check your config for correctness" | echohl None')
end
