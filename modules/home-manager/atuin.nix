{
  config,
  lib,
  ...
}:
let
  cfg = config.custom.atuin;
in
{
  options.custom.atuin = {
    enable = lib.mkEnableOption "Atuin shell history sync";
    syncAddress = lib.mkOption {
      type = lib.types.str;
      description = "Atuin sync server address";
    };
  };

  config = lib.mkIf cfg.enable {
    programs.atuin = {
      enable = true;
      enableZshIntegration = true;
      forceOverwriteSettings = true;
      settings = {
        auto_sync = true;
        sync_frequency = "5m";
        sync_address = cfg.syncAddress;
        search_mode = "fuzzy";
        filter_mode = "global";
        filter_mode_shell_up_key_binding = "directory";
        style = "compact";
        inline_height = 30;
        enter_accept = true;
        update_check = false;
        show_help = false;
        workspaces = true;
        secrets_filter = true;
        history_filter = [
          "^rm " "^shred " "^dd "
        ];
      };
    };
  };
}
