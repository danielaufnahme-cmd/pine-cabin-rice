-- A persistent terminal pinned to the right-hand side.
--
--   Ctrl-t   toggle it open / closed (works from the editor and from inside it)
--
-- Hiding it only closes the window: the shell keeps running, so whatever you
-- were doing is still there when you bring it back. The width you drag it to
-- is remembered across restarts (see lua/config/uisize.lua).

local M = {}

local uisize = require("config.uisize")

local term = { win = nil, buf = nil, job = nil }

local function win_open()
  return term.win and vim.api.nvim_win_is_valid(term.win)
end

local function buf_alive()
  return term.buf and vim.api.nvim_buf_is_valid(term.buf)
end

-- open ----------------------------------------------------------------------

local function place_window()
  local origin = vim.api.nvim_get_current_win()

  -- far right, full height
  vim.cmd("botright vsplit")
  term.win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_width(term.win, uisize.get("sideterm_width"))

  -- keeps its width when other splits open or close
  vim.wo[term.win].winfixwidth = true
  vim.wo[term.win].number = false
  vim.wo[term.win].relativenumber = false
  vim.wo[term.win].signcolumn = "no"
  vim.wo[term.win].foldcolumn = "0"
  vim.wo[term.win].winbar = nil

  return origin
end

-- Find a terminal we can reuse, even if our own state was lost or the terminal
-- was opened by something else entirely. Anything that is not the run panel
-- counts, so we can never end up with two.
local function adopt()
  if buf_alive() then
    return
  end
  local tagged, stray
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(b) and vim.bo[b].buftype == "terminal" and not vim.b[b].run_panel then
      if vim.b[b].side_term then
        tagged = tagged or b
      else
        stray = stray or b
      end
    end
  end
  term.buf = tagged or stray
  if term.buf then
    vim.b[term.buf].side_term = true
  end
end

-- a window already showing our terminal buffer, if any
local function existing_win()
  if not buf_alive() then
    return nil
  end
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(w) == term.buf then
      return w
    end
  end
end

function M.open(opts)
  opts = opts or {}

  adopt()

  -- If it is already on screen, keep that window only when it really is the
  -- full-height column on the right. Anything else (a bottom split someone
  -- else opened, a leftover) gets closed and re-placed, so Ctrl-t always
  -- means "the terminal on the right" and never adds a second one.
  local shown = existing_win()
  if shown then
    local pos = vim.api.nvim_win_get_position(shown)
    local right_edge = pos[2] + vim.api.nvim_win_get_width(shown) >= vim.o.columns - 1
    local full_height = vim.api.nvim_win_get_height(shown) >= vim.o.lines - 4
    local floating = vim.api.nvim_win_get_config(shown).relative ~= ""

    if right_edge and full_height and not floating then
      term.win = shown
    else
      pcall(vim.api.nvim_win_close, shown, false)
      term.win = nil
    end
  end

  if win_open() then
    if opts.focus ~= false then
      vim.api.nvim_set_current_win(term.win)
      vim.cmd("startinsert")
    end
    return
  end

  local origin = place_window()

  if buf_alive() then
    -- reuse the existing shell, still running
    vim.api.nvim_win_set_buf(term.win, term.buf)
  else
    term.buf = vim.api.nvim_create_buf(false, true)
    -- tag it first: TermOpen fires during jobstart, and anything looking for
    -- an existing terminal then must be able to see this one
    vim.b[term.buf].side_term = true
    vim.api.nvim_win_set_buf(term.win, term.buf)

    term.job = vim.api.nvim_buf_call(term.buf, function()
      return vim.fn.jobstart(vim.o.shell, {
        term = true,
        cwd = vim.uv.cwd(),
        on_exit = function()
          term.job = nil
          -- shell exited: drop the buffer so the next toggle starts fresh
          vim.schedule(function()
            if buf_alive() then
              pcall(vim.api.nvim_buf_delete, term.buf, { force = true })
            end
            term.buf = nil
            if win_open() then
              pcall(vim.api.nvim_win_close, term.win, true)
            end
            term.win = nil
          end)
        end,
      })
    end)

    vim.bo[term.buf].buflisted = false
  end

  -- tag it so the size tracker can recognise this window
  vim.b[term.buf].side_term = true

  if opts.focus == false then
    vim.api.nvim_set_current_win(origin)
  else
    vim.api.nvim_set_current_win(term.win)
    vim.cmd("startinsert")
  end
end

-- hide ----------------------------------------------------------------------

function M.hide()
  if not win_open() then
    return
  end
  -- record the width before it disappears
  uisize.set("sideterm_width", vim.api.nvim_win_get_width(term.win))
  vim.api.nvim_win_close(term.win, true)
  term.win = nil
end

function M.toggle()
  if win_open() then
    M.hide()
  else
    M.open()
  end
end

-- send a command into the running shell without leaving the editor
function M.send(cmd)
  M.open({ focus = false })
  if term.job then
    vim.fn.chansend(term.job, cmd .. "\n")
  end
end

-- the terminal's window, or nil when hidden
function M.win()
  return win_open() and term.win or nil
end

-- keymaps -------------------------------------------------------------------

-- keymaps for all three panels live in lua/config/panels.lua

-- :Side <cmd> runs something in it without stealing focus
vim.api.nvim_create_user_command("Side", function(o)
  if o.args == "" then
    M.toggle()
  else
    M.send(o.args)
  end
end, { nargs = "*", complete = "shellcmd", desc = "Side terminal: toggle, or run a command in it" })

-- clean up state if the window goes away by other means
vim.api.nvim_create_autocmd("WinClosed", {
  desc = "Side terminal window closed",
  callback = function(args)
    local w = tonumber(args.match)
    if w and term.win == w then
      if vim.api.nvim_win_is_valid(w) then
        uisize.set("sideterm_width", vim.api.nvim_win_get_width(w))
      end
      term.win = nil
    end
  end,
})

return M
