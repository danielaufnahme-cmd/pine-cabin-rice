-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
--
-- Add any additional autocmds here
-- with `vim.api.nvim_create_autocmd`
--
-- Or remove existing autocmds by their group name (which is prefixed with `lazyvim_` for the defaults)
-- e.g. vim.api.nvim_del_augroup_by_name("lazyvim_wrap_spell")

-- Python: auto-insert `self` when defining a method inside a class.
--
--   class Token:
--       def __init__(        ->  def __init__(self)
--                                              ^ cursor lands here
--
-- Triggers on typing `(` when the text before the cursor is `def <name>`
-- (or `async def <name>`) and the nearest less-indented line above starts
-- with `class`. A `@staticmethod` decorator on the line above skips it,
-- `@classmethod` inserts `cls` instead. Nested functions inside a method
-- are left alone. Works through InsertCharPre, so mini.pairs still adds
-- the closing `)` and the completion.lua space-swallow logic still runs.
vim.api.nvim_create_autocmd("InsertCharPre", {
  group = vim.api.nvim_create_augroup("python_auto_self", { clear = true }),
  pattern = "*.py",
  callback = function()
    if vim.v.char ~= "(" then
      return
    end

    local row, col = unpack(vim.api.nvim_win_get_cursor(0))
    local line = vim.api.nvim_get_current_line()
    local before = line:sub(1, col)
    local after = line:sub(col + 1)

    -- must be exactly `<indent>def name` / `<indent>async def name`, nothing after the cursor
    if not (before:match("^%s+def%s+[%w_]+%s*$") or before:match("^%s+async%s+def%s+[%w_]+%s*$")) then
      return
    end
    if after:match("%S") then
      return
    end

    local indent = #before:match("^%s*")
    local lines = vim.api.nvim_buf_get_lines(0, 0, row - 1, false)

    -- decorator directly above?
    for i = #lines, 1, -1 do
      local l = lines[i]
      if l:match("%S") then
        if l:match("^%s*@staticmethod") then
          return
        end
        if l:match("^%s*@classmethod") then
          vim.v.char = "(cls"
          return
        end
        break
      end
    end

    -- nearest non-blank line above with a smaller indent: is it a class?
    for i = #lines, 1, -1 do
      local l = lines[i]
      if l:match("%S") then
        local ind = #l:match("^%s*")
        if ind < indent then
          if l:match("^%s*class%s") then
            vim.v.char = "(self"
          end
          return
        end
      end
    end
  end,
})
