-- Look only: the statusline palette and separators from the previous config.
-- LazyVim keeps ownership of which components appear and what they do.
return {
  "nvim-lualine/lualine.nvim",
  opts = function(_, opts)
    local colors = {
      color0 = "#092236",
      color1 = "#ff5874",
      color2 = "#c3ccdc",
      color3 = "#1c1e26",
      color4 = "#11111B",
      color6 = "#a1aab8",
      color7 = "#828697",
      color8 = "#ae81ff",
    }

    local theme = {
      normal = {
        a = { fg = colors.color0, bg = colors.color7, gui = "bold" },
        b = { fg = colors.color2, bg = colors.color4 },
        c = { fg = colors.color2, bg = colors.color4 },
      },
      insert = {
        a = { fg = colors.color0, bg = colors.color2, gui = "bold" },
        b = { fg = colors.color2, bg = colors.color4 },
      },
      visual = {
        a = { fg = colors.color0, bg = colors.color8, gui = "bold" },
        b = { fg = colors.color2, bg = colors.color4 },
      },
      replace = {
        a = { fg = colors.color0, bg = colors.color1, gui = "bold" },
        b = { fg = colors.color2, bg = colors.color4 },
      },
      inactive = {
        a = { fg = colors.color6, bg = colors.color3, gui = "bold" },
        b = { fg = colors.color6, bg = colors.color4 },
        c = { fg = colors.color6, bg = colors.color4 },
      },
    }

    opts.options = opts.options or {}
    opts.options.theme = theme
    opts.options.component_separators = { left = "|", right = "|" }
    opts.options.section_separators = { left = "|", right = "" }
    opts.options.icons_enabled = true

    return opts
  end,
}
