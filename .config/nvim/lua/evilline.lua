local gl = require('galaxyline')
local fn = vim.fn
local colors = require('galaxyline.theme').default
local condition = require('galaxyline.condition')
local gls = gl.section


gl.short_line_list = {'NvimTree','vista','dbui'}

gls.left[1] = {
  RainbowRed = {
    provider = function() return '▊ ' end,
    highlight = {colors.blue}
  },
}
gls.left[2] = {
  ViMode = {
    provider = function()
      -- auto change color according the vim mode
      local mode_color = {
        n = colors.red,
        i = colors.green,
        v=colors.blue,
        [''] = colors.blue,
        V=colors.blue,
        c = colors.magenta,
        no = colors.red,
        s = colors.orange,
        S=colors.orange,
        [''] = colors.orange,
        ic = colors.yellow,
        R = colors.violet,
        Rv = colors.violet,
        cv = colors.red,
        ce=colors.red,
        r = colors.cyan,
        rm = colors.cyan,
        ['r?'] = colors.cyan,
        ['!']  = colors.red,
        t = colors.red,
      }

      local mode_word = {
       n  = 'NORMAL',
       no = 'N·Operator Pending',
       v  = 'V',
       V  = 'V·Line',
       x22 = 'V·Block',
       s  = 'Select',
       S  = 'S·Line',
       x19 = 'S·Block',
       i  = 'I',
       R  = 'R',
       Rv = 'V·Replace',
       c  = 'Command',
       cv = 'Vim Ex',
       ce = 'Ex',
       r  = 'Prompt',
       rm = 'More',
       ['r?'] = 'Confirm',
       ['!']  = 'Shell',
       t  = 'Terminal',
      }

      vim.api.nvim_command('hi GalaxyViMode guifg='..mode_color[vim.fn.mode()])
      return '--' ..mode_word[vim.fn.mode()]..'--'
    end,
    highlight = {colors.red,'bold'},
  },
}
gls.left[3] ={
  FileIcon = {
    provider = 'FileIcon',
    condition = condition.buffer_not_empty,
    highlight = {require('galaxyline.provider_fileinfo').get_file_icon_color},
  },
}

gls.left[4] = {
  FileName = {
    -- provider = {'FileName'},
    provider = function()
      return fn.expand("%:F")
    end,
    condition = condition.buffer_not_empty,
    highlight = {colors.magenta,'bold'}
  }
}

gls.left[5] = {
  LineInfo = {
    provider = 'LineColumn',
    separator = ' ',
    separator_highlight = {'NONE'},
    highlight = {colors.fg},
  },
}

gls.left[6] = {
  PerCent = {
    provider = 'LinePercent',
    separator = ' ',
    separator_highlight = {'NONE'},
    highlight = {colors.fg,'bold'},
  }
}

gls.left[7] = {
  GitBranch = {
    provider = 'GitBranch',
    condition = condition.check_git_workspace,
    highlight = {colors.violet,'bold'},
  }
}

gls.left[8] = {
  DiagnosticError = {
    provider = 'DiagnosticError',
    icon = '  ',
    highlight = {colors.red}
  }
}
gls.left[9] = {
  DiagnosticWarn = {
    provider = 'DiagnosticWarn',
    icon = '  ',
    highlight = {colors.yellow},
  }
}

gls.left[10] = {
  DiagnosticHint = {
    provider = 'DiagnosticHint',
    icon = '  ',
    highlight = {colors.cyan},
  }
}

gls.left[11] = {
  DiagnosticInfo = {
    provider = 'DiagnosticInfo',
    icon = '  ',
    highlight = {colors.blue},
  }
}


gls.right[3] = {
  GitIcon = {
    provider = function() return '  ' end,
    condition = condition.check_git_workspace,
    separator = ' ',
    separator_highlight = {'NONE'},
    highlight = {colors.violet,'bold'},
  }
}


gls.right[5] = {
  DiffAdd = {
    provider = 'DiffAdd',
    condition = condition.hide_in_width,
    icon = '  ',
    highlight = {colors.green},
  }
}
gls.right[6] = {
  DiffModified = {
    provider = 'DiffModified',
    condition = condition.hide_in_width,
    icon = ' 柳',
    highlight = {colors.orange},
  }
}
gls.right[7] = {
  DiffRemove = {
    provider = 'DiffRemove',
    condition = condition.hide_in_width,
    icon = '  ',
    highlight = {colors.red},
  }
}

gls.right[8] = {
  RainbowBlue = {
    provider = function() return ' ▊' end,
    highlight = {colors.blue}
  },
}

gls.short_line_left[1] = {
  BufferType = {
    provider = 'FileTypeName',
    separator = ' ',
    separator_highlight = {'NONE'},
    highlight = {colors.blue,'bold'}
  }
}

gls.short_line_left[2] = {
  SFileName = {
    provider =  'SFileName',
    condition = condition.buffer_not_empty,
    highlight = {colors.fg,'bold'}
  }
}

gls.short_line_right[1] = {
  BufferIcon = {
    provider= 'BufferIcon',
    highlight = {colors.fg}
  }
}
