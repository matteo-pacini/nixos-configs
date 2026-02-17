{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.custom.nvf;
in
{
  options.custom.nvf = {
    enable = lib.mkEnableOption "Neovim configuration via nvf";
  };

  config = lib.mkIf cfg.enable {
    programs.nvf = {
      enable = true;
      settings = {
        vim = {
          clipboard = {
            enable = true;
            registers = "unnamedplus";
            providers.wl-copy.enable = pkgs.stdenv.hostPlatform.isLinux;
          };
          lineNumberMode = "relNumber";
          options.mouse = "";
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
            };
          };
          telescope.enable = true;
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
              key = "<leader>gg";
              mode = "n";
              action = ":Neogit<CR>";
              silent = true;
              desc = "Open Neogit";
            }
          ];
          utility.smart-splits = {
            enable = true;
            setupOpts.multiplexer_integration = "tmux";
          };
          lsp = {
            enable = true;
            formatOnSave = true;
            lightbulb.enable = true;
            trouble.enable = true;
          };
          autocomplete.nvim-cmp.enable = true;
          spellcheck = {
            enable = true;
            languages = [
              "en"
              "it"
            ];
          };
          notify.nvim-notify.enable = true;
          ui.borders.enable = true;
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
  };
}
