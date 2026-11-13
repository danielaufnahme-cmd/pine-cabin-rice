-- LazyVim has no lang extra for shell, HTML or CSS, so those servers are wired
-- up by hand here. Everything else (yaml, toml, docker, sql, php, ruby,
-- svelte, tailwind, git) comes from the extras listed in lazyvim.json.
return {
  -- language servers -------------------------------------------------------
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        bashls = {
          -- also handles zsh files, which bash-language-server understands
          filetypes = { "sh", "bash", "zsh" },
        },
        html = {},
        cssls = {},
        emmet_language_server = {
          filetypes = {
            "html",
            "css",
            "scss",
            "less",
            "javascriptreact",
            "typescriptreact",
            "svelte",
            "vue",
            "php",
          },
        },
      },
    },
  },

  -- tools mason should keep installed --------------------------------------
  {
    "mason-org/mason.nvim",
    opts = function(_, opts)
      opts.ensure_installed = opts.ensure_installed or {}
      vim.list_extend(opts.ensure_installed, {
        "bash-language-server",
        "shellcheck",
        "html-lsp",
        "css-lsp",
        "emmet-language-server",
        "prettier",
      })
    end,
  },

  -- linting ----------------------------------------------------------------
  {
    "mfussenegger/nvim-lint",
    opts = {
      linters_by_ft = {
        sh = { "shellcheck" },
        bash = { "shellcheck" },
      },
    },
  },

  -- formatting -------------------------------------------------------------
  {
    "stevearc/conform.nvim",
    opts = {
      formatters_by_ft = {
        sh = { "shfmt" },
        bash = { "shfmt" },
        html = { "prettier" },
        css = { "prettier" },
        scss = { "prettier" },
      },
    },
  },
}
