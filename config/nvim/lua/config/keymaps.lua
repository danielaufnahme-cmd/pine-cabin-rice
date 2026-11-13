-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

-- <leader>rr : save, compile if needed, and run the current file in a
-- pinned bottom panel. Handles python, java, c, c++, rust, go, ts/js and more.
require("config.runner")

-- :Sh, :Sudo, :Pip, :Npm, :Cargo, :Go, :Term — shell commands from the : prompt
require("config.shell")

-- Ctrl-y / Ctrl-g / Ctrl-t : files, output panel, terminal
require("config.sideterm")
require("config.panels")

-- Arrow-key navigation (normal, visual and insert mode):
--   Ctrl-Left / Ctrl-Right : previous / next word
--   Alt-Left  / Alt-Right  : start / end of line
local map = vim.keymap.set
map({ "n", "v" }, "<C-Left>", "b", { desc = "Previous word" })
map({ "n", "v" }, "<C-Right>", "w", { desc = "Next word" })
map({ "n", "v" }, "<M-Left>", "^", { desc = "Start of line" })
map({ "n", "v" }, "<M-Right>", "$", { desc = "End of line" })
map("i", "<C-Left>", "<C-o>b", { desc = "Previous word" })
map("i", "<C-Right>", "<C-o>w", { desc = "Next word" })
map("i", "<M-Left>", "<Home>", { desc = "Start of line" })
map("i", "<M-Right>", "<End>", { desc = "End of line" })

-- qa in normal mode: quit all (asks before discarding unsaved changes).
-- Also :Qa / :QA as typo-safe aliases for :qa.
map("n", "qa", "<cmd>qa<CR>", { desc = "Quit all" })
vim.api.nvim_create_user_command("Qa", "qa<bang>", { bang = true })
vim.api.nvim_create_user_command("QA", "qa<bang>", { bang = true })
