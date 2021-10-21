local path_sep = vim.loop.os_uname().sysname == "Windows" and "\\" or "/"
local function path_join(...)
    return table.concat(vim.tbl_flatten {...}, path_sep)
end

local get_current_root_dir = function()

    local bufnr = vim.api.nvim_get_current_buf()

    -- Some path manipulation utilities
    local function is_dir(filename)
        local stat = vim.loop.fs_stat(filename)
        return stat and stat.type == 'directory' or false
    end

    -- Asumes filepath is a file.
    local function dirname(filepath)
        local is_changed = false
        local result = filepath:gsub(path_sep .. "([^" .. path_sep .. "]+)$",
                                     function()
            is_changed = true
            return ""
        end)
        return result, is_changed
    end

    -- Ascend the buffer's path until we find the rootdir.
    -- is_root_path is a function which returns bool
    local function buffer_find_root_dir(bufnr, is_root_path)
        local bufname = vim.api.nvim_buf_get_name(bufnr)
        if vim.fn.filereadable(bufname) == 0 then return nil end
        local dir = bufname
        -- Just in case our algo is buggy, don't infinite loop.
        for _ = 1, 100 do
            local did_change
            dir, did_change = dirname(dir)

            if is_root_path(dir, bufname) then return dir, bufname end
            -- If we can't ascend further, then stop looking.
            if not did_change then return nil end
        end
    end

    local root_dir = buffer_find_root_dir(bufnr, function(dir)
        return is_dir(path_join(dir, '.git'))
    end)
    return root_dir
end

require('formatter').setup({
    logging = false,
    filetype = {
        javascript = {
            -- prettier
            function()
                local rootDir = get_current_root_dir()
                local exe_path = path_join(rootDir, 'node_modules', 'prettier',
                                           'bin-prettier.js')
                local config_path = path_join(rootDir, 'prettier.config.js')
                return {
                    exe = exe_path,
                    args = {
                        "--stdin-filepath", vim.api.nvim_buf_get_name(0),
                        '--config', config_path
                    },
                    stdin = true
                }
            end
        },

        javascriptreact = {
            -- prettier
            function()
                return {
                    exe = "prettier",
                    args = {
                        "--stdin-filepath", vim.api.nvim_buf_get_name(0),
                        '--config ~/prettier.config.js'
                    },
                    stdin = true
                }
            end
        },

        typescript = {
            -- prettier
            function()
                return {
                    exe = "prettier",
                    args = {
                        "--stdin-filepath", vim.api.nvim_buf_get_name(0),
                        '--config ~/prettier.config.js'
                    },
                    stdin = true
                }
            end
        },

        typescriptreact = {
            -- prettier
            function()
                return {
                    exe = "prettier",
                    args = {
                        "--stdin-filepath", vim.api.nvim_buf_get_name(0),
                        '--config ~/prettier.config.js'
                    },
                    stdin = true
                }
            end
        },

        mdx = {
            -- prettier
            function()
                return {
                    exe = "prettier",
                    args = {
                        "--stdin-filepath", vim.api.nvim_buf_get_name(0),
                        '--config ~/prettier.config.js'
                    },
                    stdin = true
                }
            end
        },

        lua = {
            -- https://github.com/Koihik/LuaFormatter
            function()
                return {
                    exe = "lua-format",
                    args = {vim.api.nvim_buf_get_name(0)},
                    stdin = true
                }
            end
        }
    }
})

vim.api.nvim_exec([[
au! BufRead,BufNewFile *.mdx setfiletype mdx
augroup FormatAutogroup
  autocmd!
  autocmd BufWritePost *.js,*.ts,*.tsx,*.lua,*.mdx FormatWrite
augroup END
]], true)
