{ pkgs, ... }:
{
  programs.nvf = {
    enable = true;
    settings = {
      vim = {
        lineNumberMode = "number"; # absolute line numbers (not relative)
        # vim-sleuth - auto-detect shiftwidth and expandtab
        startPlugins = [
          pkgs.vimPlugins.vim-sleuth
          pkgs.vimPlugins.smear-cursor-nvim
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
          };
        };
        # Telescope - fuzzy finder for files, buffers, grep, git commits, etc.
        telescope.enable = true;
        # Git integration - gitsigns shows +/- in gutter, blame info
        git = {
          enable = true;
          gitsigns.enable = true;
          gitsigns.codeActions.enable = false;
          neogit.enable = true; # magit-like git interface
        };
        # Keymaps
        keymaps = [
          {
            key = "<leader>e";
            mode = "n";
            action = ":Neotree toggle<CR>";
            silent = true;
            desc = "Toggle Neo-tree";
          }
          {
            key = "<leader>gg";
            mode = "n";
            action = ":Neogit<CR>";
            silent = true;
            desc = "Open Neogit";
          }
          {
            key = "<Esc><Esc>";
            mode = "t";
            action = "<C-\\><C-n>";
            silent = true;
            desc = "Exit terminal mode";
          }
        ];
        # Terminal
        terminal.toggleterm = {
          enable = true;
          setupOpts = {
            direction = "vertical";
            size = 80;
          };
        };
        # LSP - required for language modules to hook into LSP API
        lsp = {
          enable = true;
          formatOnSave = true;
          lightbulb.enable = true;
          trouble.enable = true;
        };
        # Autocomplete - LSP completions, snippets, buffer words
        autocomplete.nvim-cmp.enable = true;
        # Dashboard - startup screen with recent files
        dashboard.alpha.enable = true;
        # Spellcheck
        spellcheck = {
          enable = true;
          languages = [
            "en"
            "it"
          ];
        };
        # Notifications
        notify.nvim-notify.enable = true;
        # UI - borders on floating windows
        ui.borders.enable = true;
        # Global floating window border (Neovim 0.11+)
        luaConfigRC.floatBorder = ''
          vim.o.winborder = 'rounded'
        '';
        # Smear cursor animation
        luaConfigRC.smearCursor = ''
          require('smear_cursor').setup({})
        '';
        # Custom Neogit colors (darker green for additions)
        luaConfigRC.neogitColors = ''
          vim.api.nvim_set_hl(0, "NeogitDiffAdd", { bg = "#2d4a32", fg = "#f8f8f2" })
          vim.api.nvim_set_hl(0, "NeogitDiffAddHighlight", { bg = "#3d5a42", fg = "#f8f8f2" })
          vim.api.nvim_set_hl(0, "NeogitDiffAddCursor", { bg = "#4d6a52", fg = "#f8f8f2" })
        '';
        # Tabline - buffer/tab bar at the top
        tabline.nvimBufferline.enable = true;
        # Visuals
        visuals = {
          nvim-cursorline.enable = true; # highlights current line
          cinnamon-nvim.enable = true; # smooth scrolling
          fidget-nvim.enable = true; # LSP progress indicator
          indent-blankline.enable = true; # indentation guides
          rainbow-delimiters.enable = true; # color-coded matching brackets
        };
        # Language support
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
          ts.enable = true;
          go.enable = true;
          python.enable = true;
          json.enable = true;
          xml.enable = true;
          ruby.enable = true;
        };
      };
    };
  };
}
