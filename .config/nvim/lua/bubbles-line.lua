

local gl = require("galaxyline")
local gls = gl.section

gl.short_line_list = {" "} -- keeping this table { } as empty will show inactive statuslines

local colors = {
    main = "#ff87ff",
    bg_alt = "#0B0C15",
    lightbg = "#21252B",
    commented = "#5c6370",
	grey = "#3c4048",
	line_bg = "#282c34",
	creamydark = "#282c34",
    purple = "#252930",
    cyan = "#00FFFF",
    nord = "#81A1C1",
	lightblue = "#81a1c1",
    darkblue = "#61afef",
    blue = "#61afef",
	limegreen = "#bbe67e",
    green = "#7ed491",
    fg_green = "#65a380",
	creamygreen = "#a3be8c",
    yellow = "#A3BE8C",
	creamyorange = "#ff8800",
    orange = "#FF8800",
    bg = "#000B0C15",
    fg = "#D8DEE9",
    magenta = "#c678dd",
    red = "#df8890",
	crimsonRed = "#990000",
    greenYel = "#EBCB8B",
    white = "#d8dee9",
	brown = "91684a"
}

local mode_map = {
    n		= {" NORMAL ", colors.red},
    i		= {" INSERT ", colors.green},
    c		= {" COMMAND ", colors.orange},
    v		= {" VISUAL ", colors.lightblue},
    R		= {" REPLACE ", colors.lightblue},
	t		= {"  TERMINAL ", colors.magenta},

	no		= {" NORMAL ", colors.red},
	ic		= {" INSERT ", colors.green},
	cv		= {" COMMAND ", colors.orange},
	ce		= {" COMMAND ", colors.orange},
    V		= {" VISUAL ", colors.lightblue},
    [""]  = {" VISUAL ", colors.brown},
	['r?']  = {" REPLACE ", colors.lightblue},
	Rv		= {" REPLACE ", colors.lightblue},
	r		= {" REPLACE ", colors.lightblue},
	rm		= {" REPLACE ", colors.lightblue},
	s		= {"  S ", colors.greenYelenYel},
	S		= {"  S ", colors.greenYelenYel},
	['']  = {"  S ", colors.greenYelenYel},
	['!']	= {" ! ", colors.crimsonRed},
}

----------------------------=== Funcs ===--------------------------

local function mode_label() return mode_map[vim.fn.mode()][1] or 'N/A' end
local function mode_hl() return mode_map[vim.fn.mode()][2] or colors.main end

local function highlight1(group, fg, gui)
    local cmd = string.format('highlight %s guifg=%s', group, fg)
    if gui ~= nil then cmd = cmd .. ' gui=' .. gui end
    vim.cmd(cmd)
end

local function highlight2(group, bg, fg, gui)
    local cmd = string.format('highlight %s guibg=%s guifg=%s', group, bg, fg)
    if gui ~= nil then cmd = cmd .. ' gui=' .. gui end
    vim.cmd(cmd)
end


----------------------------=== Components ===--------------------------

----------------------------=== Left ===--------------------------


gls.left[1] = {
    leftRounded = {
        provider = function()
            return ""
        end,
        highlight = 'GalaxyViModeInv'
    }
}

gls.left[2] = {
    ViMode = {
        provider = function()
            highlight2('GalaxyViMode', mode_hl(), colors.bg_alt, 'bold')
            highlight1('GalaxyViModeInv', mode_hl(), 'bold')
            return string.format(' %s', mode_label())
        end,
    }
}

gls.left[3] = {
    WhiteSpace = {
        provider = function()
            highlight2('SecondGalaxyViMode', mode_hl(), colors.white, 'bold')
        end,
        separator = "",
        separator_highlight = 'SecondGalaxyViMode'
    }
}


gls.left[4] = {
	FileIcon = {
       provider = "FileIcon",
       separator = "",
       separator_highlight = {colors.white, colors.white},
       highlight = {colors.creamydark, colors.white}
   }

}

gls.left[5] = {
    FileName = {
        provider = {"FileName", "FileSize"},
        condition = buffer_not_empty,
        highlight = {colors.creamydark, colors.white}
    }
}

gls.left[6] = {
    teech = {
        provider = function()
            return ""
        end,
        separator = "",
        highlight = {colors.white, colors.bg}
    }
}

local checkwidth = function()
    local squeeze_width = vim.fn.winwidth(0) / 2
    if squeeze_width > 40 then
        return true
    end
    return false
end

gls.left[7] = {
    DiffAdd = {
        provider = "DiffAdd",
        condition = checkwidth,
        icon = "   ",
        highlight = {colors.greenYel, colors.bg}
    }
}

gls.left[8] = {
    DiffModified = {
        provider = "DiffModified",
        condition = checkwidth,
        icon = "  柳",
        highlight = {colors.creamyorange, colors.bg}
    }
}

gls.left[9] = {
    DiffRemove = {
        provider = "DiffRemove",
        condition = checkwidth,
        icon = "   ",
        highlight = {colors.red, colors.bg}
    }
}

gls.left[10] = {
    LeftEnd = {
        provider = function()
            return " "
        end,
        separator = " ",
        separator_highlight = {colors.bg, colors.bg},
        highlight = {colors.bg, colors.bg}
    }
}

gls.left[11] = {
    DiagnosticError = {
        provider = "DiagnosticError",
        icon = "   ",
        highlight = {colors.red, colors.bg}
    }
}

gls.left[12] = {
    Space = {
        provider = function()
            return " "
        end,
        highlight = {colors.bg, colors.bg}
    }
}

gls.left[13] = {
    DiagnosticWarn = {
        provider = "DiagnosticWarn",
        icon = "   ",
        highlight = {colors.green, colors.bg}
    }
}

gls.left[14] = {
    Space = {
        provider = function()
            return " "
        end,
        highlight = {colors.bg, colors.bg}
    }
}


gls.left[15] = {
    DiagnosticInfo = {
        provider = "DiagnosticInfo",
        icon = "   ",
        highlight = {colors.blue, colors.bg}
    }
}

gls.left[16] = {
    Space = {
        provider = function()
            return " "
        end,
        highlight = {colors.bg, colors.bg}
    }
}


gls.left[17] = {
    DiagnosticHint = {
        provider = "DiagnosticHint",
        icon = "   ",
        highlight = {colors.blue, colors.bg}
    }
}


----------------------------=== Middle ===--------------------------
-- gls.mid[1] = {
-- 	ShowLspClient = {
-- 		provider = 'GetLspClient',
-- 		condition = function ()
-- 			local tbl = {['dashboard'] = true,['']=true}

-- 			if tbl[vim.bo.filetype] then
-- 				return false
-- 			end
-- 			return true
-- 		end,
-- 		icon = ' LSP:',
-- 		highlight = {colors.white,colors.bg,'bold'}
-- 	}
-- }

----------------------------=== Right ===--------------------------

gls.right[1] = {
    GitIcon = {
        provider = function()
            return "   "
        end,
        condition = require("galaxyline.provider_vcs").check_git_workspace,
        highlight = {colors.limegreen, colors.bg}
    }
}

gls.right[2] = {
    GitBranch = {
        provider = "GitBranch",
        condition = require("galaxyline.provider_vcs").check_git_workspace,
        highlight = {colors.darkblue, colors.bg},
    }
}

gls.right[3] = {
    right_LeftRounded = {
		separator = " ", -- separate from git branch
        provider = function()
            return ""
        end,
        highlight = {colors.grey, colors.bg}
    }
}

gls.right[4] = {
    LineInfo = {
        provider = "LineColumn",
        separator = "l/n ",
        separator_highlight = {colors.white, colors.grey},
        highlight = {colors.white, colors.grey}
    }
}

gls.right[5] = {
    PerCent = {
        provider = "LinePercent",
        separator = " ",
        separator_highlight = {colors.white, colors.grey},
        highlight = {colors.white, colors.grey}
    }
}

gls.right[6] = {
    rightRounded = {
        provider = function()
            return ""
        end,
        highlight = {colors.grey, colors.bg}
    }
}
