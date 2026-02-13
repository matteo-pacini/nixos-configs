{ pkgs, ... }:
{
  programs.nvf.settings.vim = {
    # Add augment.vim plugin
    startPlugins = [ pkgs.vimPlugins.augment-vim ];
    # Node.js 22+ required for Augment (adds to Neovim's PATH)
    extraPackages = [ pkgs.nodejs_22 ];
    # Configure Augment
    luaConfigRC.augment = ''
      vim.g.augment_workspace_folders = { vim.fn.getcwd() }
      -- Create command to toggle Augment completions
      vim.api.nvim_create_user_command('AugmentToggle', function()
        vim.g.augment_disable_completions = not vim.g.augment_disable_completions
        local status = vim.g.augment_disable_completions and "disabled" or "enabled"
        vim.notify("Augment completions " .. status)
      end, {})
    '';
    # Keymaps (integrates with whichKey)
    keymaps = [
      {
        key = "<leader>aa";
        mode = "n";
        action = ":AugmentToggle<CR>";
        silent = true;
        desc = "Toggle Augment completions";
      }
      {
        key = "<leader>ac";
        mode = "n";
        action = ":Augment chat-toggle<CR>";
        silent = true;
        desc = "Toggle Augment chat";
      }
      {
        key = "<leader>an";
        mode = "n";
        action = ":Augment chat-new<CR>";
        silent = true;
        desc = "New Augment chat";
      }
    ];
  };
}
