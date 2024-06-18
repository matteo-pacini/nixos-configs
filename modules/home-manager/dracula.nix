{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  inherit (lib) mkEnableOption;
  cfg = config.dracula;
  isDarwin = pkgs.stdenv.isDarwin;
in
{
  options.dracula = {
    wallpaper.enable = mkEnableOption "Activates the Dracula wallpaper on the first monitor";
    eza.enable = mkEnableOption "Activates the Dracula color scheme for eza";
    vscode.enable = mkEnableOption "Activates the Dracula theme for Visual Studio Code";
    xcode.enable = mkEnableOption "Activates the Dracula theme for Xcode";
    fzf.enable = mkEnableOption "Activates the Dracula theme for fzf";
    bat.enable = mkEnableOption "Activates the Dracula theme for bat";
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.wallpaper.enable {
      home.file."Pictures/wallpaper.png".source =
        if isDarwin then
          "${inputs.dracula-wallpaper}/first-collection/macos.png"
        else
          "${inputs.dracula-wallpaper}/first-collection/nixos.png";
    })
    (lib.mkIf cfg.eza.enable {
      programs.zsh.initExtra = ''
        #### ------------------------------
        #### eza - Color Scheme Definitions
        #### ------------------------------
        export EZA_COLORS="\
        uu=36:\
        gu=37:\
        sn=32:\
        sb=32:\
        da=34:\
        ur=34:\
        uw=35:\
        ux=36:\
        ue=36:\
        gr=34:\
        gw=35:\
        gx=36:\
        tr=34:\
        tw=35:\
        tx=36:"
      '';
    })
    (lib.mkIf (cfg.vscode.enable && config.programs.vscode.enable) {
      programs.vscode.extensions =
        let
          vscext = pkgs.unstable.vscode-extensions;
        in
        [ vscext.dracula-theme.theme-dracula ];
      programs.vscode.userSettings = {
        "workbench.colorTheme" = "Dracula";
      };
    })
    (lib.mkIf (cfg.xcode.enable && config.programs.xcodes.enable) {
      home.activation.xcodeDraculaTheme = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        THEMES_DIR="${config.home.homeDirectory}/Library/Developer/Xcode/UserData/FontAndColorThemes"
        [ -d "$THEMES_DIR" ] || mkdir -p "$THEMES_DIR"
        cd "$THEMES_DIR"
        [ -f Dracula.xccolortheme ] && unlink Dracula.xccolortheme
        $DRY_RUN_CMD ln -s "${inputs.xcode-dracula-theme}/Dracula.xccolortheme" .
      '';
    })
    (lib.mkIf (cfg.fzf.enable && config.programs.fzf.enable) {
      programs.fzf = {
        defaultOptions = [
          "--color=fg:#f8f8f2,bg:#282a36,hl:#bd93f9"
          "--color=fg+:#f8f8f2,bg+:#44475a,hl+:#bd93f9"
          "--color=info:#ffb86c,prompt:#50fa7b,pointer:#ff79c6"
          "--color=marker:#ff79c6,spinner:#ffb86c,header:#6272a4"
        ];
      };
    })
    (lib.mkIf (cfg.bat.enable && config.programs.bat.enable) {
      programs.bat = {
        themes = {
          dracula = {
            src = inputs.sublime-dracula-theme;
            file = "Dracula.tmTheme";
          };
        };
        config = {
          theme = "Dracula";
        };
      };
    })
  ];
}
