local api = vim.api
local M = {}
function M.LSPLogs()
  local logFile = vim.lsp.get_log_path()
  api.nvim_command("split|term tail -f " ..logFile)
  --api.nvim_command('enew') -- equivalent to :enew
  --vim.bo[0].buftype=nofile -- set the current buffer's (buffer 0) buftype to nofile
  --vim.bo[0].bufhidden=hide
  --vim.bo[0].swapfile=false
end


function M.GitRoot()
  -- https://github.com/nvim-telescope/telescope-project.nvim/blob/master/lua/telescope/_extensions/project_actions.lua
  local git_root = vim.fn.systemlist("git -C " .. vim.loop.cwd() .. " rev-parse --show-toplevel")[
    1
  ]
  local project_directory = git_root
  if not git_root then
    project_directory = vim.loop.cwd()
  end
  return project_directory
end

function M.telescope_files()
  local root = M.GitRoot()
  require('telescope.builtin').find_files({cwd=root})
end

function M.telescope_grep()
  local root = M.GitRoot()
  require('telescope.builtin').live_grep({cwd=root})
end

return M
