-- Quieter diagnostics: no inline text, and basedpyright dialled back from its
-- default "recommended" mode (which flags every un-annotated parameter).
return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      -- no inferred ": None" / "-> None" / "master=" ghost words in the code
      inlay_hints = { enabled = false },
      diagnostics = {
        -- no red/orange text trailing every line; gutter signs + <leader>cd instead
        virtual_text = false,
        -- no squiggles or underlines under flagged code
        underline = false,
        update_in_insert = false,
        severity_sort = true,
      },
      servers = {
        basedpyright = {
          -- point the server at the project's own virtualenv, so imports
          -- installed in .venv resolve instead of falling back to system python
          before_init = function(_, config)
            local root = config.root_dir or vim.uv.cwd()
            for _, dir in ipairs({ ".venv", "venv", ".env" }) do
              local py = root .. "/" .. dir .. "/bin/python"
              if vim.fn.executable(py) == 1 then
                config.settings = config.settings or {}
                config.settings.python = config.settings.python or {}
                config.settings.python.pythonPath = py
                return
              end
            end
          end,
          settings = {
            basedpyright = {
              analysis = {
                -- "recommended" is basedpyright's strictest preset and is the
                -- source of the "Type of X is partially unknown" flood
                typeCheckingMode = "standard",
                autoImportCompletions = true,
                autoSearchPaths = true,
                useLibraryCodeForTypes = true,
                diagnosticMode = "openFilesOnly",
                diagnosticSeverityOverrides = {
                  -- untyped third-party libraries are not your problem
                  reportUnknownParameterType = "none",
                  reportUnknownArgumentType = "none",
                  reportUnknownVariableType = "none",
                  reportUnknownMemberType = "none",
                  reportUnknownLambdaType = "none",
                  reportMissingParameterType = "none",
                  reportMissingTypeStubs = "none",
                  reportAny = "none",
                  reportExplicitAny = "none",
                  reportUnusedCallResult = "none",
                  reportUnannotatedClassAttribute = "none",
                  reportImplicitStringConcatenation = "none",
                },
              },
            },
          },
        },
      },
    },
  },
}
