{
  lib,
  pkgs,
  ...
}:
{
  imports = [ ./perl.nix ];

  config.vim = {
    clipboard = {
      enable = true;
      registers = "unnamedplus";
      providers.wl-copy.enable = pkgs.stdenv.hostPlatform.isLinux;
    };
    lineNumberMode = "relNumber";
    options = {
      mouse = "";
      foldlevel = 99;
      foldlevelstart = 99;
    };
    startPlugins = [
      pkgs.vimPlugins.vim-sleuth
      pkgs.vimPlugins.smear-cursor-nvim
      pkgs.vimPlugins.tiny-inline-diagnostic-nvim
    ];
    theme = {
      enable = true;
      name = "dracula";
    };
    statusline.lualine = {
      enable = true;
      theme = "dracula";
    };
    binds = {
      whichKey.enable = true;
      cheatsheet.enable = true;
    };
    filetree = {
      neo-tree = {
        enable = true;
        setupOpts = {
          git_status_async = true;
          use_libuv_file_watcher = true;
          close_if_last_window = true;
          event_handlers = [
            {
              event = "neo_tree_buffer_enter";
              handler = lib.generators.mkLuaInline ''
                function()
                  vim.opt_local.number = true
                  vim.opt_local.relativenumber = true
                  vim.opt_local.winhighlight = "LineNr:Comment,CursorLineNr:Title"
                end
              '';
            }
          ];
        };
      };
    };
    telescope = {
      enable = true;
      setupOpts = {
        defaults.vimgrep_arguments = [
          (lib.getExe pkgs.ripgrep)
          "--color=never"
          "--no-heading"
          "--with-filename"
          "--line-number"
          "--column"
          "--smart-case"
          "--max-columns=200"
          "--max-columns-preview"
        ];
        pickers.live_grep.additional_args = lib.generators.mkLuaInline ''
          function() return { "--max-filesize=1M" } end
        '';
      };
      extensions = [
        {
          name = "fzf";
          packages = [ pkgs.vimPlugins.telescope-fzf-native-nvim ];
          setup = {
            fzf = {
              fuzzy = true;
              override_generic_sorter = true;
              override_file_sorter = true;
              case_mode = "smart_case";
            };
          };
        }
      ];
    };
    git = {
      enable = true;
      gitsigns.enable = true;
      gitsigns.codeActions.enable = false;
      neogit.enable = true;
    };
    keymaps = [
      {
        key = "<leader>e";
        mode = "n";
        action = ":Neotree toggle<CR>";
        silent = true;
        desc = "Toggle Neo-tree";
      }
      {
        key = "<leader>E";
        mode = "n";
        action = ":Neotree reveal<CR>";
        silent = true;
        desc = "Reveal current buffer in Neo-tree";
      }
      {
        key = "<leader>gg";
        mode = "n";
        action = ":Neogit<CR>";
        silent = true;
        desc = "Open Neogit";
      }
    ];
    utility.smart-splits = {
      enable = true;
      setupOpts.multiplexer_integration = "zellij";
    };
    lsp = {
      enable = true;
      formatOnSave = true;
      lightbulb.enable = true;
      trouble.enable = true;
    };
    autocomplete.nvim-cmp.enable = true;
    assistant.copilot = {
      enable = true;
      cmp.enable = true;
    };
    spellcheck = {
      enable = true;
      languages = [
        "en"
        "it"
      ];
    };
    notify.nvim-notify.enable = true;
    ui.borders.enable = true;
    luaConfigRC.termguicolors = ''
      vim.opt.termguicolors = true
    '';
    luaConfigRC.floatBorder = ''
      vim.o.winborder = 'rounded'
    '';
    luaConfigRC.tinyInlineDiagnostic = ''
      vim.diagnostic.config({ virtual_text = false })
      require('tiny-inline-diagnostic').setup({
        preset = "modern",
      })
    '';
    luaConfigRC.smearCursor = ''
      require('smear_cursor').setup({})
    '';
    luaConfigRC.bufferDelete = ''
      local function smart_bd()
        local current = vim.api.nvim_get_current_buf()
        local bufs = vim.tbl_filter(function(b)
          return vim.api.nvim_buf_is_loaded(b) and vim.bo[b].buflisted
        end, vim.api.nvim_list_bufs())

        if #bufs > 1 then
          vim.cmd('bnext')
          if vim.api.nvim_get_current_buf() == current then
            vim.cmd('bprevious')
          end
        else
          vim.cmd('enew')
        end
        if vim.api.nvim_buf_is_valid(current) then
          vim.cmd('bdelete ' .. current)
        end
      end

      local function delete_other_bufs()
        local current = vim.api.nvim_get_current_buf()
        for _, buf in ipairs(vim.api.nvim_list_bufs()) do
          if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].buflisted and buf ~= current then
            pcall(vim.cmd, 'bdelete ' .. buf)
          end
        end
      end

      vim.keymap.set('n', '<leader>bd', smart_bd, { desc = 'Delete buffer' })
      vim.keymap.set('n', '<leader>bo', delete_other_bufs, { desc = 'Delete other buffers' })
    '';
    luaConfigRC.neogitColors = ''
      vim.api.nvim_set_hl(0, "NeogitDiffAdd", { bg = "#2d4a32", fg = "#f8f8f2" })
      vim.api.nvim_set_hl(0, "NeogitDiffAddHighlight", { bg = "#3d5a42", fg = "#f8f8f2" })
      vim.api.nvim_set_hl(0, "NeogitDiffAddCursor", { bg = "#4d6a52", fg = "#f8f8f2" })
    '';
    tabline.nvimBufferline.enable = true;
    visuals = {
      nvim-cursorline.enable = true;
      cinnamon-nvim.enable = true;
      fidget-nvim.enable = true;
      indent-blankline.enable = true;
      rainbow-delimiters.enable = true;
    };
    treesitter.fold = true;
    languages = {
      enableFormat = true;
      enableTreesitter = true;
      enableExtraDiagnostics = true;
      nix = {
        enable = true;
        format = {
          enable = true;
          type = [ "nixfmt" ];
        };
      };
      bash.enable = true;
      markdown.enable = true;
      typescript.enable = true;
      go.enable = true;
      python = {
        enable = true;
        lsp.servers = [
          "basedpyright"
          "ruff"
        ];
        format = {
          enable = true;
          type = [
            "ruff"
            "ruff-check"
          ];
        };
        extraDiagnostics.enable = false;
      };
      json.enable = true;
      xml.enable = true;
      ruby.enable = true;
      clang.enable = true;
      css.enable = true;
      html.enable = true;
      haskell.enable = true;
      rust = {
        enable = true;
        lsp.opts = ''
          ['rust-analyzer'] = {
            cargo = { allFeatures = true },
            checkOnSave = true,
            check = {
              command = "clippy",
              extraArgs = { "--no-deps" },
            },
            procMacro = { enable = true },
          },
        '';
        extensions.crates-nvim.enable = true;
      };
    };
    lsp.presets.tailwindcss-language-server.enable = true;
  };
}
