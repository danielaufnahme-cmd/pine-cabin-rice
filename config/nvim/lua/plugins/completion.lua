-- Completion tweaks for blink.cmp (LazyVim default completer).

-- Position of the space we last inserted after a completion (or nil).
local auto_space = nil

-- Accept the selected item, then add a trailing space if we landed at the
-- end of the line right after a word character.
local function accept_with_space(cmp)
  return cmp.accept({
    callback = function()
      local line = vim.api.nvim_get_current_line()
      local col = vim.api.nvim_win_get_cursor(0)[2]
      local prev = line:sub(col, col)
      if col == #line and prev:match("[%w_]") then
        vim.api.nvim_put({ " " }, "c", true, true)
        -- remember where the auto-space is so `.` can undo it
        auto_space = { buf = vim.api.nvim_get_current_buf(), row = vim.api.nvim_win_get_cursor(0)[1], col = col + 1 }
      end
    end,
  })
end

-- If the very next thing typed after an auto-space is one of these keys,
-- swallow the space first: `System |` + `.` -> `System.`
-- The mappings wrap whatever was mapped before (mini.pairs auto-closing,
-- LazyVim's undo breakpoints), so those keep working. Set up after
-- VeryLazy so we run last.
local swallow_keys = { ".", ":", "(", ";", ")", ",", "[", "]" }

local function should_swallow()
  local a = auto_space
  auto_space = nil
  if not a or a.buf ~= vim.api.nvim_get_current_buf() then
    return false
  end
  local pos = vim.api.nvim_win_get_cursor(0)
  local line = vim.api.nvim_get_current_line()
  return pos[1] == a.row and pos[2] == a.col and line:sub(a.col, a.col) == " "
end

local function t(keys)
  return vim.api.nvim_replace_termcodes(keys, true, false, true)
end

vim.api.nvim_create_autocmd("User", {
  pattern = "VeryLazy",
  once = true,
  callback = function()
    vim.schedule(function()
      for _, key in ipairs(swallow_keys) do
        local orig = vim.fn.maparg(key, "i", false, true)
        local function original()
          if orig.expr == 1 then
            -- expression mapping: Lua callback or a Vimscript expression
            local r = orig.callback and orig.callback() or vim.api.nvim_eval(orig.rhs)
            if type(r) ~= "string" then
              return ""
            end
            return orig.replace_keycodes == 1 and t(r) or r
          end
          if orig.rhs and orig.rhs ~= "" then
            return t(orig.rhs)
          end
          return key
        end
        vim.keymap.set("i", key, function()
          local prefix = should_swallow() and t("<BS>") or ""
          return prefix .. original()
        end, {
          expr = true,
          replace_keycodes = false,
          desc = "Type " .. key .. " (drops an auto-inserted completion space)",
        })
      end
    end)
  end,
})

return {
  {
    "saghen/blink.cmp",
    opts = {
      keymap = {
        -- accept with <CR> / <C-y> and put a space after the inserted text
        -- (only when the cursor ends up at the end of the line, so things
        -- like `foo(|)` or `x|;` are left alone)
        ["<CR>"] = { accept_with_space, "fallback" },
        ["<C-y>"] = { accept_with_space, "fallback" },
      },

      completion = {
        -- don't auto-open the docs/example window next to the menu;
        -- press <C-space> while the menu is open if you do want it
        documentation = { auto_show = false },
        -- no inline grey preview text after the cursor
        ghost_text = { enabled = false },
      },

      fuzzy = {
        -- items whose start matches what you typed exactly come first
        -- ("S" -> String/System before sIze), then by fuzzy score.
        -- frecency (on by default) also bumps things you pick often.
        sorts = { "exact", "score", "sort_text" },
      },

      sources = {
        -- no completion menu inside strings or comments
        default = function()
          local ok, node = pcall(vim.treesitter.get_node)
          if ok and node then
            local t = node:type()
            if
              t:find("string")
              or t:find("comment")
              or t == "text_block"
              or t == "character_literal"
            then
              return {}
            end
          end
          return { "lsp", "path", "snippets", "buffer" }
        end,
        providers = {
          -- real symbols from the language server win over snippet templates
          snippets = { score_offset = -3, min_keyword_length = 2 },
          -- words scraped from the buffer only as a last resort
          buffer = { score_offset = -5, min_keyword_length = 3 },
        },
      },
    },
  },
}
