local api = vim.api
local a = require("plenary.async")
local luv = vim.loop
local filetypes = require('filetypes').defaultConfig
local buffer_find_root_dir = require('tools').buffer_find_root_dir
local is_dir = require('tools').is_dir
local file_exists = require('tools').file_exists
local path_join = require('tools').path_join
local open_file = require('tools').open_file
local Job = require 'plenary.job'
local log = require('plenary.log').new({
    plugin = 'hubspot-js-utils',
    use_console = true
})

local M = {}

local function get_full_file_path_of_current_buffer() return
    vim.fn.expand('%:p') end

local function get_file_extension_from_path(path)
    local lastdotpos = (path:reverse()):find("%.")
    return (path:sub(1 - lastdotpos))
end

local function verify_filetype_is_valid()
    local bufnr = vim.api.nvim_get_current_buf()
    local buf_filetype = vim.api.nvim_buf_get_option(bufnr, "filetype")

    -- Filter which files we are considering.
    if not filetypes[buf_filetype] then
        log.error('current filetype is not relevant "', buf_filetype, '"')
        return false
    end
    return true
end

local function verify_static_test_dir_exists()
    local bufnr = vim.api.nvim_get_current_buf()
    local static_root_dir = buffer_find_root_dir(bufnr, function(dir)
        return is_dir(path_join(dir, "js")) and is_dir(path_join(dir, "test"))
    end)

    -- We couldn't find a root directory, so ignore this file.
    if not static_root_dir then
        log.error("No test directory found, ending")
        return false
    end
    return true
end

local function get_dirname_of_filepath(filepath)
    local result = ""
    Job:new({
        command = "dirname",
        args = {filepath},
        on_exit = function(j, return_val)
            local path = j:result()[1]
            result = path .. result
        end
    }):sync()
    return result
end

local function mkdirp(path)
    local result = nil
    Job:new({
        command = "mkdir",
        args = {"-p", filepath},
        on_exit = function(j, return_val) result = j:result() end
    }):sync()
    return result
end

local function touchFile(filepath)
    local result = nil
    Job:new({
        command = "touch",
        args = {filepath},
        on_exit = function(j, return_val) result = j:result() end
    }):sync()
    return result
end

local function writeLineToFile(filepath, line)
    local f = assert(io.open(filepath, "a"))
    f:write(line, "\n")
    f:close()
end

local function get_substring_before_and_after_match(mainstring, substring)
    local indexBeforeSubstring, indexAfterSubstring =
        string.find(mainstring, substring)

    local before = mainstring:sub(0, indexBeforeSubstring - 1) -- sub means substring
    local after = mainstring:sub(indexAfterSubstring + 1) -- sub means substring

    return {before = before, after = after}
end

local function generate_testfilepath_from_currentfilepath(currentfilepath)
    local filepathBeforeAfterStaticJs = get_substring_before_and_after_match(
                                            currentfilepath, "/static/js/")

    local currentfilepathextension = get_file_extension_from_path(
                                         currentfilepath)

    local relativePath = string.gsub(filepathBeforeAfterStaticJs.after,
                                     "." .. currentfilepathextension,
                                     "-test." .. currentfilepathextension)

    local result = path_join(filepathBeforeAfterStaticJs.before, "static",
                             "test", "spec", relativePath)

    return result
end

local function touch_file_recursive(filepath)
    local dirname = get_dirname_of_filepath(filepath)
    mkdirp(dirname)
    touchFile(filepath)
    writeLineToFile(filepath, "//Auto generated from nvim-hubspot-js-utils")
    writeLineToFile(filepath, "")
    writeLineToFile(filepath, "describe(\"" ..
                        get_substring_before_and_after_match(filepath,
                                                             "/static/test/spec/").after ..
                        "\", () => {")
    writeLineToFile(filepath, "//")
    writeLineToFile(filepath, "})")

end

function M.test_file()

    if verify_filetype_is_valid() == false then return end
    if verify_static_test_dir_exists() == false then return end

    local buff_file_path = get_full_file_path_of_current_buffer()
    local suggested_location = generate_testfilepath_from_currentfilepath(
                                   buff_file_path)

    if file_exists(suggested_location) then
        open_file(suggested_location)
        return
    end

    local new_file_location = vim.fn.input({
        prompt = "New test file: ",
        default = suggested_location,
        cancelreturn = nil
    })

    if new_file_location ~= "" then
        touch_file_recursive(new_file_location)
        open_file(new_file_location)
    else
        log.error("New test file location is invalid - not creating '",
                  new_file_location, '"')
    end
end

return M
