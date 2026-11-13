-- One key per panel, on three keys that touch on the keyboard:
--
--         Ctrl-t   Ctrl-y          T Y sit side by side,
--            Ctrl-g                G sits directly beneath them
--
--   Ctrl-y   files, on the left
--   Ctrl-g   output panel, along the bottom   (G is the low key = the low panel)
--   Ctrl-t   terminal, on the right
--
-- Each key is a *smart* toggle:
--   closed          -> open it and jump in
--   open, elsewhere -> jump into it, leaving it open
--   open, you're in it -> hide it
--
-- So pressing it twice from your code opens then closes; pressing it once
-- while you are inside sends you back out.

local M = {}

local runner = require("config.runner")
local sideterm = require("config.sideterm")

-- helpers --------------------------------------------------------------------

local function here()
  return vim.api.nvim_get_current_win()
end

local function valid(win)
  return win and vim.api.nvim_win_is_valid(win)
end

local function enter(win)
  if valid(win) then
    vim.api.nvim_set_current_win(win)
  end
end

---Smart toggle: open / focus / hide depending on where you are.
---@param find fun():integer|nil   the panel's window, or nil if hidden
---@param open fun()               open it and focus it
---@param hide fun()               hide it
---@param insert? boolean          drop into insert mode when focusing (terminals)
local function smart(find, open, hide, insert)
  return function()
    local win = find()
    if not valid(win) then
      open()
      return
    end
    if here() == win then
      -- you are standing in it: put it away
      if vim.fn.mode() == "t" then
        vim.cmd("stopinsert")
      end
      hide()
    else
      enter(win)
      if insert then
        vim.cmd("startinsert")
      end
    end
  end
end

-- explorer (left) ------------------------------------------------------------

local EXPLORER_FT = {
  snacks_layout_box = true,
  snacks_picker_list = true,
  snacks_picker_input = true,
  snacks_picker_preview = true,
}

local function explorer_picker()
  local ok, found = pcall(function()
    return Snacks.picker.get({ source = "explorer" })[1]
  end)
  return ok and found or nil
end

-- prefer the file list itself, so focusing lands somewhere useful
local function explorer_list_win()
  local fallback
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    local ft = vim.bo[vim.api.nvim_win_get_buf(w)].filetype
    if ft == "snacks_picker_list" then
      return w
    elseif EXPLORER_FT[ft] then
      fallback = fallback or w
    end
  end
  return fallback
end

-- you may be standing in the input, the list or the preview; all count as "in it"
local function in_explorer()
  return EXPLORER_FT[vim.bo[vim.api.nvim_win_get_buf(here())].filetype] == true
end

function M.explorer()
  local picker = explorer_picker()

  if not picker then
    Snacks.explorer.open()
    return
  end

  if in_explorer() then
    pcall(function()
      picker:close()
    end)
  else
    enter(explorer_list_win())
  end
end

-- output panel (bottom) ------------------------------------------------------

-- shows the last run's output; never starts a shell of its own
local panel_smart = smart(runner.win, function()
  runner.show()
  runner.focus()
end, runner.hide, false)

M.panel = function()
  local ok, err = pcall(panel_smart)
  if not ok then
    vim.notify("Ctrl-g failed: " .. tostring(err), vim.log.levels.ERROR)
  end
end

-- side terminal (right) ------------------------------------------------------

M.terminal = smart(sideterm.win, function()
  sideterm.open()
end, sideterm.hide, true)

-- the code itself (centre) ---------------------------------------------------

-- remember the last window you were actually editing in
local last_code_win

local function is_code_win(w)
  if not valid(w) then
    return false
  end
  local b = vim.api.nvim_win_get_buf(w)
  if vim.api.nvim_win_get_config(w).relative ~= "" then
    return false
  end
  if vim.b[b].side_term or vim.b[b].run_panel then
    return false
  end
  local ft, bt = vim.bo[b].filetype, vim.bo[b].buftype
  if EXPLORER_FT[ft] or bt == "terminal" then
    return false
  end
  return bt == "" or ft == "snacks_dashboard"
end

vim.api.nvim_create_autocmd("WinLeave", {
  desc = "Remember the editing window",
  callback = function()
    local w = here()
    if is_code_win(w) then
      last_code_win = w
    end
  end,
})

function M.code()
  if is_code_win(last_code_win) and last_code_win ~= here() then
    enter(last_code_win)
    return
  end
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    if is_code_win(w) and w ~= here() then
      enter(w)
      return
    end
  end
  vim.notify("No editor window open", vim.log.levels.INFO)
end

-- keymaps --------------------------------------------------------------------

local function map(key, fn, desc)
  vim.keymap.set({ "n", "t" }, key, function()
    -- leave terminal-insert first so window switching behaves
    if vim.fn.mode() == "t" then
      vim.cmd("stopinsert")
      vim.schedule(fn)
    else
      fn()
    end
  end, { desc = desc })
end

-- Some plugins (noice) claim <C-b>/<C-f> when they load, which happens after
-- this file. Apply our maps now and again on a short delay so ours win.
local function apply_maps()
  map("<C-y>", M.explorer, "Files panel (left)")
  map("<C-g>", M.panel, "Output panel (bottom)")
  map("<C-t>", M.terminal, "Terminal (right)")
  map("<C-b>", M.code, "Back to the code")
end

apply_maps()

-- LazyVim ships its own terminal on <C-/>, <C-_>, <leader>ft and <leader>fT,
-- which opens a *second* one as a bottom split. Point them all at ours so
-- there is only ever one terminal.
-- this file already loads on VeryLazy, so LazyVim's own maps exist by now;
-- the defer just makes sure we win against anything set in the same tick
vim.defer_fn(function()
  apply_maps()
  for _, k in ipairs({ "<C-/>", "<C-_>" }) do
    pcall(vim.keymap.set, { "n", "t" }, k, M.terminal, { desc = "Terminal (right)" })
  end
  for _, k in ipairs({ "<leader>ft", "<leader>fT" }) do
    pcall(vim.keymap.set, "n", k, M.terminal, { desc = "Terminal (right)" })
  end
end, 100)

-- move out of a terminal with the same keys you use everywhere else
for key, dir in pairs({ ["<C-h>"] = "h", ["<C-j>"] = "j", ["<C-k>"] = "k", ["<C-l>"] = "l" }) do
  vim.keymap.set("t", key, function()
    vim.cmd("stopinsert")
    vim.schedule(function()
      vim.cmd("wincmd " .. dir)
    end)
  end, { desc = "Go to " .. dir .. " window" })
end

return M
