local api = vim.api
local a = require("plenary.async")
local luv = vim.loop
local filetypes = require('filetypes').defaultConfig
local buffer_find_root_dir = require('tools').buffer_find_root_dir
local Job = require'plenary.job'
local log = require('plenary.log').new({
  plugin = 'hubspot-js-utils',
  use_console = false,
})


local open_mode = luv.constants.O_CREAT + luv.constants.O_WRONLY + luv.constants.O_TRUNC
local path_sep = vim.loop.os_uname().sysname == "Windows" and "\\" or "/"
local M = {}


local function get_file_location(filepath)
    return string.match(filepath, "^(.+)/.+$")
end

local function get_file_name(filepath)
    return string.match(filepath, "^.+/(.+)$")
end

local function clear_prompt()
    vim.api.nvim_command("normal :esc<CR>")
end

local function get_user_input_char()
    local c = vim.fn.getchar()
    while type(c) ~= "number" do
        c = vim.fn.getchar()
    end
    return vim.fn.nr2char(c)
end

local function create_file(file)
    -- we want to strip this out to the filename and folder location
    local file_location = get_file_location(file)
    local file_name = get_file_name(file)

    if luv.fs_access(file, "r") ~= false then
        log.info(file .. " already exists. Overwrite? y/n")
        local ans = get_user_input_char()
        clear_prompt()
        if ans ~= "y" then
            return
        end
    end
    luv.fs_mkdir(file_location, 493)
    luv.fs_open(
        file,
        "w",
        open_mode,
        vim.schedule_wrap(function(err, fd)
            if err then
                api.nvim_err_writeln("Couldn't create file " .. file)
            else
                -- FIXME: i don't know why but libuv keeps creating file with executable permissions
                -- this is why we need to chmod to default file permissions
                luv.fs_chmod(file, 420)
                luv.fs_close(fd)
            end
        end)
    )
end

function M.test_file()
    local bufnr = vim.api.nvim_get_current_buf()
    local buf_filetype = vim.api.nvim_buf_get_option(bufnr, "filetype")

    -- Filter which files we are considering.
    if not filetypes[buf_filetype] then
        log.info('current filetype is not relevant', buf_filetype)
        return
    end

    local function file_exists(fname)
        local stat = vim.loop.fs_stat(fname)
        return (stat and stat.type) or false
    end

    local function is_dir(filename)
        local stat = vim.loop.fs_stat(filename)
        return stat and stat.type == "directory" or false
    end

    local function path_join(...)
        return table.concat(vim.tbl_flatten({ ... }), path_sep)
    end

    local function open_file(file)
      vim.cmd("e "..file)
    end


    local static_root_dir = buffer_find_root_dir(bufnr, function(dir)
        log.info(dir)
        log.info("is js a dir", path_join(dir, "js"), is_dir(path_join(dir, "js")))
        log.info("is test a dir", path_join(dir, "js"), is_dir(path_join(dir, "test")))

        return is_dir(path_join(dir, "js")) and is_dir(path_join(dir, "test"))
    end)

    -- We couldn't find a root directory, so ignore this file.
    if not static_root_dir then
        api.nvim_err_writeln("No test directory found, ending")
        log.info("we couldnt find a test directory, ending")
        return
    end

    log.info("found static root dir of", static_root_dir)
    local buff_file_path = vim.api.nvim_buf_get_name(bufnr)
    log.info("from current file path of ", buff_file_path)

    -- strip off everything before /static/js/ (including that substring)
    -- and replace the ending of .js with -test.js
    -- and then we have our new file location
    local _, stripUntil = string.find(buff_file_path, "/static/js/")
    local path_within_static_dir = buff_file_path:sub(stripUntil + 1)

    local test_file_path = string.gsub(path_within_static_dir, ".js", "-test.js")

    local suggested_location = path_join(static_root_dir, "test", "spec", test_file_path)

    if file_exists(suggested_location) then
      api.nvim_err_writeln('Test file found, opening')
      open_file(suggested_location)
      return
    end

    log.info("test file path will be", suggested_location)

    local new_file_location = vim.fn.input({
        prompt = "New test file: ",
        default = suggested_location,
        cancelreturn = nil,
    })

    if new_file_location ~= "" then
        log.info("below will be split file location")
        open_file(new_file_location)
    else
        api.nvim_err_writeln("New test file location is invalid - not creating")
    end
end

return M
