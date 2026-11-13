-- Modern-feeling UI: rounded floats everywhere, a centred command palette,
-- breadcrumbs in the winbar, and softer diagnostic marks.
return {
  -- rounded borders on every LSP popup + the diagnostic float
  {
    "neovim/nvim-lspconfig",
    opts = function(_, opts)
      opts.diagnostics = vim.tbl_deep_extend("force", opts.diagnostics or {}, {
        float = { border = "rounded", source = true },
        signs = {
          text = {
            [vim.diagnostic.severity.ERROR] = "󰅚 ",
            [vim.diagnostic.severity.WARN] = "󰀪 ",
            [vim.diagnostic.severity.HINT] = "󰌶 ",
            [vim.diagnostic.severity.INFO] = "󰋽 ",
          },
        },
      })

      local orig = vim.lsp.util.open_floating_preview
      vim.lsp.util.open_floating_preview = function(contents, syntax, o, ...)
        o = o or {}
        o.border = o.border or "rounded"
        o.max_width = o.max_width or 82
        return orig(contents, syntax, o, ...)
      end

      return opts
    end,
  },

  -- command line and messages as centred floating palettes
  {
    "folke/noice.nvim",
    opts = {
      presets = {
        bottom_search = false,
        command_palette = true,
        long_message_to_split = true,
        lsp_doc_border = true,
      },
      cmdline = {
        view = "cmdline_popup",
      },
      -- don't pop the signature/docs window up on every `(` or `,`;
      -- press <C-k> in insert mode (or gK in normal) when you want it
      lsp = {
        signature = { auto_open = { enabled = false } },
      },
      views = {
        cmdline_popup = {
          border = { style = "rounded" },
          win_options = { winblend = 0 },
        },
      },
    },
  },

  -- rounded which-key, and give it room
  {
    "folke/which-key.nvim",
    opts = {
      preset = "modern",
      win = { border = "rounded" },
    },
  },

  -- rounded plugin manager and mason
  { "folke/lazy.nvim", opts = { ui = { border = "rounded" } } },
  { "mason-org/mason.nvim", opts = { ui = { border = "rounded" } } },

  -- breadcrumbs: where you are inside the file, along the top of the window
  {
    "SmiteshP/nvim-navic",
    opts = { highlight = true, separator = "  ", depth_limit = 5 },
  },

  -- pickers as centred floats with rounded edges
  {
    "folke/snacks.nvim",
    opts = {
      picker = {
        layout = { preset = "ivy" },
        win = {
          input = { border = "rounded" },
          list = { border = "rounded" },
          preview = { border = "rounded" },
        },
        sources = {
          explorer = {
            -- the explorer's own buffer-local keys shadow the global panel
            -- cluster (<C-t> even opens snacks' second terminal at the
            -- bottom). Disable them here so Ctrl-t/g/b/y behave the same
            -- inside the sidebar as everywhere else.
            win = {
              input = {
                keys = {
                  ["<c-t>"] = false,
                  ["<c-g>"] = false,
                  ["<c-b>"] = false,
                  ["<c-y>"] = false,
                },
              },
              list = {
                keys = {
                  ["<c-t>"] = false,
                  ["<c-g>"] = false,
                  ["<c-b>"] = false,
                  ["<c-y>"] = false,
                },
              },
            },
            layout = {
              preset = "sidebar",
              layout = {
                backdrop = false,
                width = require("config.uisize").get("explorer_width"),
                min_width = require("config.uisize").get("explorer_width"),
                height = 0,
                position = "left",
                border = "none",
                box = "vertical",
                { win = "input", height = 1, border = "rounded",
                  title = "{title} {live} {flags}", title_pos = "center" },
                { win = "list", border = "rounded" },
                { win = "preview", title = "{preview}", height = 0.4, border = "rounded" },
              },
            },
          },
        },
      },
      explorer = { enabled = true },
      indent = {
        enabled = true,
        animate = { enabled = true },
        scope = { enabled = true },
      },
      scroll = { enabled = true },
      input = { enabled = true },
      notifier = {
        enabled = true,
        style = "compact",
        top_down = false,
      },
      styles = {
        notification = { border = "rounded" },
        input = { border = "rounded" },
      },
    },
  },

  -- slimmer statusline separators to match the rounded look
  {
    "nvim-lualine/lualine.nvim",
    opts = function(_, opts)
      opts.options = opts.options or {}
      opts.options.globalstatus = true

      -- half-circle powerline glyphs: the closest a terminal gets to a
      -- rounded corner on the statusline
      opts.options.section_separators = { left = "", right = "" }
      opts.options.component_separators = { left = "", right = "" }

      -- cap the outermost blocks so NORMAL reads as a pill, not a rectangle
      local function cap(section, left, right)
        if type(section) ~= "table" then
          return section
        end
        local first = section[1]
        if type(first) == "string" then
          section[1] = { first, separator = { left = left, right = right } }
        elseif type(first) == "table" then
          first.separator = { left = left, right = right }
        end
        return section
      end

      opts.sections = opts.sections or {}
      opts.sections.lualine_a = cap(opts.sections.lualine_a, "", "")
      opts.sections.lualine_z = cap(opts.sections.lualine_z, "", "")

      return opts
    end,
  },
}
