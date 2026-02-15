{ pkgs, ... }:
{
  programs.nvf = {
    enable = true;
    settings = {
      vim = {
        lineNumberMode = "relNumber"; # relative line numbers
        options.mouse = ""; # disable mouse support
        startPlugins = [
          # vim-sleuth - auto-detect shiftwidth and expandtab
          pkgs.vimPlugins.vim-sleuth
          pkgs.vimPlugins.smear-cursor-nvim
          # tiny-inline-diagnostic - VS Code Error Lens-style inline diagnostics
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
        ];
        # Smart-splits - seamless navigation between neovim splits and tmux panes
        utility.smart-splits = {
          enable = true;
          setupOpts.multiplexer_integration = "tmux";
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
        # Inline diagnostics (Error Lens style)
        luaConfigRC.tinyInlineDiagnostic = ''
          vim.diagnostic.config({ virtual_text = false })
          require('tiny-inline-diagnostic').setup({
            preset = "modern",
          })
        '';
        # Smear cursor animation
        luaConfigRC.smearCursor = ''
          require('smear_cursor').setup({})
        '';
        # Smart buffer delete - keeps window open so neo-tree doesn't resize
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
        # Treesitter folding (za/zo/zc/zR/zM)
        treesitter.fold = true;
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
          clang.enable = true;
        };
      };
    };
  };
}
