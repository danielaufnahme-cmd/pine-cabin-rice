-- PyCharm-style run panel: <leader>r runs the current file in a persistent
-- terminal split pinned to the bottom of the screen.

local M = {}

local panel = { win = nil, buf = nil, job = nil }

-- remembered across restarts; see lua/config/uisize.lua
local function height()
  local ok, uisize = pcall(require, "config.uisize")
  return ok and uisize.get("panel_height") or 15
end

-- helpers ------------------------------------------------------------------

local function exe(name)
    return vim.fn.executable(name) == 1
end

-- first available executable from a list
local function pick(...)
    for _, name in ipairs({ ... }) do
        if exe(name) then
            return name
        end
    end
end

local function esc(path)
    return vim.fn.shellescape(path)
end

-- nearest ancestor directory containing one of the given markers
local function root_with(file, markers)
    local found = vim.fs.find(markers, { path = vim.fs.dirname(file), upward = true })[1]
    return found and vim.fs.dirname(found) or nil
end

-- build + run a compiled file through a throwaway binary in the temp dir
local function compile_run(cmd, file, extra)
    local out = vim.fn.stdpath("cache") .. "/nvim-run-" .. vim.fn.fnamemodify(file, ":t:r")
    return string.format("%s %s -o %s %s && %s", cmd, esc(file), esc(out), extra or "", esc(out))
end

-- language table -----------------------------------------------------------
-- each entry returns a shell command string, or nil if the toolchain is absent

local runners = {
    python = function(f)
        local py = pick("python3", "python")
        return py and (py .. " " .. esc(f))
    end,

    lua = function(f)
        local lua = pick("lua", "luajit")
        -- fall back to nvim's own interpreter so lua files always run
        return (lua and lua .. " " .. esc(f)) or ("nvim -l " .. esc(f))
    end,

    javascript = function(f)
        local js = pick("node", "bun", "deno")
        if js == "deno" then
            return "deno run -A " .. esc(f)
        end
        return js and (js .. " " .. esc(f))
    end,

    typescript = function(f)
        local ts = pick("bun", "tsx", "ts-node", "deno")
        if ts == "deno" then
            return "deno run -A " .. esc(f)
        end
        if ts then
            return ts .. " " .. esc(f)
        end
        return exe("npx") and ("npx --yes tsx " .. esc(f))
    end,

    go = function(f)
        -- inside a module, `go run .` picks up sibling files
        local root = root_with(f, { "go.mod" })
        if root then
            return "cd " .. esc(root) .. " && go run ."
        end
        return "go run " .. esc(f)
    end,

    rust = function(f)
        local root = root_with(f, { "Cargo.toml" })
        if root then
            return "cd " .. esc(root) .. " && cargo run"
        end
        return exe("rustc") and compile_run("rustc", f)
    end,

    c = function(f)
        local cc = pick("cc", "gcc", "clang")
        return cc and compile_run(cc, f, "-lm")
    end,

    cpp = function(f)
        local cxx = pick("c++", "g++", "clang++")
        return cxx and compile_run(cxx, f, "-std=c++20")
    end,

    java = function(f)
        -- single-file source launch (JEP 330, Java 11+)
        return exe("java") and ("java " .. esc(f))
    end,

    sh = function(f)
        return "bash " .. esc(f)
    end,

    ruby = function(f)
        return exe("ruby") and ("ruby " .. esc(f))
    end,

    php = function(f)
        return exe("php") and ("php " .. esc(f))
    end,

    perl = function(f)
        return exe("perl") and ("perl " .. esc(f))
    end,

    r = function(f)
        return exe("Rscript") and ("Rscript " .. esc(f))
    end,

    julia = function(f)
        return exe("julia") and ("julia " .. esc(f))
    end,

    zig = function(f)
        return exe("zig") and ("zig run " .. esc(f))
    end,

    swift = function(f)
        return exe("swift") and ("swift " .. esc(f))
    end,

    dart = function(f)
        return exe("dart") and ("dart run " .. esc(f))
    end,

    kotlin = function(f)
        return exe("kotlinc") and ("kotlinc -script " .. esc(f))
    end,

    elixir = function(f)
        return exe("elixir") and ("elixir " .. esc(f))
    end,

    haskell = function(f)
        return exe("runghc") and ("runghc " .. esc(f))
    end,

    scala = function(f)
        return exe("scala") and ("scala " .. esc(f))
    end,

    nim = function(f)
        return exe("nim") and ("nim r " .. esc(f))
    end,

    ocaml = function(f)
        return exe("ocaml") and ("ocaml " .. esc(f))
    end,

    cs = function(f)
        local root = root_with(f, { "*.csproj", "*.sln" })
        return root and exe("dotnet") and ("cd " .. esc(root) .. " && dotnet run")
    end,
}

-- filetypes that reuse another entry
runners.bash = runners.sh
runners.zsh = runners.sh
runners.javascriptreact = runners.javascript
runners.typescriptreact = runners.typescript
runners.rmd = runners.r

-- panel --------------------------------------------------------------------

local function panel_open()
    return panel.win and vim.api.nvim_win_is_valid(panel.win)
end

-- open the bottom split without stealing focus from the editor
local function ensure_panel()
    if panel_open() then
        return
    end

    local origin = vim.api.nvim_get_current_win()
    vim.cmd("botright " .. height() .. "split")
    panel.win = vim.api.nvim_get_current_win()

    -- pinned: keeps its height when other windows open or close
    vim.wo[panel.win].winfixheight = true
    vim.wo[panel.win].number = false
    vim.wo[panel.win].relativenumber = false
    vim.wo[panel.win].signcolumn = "no"
    vim.wo[panel.win].foldcolumn = "0"

    vim.api.nvim_set_current_win(origin)
end

-- the run panel's window, or nil when hidden
function M.win()
  return panel_open() and panel.win or nil
end

-- close the window but keep the output (and anything still running) around
function M.hide()
    if panel_open() then
        vim.api.nvim_win_close(panel.win, true)
    end
    panel.win = nil
end

-- show the panel again with the last run's output still in it
function M.show()
    if panel_open() then
        return
    end

    ensure_panel()

    if panel.buf and vim.api.nvim_buf_is_valid(panel.buf) then
        vim.api.nvim_win_set_buf(panel.win, panel.buf)
        return
    end

    -- nothing has been run yet: say so rather than opening a shell
    panel.buf = vim.api.nvim_create_buf(false, true)
    vim.bo[panel.buf].bufhidden = "hide"
    vim.api.nvim_buf_set_lines(panel.buf, 0, -1, false, {
        "",
        "  Output panel — empty.",
        "",
        "  <leader>rr   run the current file here",
        "  Ctrl-t       open the terminal on the right instead",
        "",
    })
    vim.bo[panel.buf].modifiable = false
    vim.b[panel.buf].run_panel = true
    vim.api.nvim_win_set_buf(panel.win, panel.buf)
    vim.keymap.set("n", "q", M.hide, { buffer = panel.buf, nowait = true, desc = "Hide run panel" })
end

-- full teardown: stop whatever is running and forget the output
function M.close()
    if panel.job then
        pcall(vim.fn.jobstop, panel.job)
        panel.job = nil
    end
    if panel_open() then
        vim.api.nvim_win_close(panel.win, true)
    end
    if panel.buf and vim.api.nvim_buf_is_valid(panel.buf) then
        pcall(vim.api.nvim_buf_delete, panel.buf, { force = true })
    end
    panel.win, panel.buf = nil, nil
end

function M.focus()
    if panel_open() then
        vim.api.nvim_set_current_win(panel.win)
    end
end

function M.toggle()
    if panel_open() then
        M.hide()
    else
        M.show()
    end
end

-- run ----------------------------------------------------------------------

function M.run()
    local src = vim.api.nvim_get_current_buf()
    local file = vim.api.nvim_buf_get_name(src)

    if file == "" then
        vim.notify("Run: buffer has no file on disk", vim.log.levels.WARN)
        return
    end

    -- save first so we always execute what's on screen
    if vim.bo[src].modified then
        vim.cmd("silent write")
    end

    local ft = vim.bo[src].filetype
    local build = runners[ft]

    if not build then
        vim.notify("Run: no runner for filetype '" .. ft .. "'", vim.log.levels.WARN)
        return
    end

    local cmd = build(file)
    if not cmd then
        vim.notify("Run: no toolchain found for '" .. ft .. "'", vim.log.levels.WARN)
        return
    end

    ensure_panel()

    -- stop whatever was running before
    if panel.job then
        pcall(vim.fn.jobstop, panel.job)
        panel.job = nil
    end

    -- fresh scratch buffer per run, so output never accumulates
    local old = panel.buf
    panel.buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_win_set_buf(panel.win, panel.buf)
    if old and vim.api.nvim_buf_is_valid(old) then
        vim.api.nvim_buf_delete(old, { force = true })
    end

    local start = vim.uv.hrtime()

    -- run from the file's own directory so relative paths resolve
    panel.job = vim.api.nvim_buf_call(panel.buf, function()
        return vim.fn.jobstart(cmd, {
            term = true,
            cwd = vim.fs.dirname(file),
            on_exit = function(_, code)
                local ms = (vim.uv.hrtime() - start) / 1e6
                local tag = code == 0 and "finished" or ("exited " .. code)
                local level = code == 0 and vim.log.levels.INFO or vim.log.levels.ERROR
                vim.notify(string.format("Run: %s in %.0fms", tag, ms), level)
            end,
        })
    end)

    vim.b[panel.buf].run_panel = true

    -- follow output as it streams
    if panel_open() then
        vim.api.nvim_buf_call(panel.buf, function()
            vim.cmd("normal! G")
        end)
    end

    -- q closes the panel from inside it
    vim.keymap.set("n", "q", M.hide, { buffer = panel.buf, nowait = true, desc = "Hide run panel" })
end

-- arbitrary shell commands in the same panel --------------------------------

-- Run any shell command in the run panel. The panel is a real pty, so
-- interactive prompts (sudo passwords, y/N confirmations) work normally.
-- opts.focus puts the cursor in the panel so you can type into it.
function M.shell(cmd, opts)
  opts = opts or {}

  if not cmd or cmd == "" then
    vim.notify("Shell: nothing to run", vim.log.levels.WARN)
    return
  end

  ensure_panel()

  if panel.job then
    pcall(vim.fn.jobstop, panel.job)
    panel.job = nil
  end

  local old = panel.buf
  panel.buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(panel.win, panel.buf)
  if old and vim.api.nvim_buf_is_valid(old) then
    vim.api.nvim_buf_delete(old, { force = true })
  end

  local start = vim.uv.hrtime()
  local cwd = opts.cwd or vim.uv.cwd()

  panel.job = vim.api.nvim_buf_call(panel.buf, function()
    return vim.fn.jobstart(cmd, {
      term = true,
      cwd = cwd,
      on_exit = function(_, code)
        local ms = (vim.uv.hrtime() - start) / 1e6
        local tag = code == 0 and "finished" or ("exited " .. code)
        vim.notify(
          string.format("Shell: %s in %.0fms", tag, ms),
          code == 0 and vim.log.levels.INFO or vim.log.levels.ERROR
        )
      end,
    })
  end)

  vim.b[panel.buf].run_panel = true
  vim.keymap.set("n", "q", M.hide, { buffer = panel.buf, nowait = true, desc = "Hide run panel" })

  if opts.focus then
    M.focus()
    vim.cmd("startinsert")
  end
end

-- the python interpreter for the current project: prefer a local virtualenv
function M.python()
  local root = vim.fs.root(0, { ".venv", "venv", "pyproject.toml", "setup.py", ".git" })
    or vim.uv.cwd()
  for _, dir in ipairs({ ".venv", "venv", ".env" }) do
    local py = root .. "/" .. dir .. "/bin/python"
    if vim.fn.executable(py) == 1 then
      return py, root
    end
  end
  if vim.env.VIRTUAL_ENV and vim.fn.executable(vim.env.VIRTUAL_ENV .. "/bin/python") == 1 then
    return vim.env.VIRTUAL_ENV .. "/bin/python", root
  end
  return vim.fn.exepath("python3") ~= "" and "python3" or "python", root
end

-- keymaps ------------------------------------------------------------------

-- <leader>rr rather than a bare <leader>r: the config already maps <leader>re,
-- <leader>rn and <leader>rN, so a bare <leader>r would stall for 'timeoutlen'
-- waiting to see if another key follows. The doubled r resolves instantly.
vim.keymap.set("n", "<leader>rr", M.run, { desc = "Run current file in bottom panel" })

-- panel stays pinned; clean up state if it is closed by other means
vim.api.nvim_create_autocmd("WinClosed", {
    callback = function(args)
        if panel.win and tonumber(args.match) == panel.win then
            -- only the window went away; keep the output buffer and any
            -- running job so the panel can be brought back intact
            panel.win = nil
        end
    end,
})

return M
