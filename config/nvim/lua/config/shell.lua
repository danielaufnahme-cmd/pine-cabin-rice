-- Shell and package-install commands, all typed at the `:` prompt.
--
-- The run panel is a real pty, so anything interactive works there: sudo
-- password prompts, y/N confirmations, progress bars.

local runner = require("config.runner")

local function cmd(name, fn, opts)
  vim.api.nvim_create_user_command(name, fn, opts or {})
end

-- :Sh <command>            run a shell command in the bottom panel
cmd("Sh", function(o)
  runner.shell(o.args)
end, { nargs = "+", complete = "shellcmd", desc = "Run a shell command in the panel" })

-- :Sudo <command>          same, but focused so you can type your password
cmd("Sudo", function(o)
  runner.shell("sudo " .. o.args, { focus = true })
end, { nargs = "+", complete = "shellcmd", desc = "Run a command with sudo (asks for password)" })

-- :Pip <packages>          install into this project's virtualenv
cmd("Pip", function(o)
  local py, root = runner.python()
  runner.shell(vim.fn.shellescape(py) .. " -m pip install " .. o.args, { cwd = root })
  vim.notify("Installing into " .. py, vim.log.levels.INFO)
end, { nargs = "+", desc = "pip install into the project venv" })

-- :PipUn <packages>        uninstall from this project's virtualenv
cmd("PipUn", function(o)
  local py, root = runner.python()
  runner.shell(vim.fn.shellescape(py) .. " -m pip uninstall -y " .. o.args, { cwd = root })
end, { nargs = "+", desc = "pip uninstall from the project venv" })

-- :PipList                 what is installed in this project's virtualenv
cmd("PipList", function()
  local py, root = runner.python()
  runner.shell(vim.fn.shellescape(py) .. " -m pip list", { cwd = root })
end, { desc = "List packages in the project venv" })

-- :Which                   which interpreter is this project using?
cmd("Which", function()
  local py, root = runner.python()
  vim.notify(("python: %s\nroot:   %s"):format(py, root), vim.log.levels.INFO)
end, { desc = "Show the python interpreter and project root in use" })

-- :Npm / :Cargo / :Go / :Mvn  package managers for the other languages
cmd("Npm", function(o)
  runner.shell("npm " .. o.args)
end, { nargs = "+", desc = "Run npm in the panel" })

cmd("Cargo", function(o)
  runner.shell("cargo " .. o.args)
end, { nargs = "+", desc = "Run cargo in the panel" })

cmd("Go", function(o)
  runner.shell("go " .. o.args)
end, { nargs = "+", desc = "Run go in the panel" })

-- :Term                    the one side terminal (same as Ctrl-t)
cmd("Term", function()
  require("config.sideterm").open()
end, { desc = "Open the side terminal" })
