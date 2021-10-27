local Job = require "plenary.job"
local is_dir = require('tools').is_dir;
local buffer_find_root_dir = require('tools').buffer_find_root_dir;
local path_join = require('tools').path_join;

local source = {}

source.new = function()
    local self = setmetatable({cache = {}}, {__index = source})

    return self
end

print('hello world')

function split_string(s, delimiter)
    result = {};
    for match in (s .. delimiter):gmatch("(.-)" .. delimiter) do
        table.insert(result, match);
    end
    return result;
end
source.complete = function(self, _, callback)
    local bufnr = vim.api.nvim_get_current_buf()

    -- This just makes sure that we only hit the GH API once per session.
    --
    -- You could remove this if you wanted, but this just makes it so we're
    -- good programming citizens.
    if not self.cache[bufnr] then
        -- Try to find our root directory. We will define this as a directory which contains
        -- .git
        local root_dir = buffer_find_root_dir(bufnr, function(dir)
            return is_dir(path_join(dir, '.git'))
        end)

        -- We couldn't find a root directory, so ignore this file.
        if not root_dir then callback {items = {}, isIncomplete = false} end
        Job:new({
            command = 'rg',
            args = {'--files', root_dir},
            on_exit = function(job)
                local all_files = job:result()
                Job:new({
                    command = 'rg',
                    args = {'en.lyaml'},
                    writer = all_files,
                    on_exit = function(job)
                        local lyaml_files_for_current_project = job:result()
                        print(vim.inspect(lyaml_files_for_current_project))
                        local args = {}
                        table.insert(args, "ea")
                        table.insert(args, '. as $item ireduce ({}; . * $item )')
                        for k, v in ipairs(lyaml_files_for_current_project) do
                            table.insert(args, v)
                        end
                        table.insert(args, "-o")
                        table.insert(args, "p")

                        Job:new({
                            command = "yq",
                            args = args,
                            on_exit = function(job)
                                local unparsed_results = job:result()
                                local items = {}
                                for k, v in ipairs(unparsed_results) do
                                    local translationKeyValuePair =
                                        split_string(v, " = ")
                                    table.insert(items, {
                                        label = translationKeyValuePair[1],
                                        documentation = {
                                            kind = "markdown",
                                            value = translationKeyValuePair[2]
                                        }
                                    })
                                end

                                print(vim.inspect(items))
                                callback {items = items, isIncomplete = false}
                                self.cache[bufnr] = items
                            end
                        }):start()
                    end
                }):start()
            end
        }):start()
    else
        callback {items = self.cache[bufnr], isIncomplete = false}
    end
end

source.get_trigger_characters = function() return {'"'} end

source.is_available = function() return true end
-- source.is_available = function() return vim.bo.filetype == "gitcommit" end

require("cmp").register_source("lyaml_completion", source.new())
