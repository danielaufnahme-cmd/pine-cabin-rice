-- Remember how big you dragged the explorer sidebar and the run panel, and
-- restore those sizes on the next launch.
--
-- Sizes are written to stdpath("state")/ui-sizes.json, debounced so dragging a
-- border doesn't hammer the disk.

local M = {}

local path = vim.fs.joinpath(vim.fn.stdpath("state"), "ui-sizes.json")

M.defaults = {
  explorer_width = 34,
  panel_height = 15,
  sideterm_width = 60,
}

M.sizes = vim.deepcopy(M.defaults)

-- read -----------------------------------------------------------------------

local function read()
  local f = io.open(path, "r")
  if not f then
    return
  end
  local raw = f:read("*a")
  f:close()
  local ok, data = pcall(vim.json.decode, raw)
  if ok and type(data) == "table" then
    for k, v in pairs(data) do
      if type(v) == "number" and M.defaults[k] then
        M.sizes[k] = v
      end
    end
  end
end

-- write ----------------------------------------------------------------------

local timer

local function flush()
  local f = io.open(path, "w")
  if f then
    f:write(vim.json.encode(M.sizes))
    f:close()
  end
end

local function write_soon()
  if timer then
    timer:stop()
    timer:close()
    timer = nil
  end
  timer = vim.uv.new_timer()
  timer:start(400, 0, vim.schedule_wrap(function()
    flush()
    if timer then
      timer:stop()
      timer:close()
      timer = nil
    end
  end))
end

---@param key string
---@param value number
function M.set(key, value)
  value = math.floor(value or 0)
  -- ignore nonsense values from transient layout states
  if value < 5 or value > 400 then
    return
  end
  if M.sizes[key] == value then
    return
  end
  M.sizes[key] = value
  write_soon()

  -- keep the live snacks layout in step, so reopening the explorer in this
  -- same session uses the new width too
  if key == "explorer_width" then
    pcall(function()
      local layout = require("snacks.config").picker.sources.explorer.layout.layout
      layout.width = value
      layout.min_width = value
    end)
  end
end

function M.get(key)
  return M.sizes[key] or M.defaults[key]
end

-- track ----------------------------------------------------------------------

local function measure(win)
  if not vim.api.nvim_win_is_valid(win) then
    return
  end
  -- floating windows are not user-resizable splits; skip them
  if vim.api.nvim_win_get_config(win).relative ~= "" then
    return
  end

  local buf = vim.api.nvim_win_get_buf(win)

  -- the explorer sidebar is a snacks layout container pinned to the left
  if vim.bo[buf].filetype == "snacks_layout_box" then
    M.set("explorer_width", vim.api.nvim_win_get_width(win))
    return
  end

  -- the run panel tags its own buffer
  if vim.b[buf].run_panel then
    M.set("panel_height", vim.api.nvim_win_get_height(win))
    return
  end

  -- the right-hand terminal does too
  if vim.b[buf].side_term then
    M.set("sideterm_width", vim.api.nvim_win_get_width(win))
  end
end

function M.setup()
  read()

  vim.api.nvim_create_autocmd("WinResized", {
    desc = "Remember explorer and run-panel sizes",
    callback = function()
      local wins = (vim.v.event or {}).windows
      if type(wins) == "table" then
        for _, w in ipairs(wins) do
          measure(w)
        end
      end
    end,
  })

  -- catch a size set by other means, and make sure it reaches disk on exit
  vim.api.nvim_create_autocmd({ "WinClosed", "VimLeavePre" }, {
    desc = "Flush remembered UI sizes",
    callback = function(args)
      local w = tonumber(args.match)
      if w then
        measure(w)
      end
      if args.event == "VimLeavePre" then
        flush()
      end
    end,
  })
end

M.setup()

return M
