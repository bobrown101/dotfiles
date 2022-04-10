local M = {}

function M.LSPLogs()
    local logFile = vim.lsp.get_log_path()
    vim.api.nvim_command("split|term tail -f " .. logFile)
end

function M.GitRoot()
    local git_root = vim.fn.systemlist("git -C " .. vim.loop.cwd() ..
                                           " rev-parse --show-toplevel")[1]
    local project_directory = git_root
    if not git_root then project_directory = vim.loop.cwd() end
    return project_directory
end

function M.telescope_files()
    local root = M.GitRoot()
    require("telescope.builtin").find_files({cwd = root})
end

function M.telescope_grep()
    local root = M.GitRoot()
    require("telescope.builtin").live_grep({cwd = root})
end

return M
