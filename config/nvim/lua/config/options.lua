-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here

-- ---------------------------------------------------------------------------
-- Look-only carryover from the previous config. No keymaps, no behaviour.
-- ---------------------------------------------------------------------------

-- block cursor in every mode, insert included
vim.opt.guicursor = "n-v-c-sm:block,i-ci-ve:block,r-cr-o:block"

-- keep more context around the cursor when scrolling
vim.opt.scrolloff = 8

-- no colour column
vim.opt.colorcolumn = "0"

vim.opt.termguicolors = true

-- use basedpyright (better inference than stock pyright) for the lang.python extra
vim.g.lazyvim_python_lsp = "basedpyright"

-- intelephense over the default phpactor: better completion and stubs out of
-- the box, and it is the one installed via mason
vim.g.lazyvim_php_lsp = "intelephense"

-- rounded corners on every floating window that doesn't set its own border
-- (explorer, pickers, hover, help, plugin UIs)
vim.o.winborder = "rounded"

-- remember explorer / run-panel sizes across restarts
require("config.uisize")

-- absolute line numbers in the gutter (LazyVim enables relativenumber by default)
vim.opt.relativenumber = false
