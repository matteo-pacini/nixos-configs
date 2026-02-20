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
  wallpaper =
    if pkgs.stdenv.isDarwin then
      "${inputs.dracula-wallpaper}/first-collection/macos.png"
    else
      "${inputs.dracula-wallpaper}/first-collection/nixos.png";
in
{
  options.dracula = {
    wallpaper.enable = mkEnableOption "Activates the Dracula wallpaper on the first monitor";
    eza.enable = mkEnableOption "Activates the Dracula color scheme for eza";
    vscode.enable = mkEnableOption "Activates the Dracula theme for Visual Studio Code";
    xcode.enable = mkEnableOption "Activates the Dracula theme for Xcode";
    fzf.enable = mkEnableOption "Activates the Dracula theme for fzf";
    bat.enable = mkEnableOption "Activates the Dracula theme for bat";
    firefox.enable = mkEnableOption "Activates the Dracula extension for Firefox";
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.wallpaper.enable {
      home.activation.draculaTheme = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        if [ ! -f "${config.home.homeDirectory}/Pictures/wallpaper.png" ]; then
          $DRY_RUN_CMD cp ${wallpaper} ${config.home.homeDirectory}/Pictures/wallpaper.png
        fi
      '';
    })
    (lib.mkIf cfg.eza.enable {
      programs.zsh.initContent = ''
        #### ------------------------------
        #### eza - Color Scheme Definitions
        #### ------------------------------
        export EZA_COLORS="\
        di=1;38;2;189;147;249:\
        ln=38;2;139;233;253:\
        ex=38;2;80;250;123:\
        or=38;2;255;85;85:\
        uu=38;2;139;233;253:\
        gu=38;2;248;248;242:\
        sn=38;2;80;250;123:\
        sb=38;2;80;250;123:\
        da=38;2;98;114;164:\
        ur=38;2;189;147;249:\
        uw=38;2;255;121;198:\
        ux=38;2;80;250;123:\
        ue=38;2;80;250;123:\
        gr=38;2;189;147;249:\
        gw=38;2;255;121;198:\
        gx=38;2;80;250;123:\
        tr=38;2;189;147;249:\
        tw=38;2;255;121;198:\
        tx=38;2;80;250;123:"
      '';
    })
    (lib.mkIf (cfg.vscode.enable && config.programs.vscode.enable) {
      programs.vscode.profiles.default.extensions =
        let
          vscext = pkgs.vscode-extensions;
        in
        [ vscext.dracula-theme.theme-dracula ];
      programs.vscode.profiles.default.userSettings = {
        "workbench.colorTheme" = "Dracula Theme";
      };
    })
    (lib.mkIf (cfg.xcode.enable) {
      home.activation.xcodeDraculaTheme = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        THEMES_DIR="${config.home.homeDirectory}/Library/Developer/Xcode/UserData/FontAndColorThemes"
        [ -d "$THEMES_DIR" ] || mkdir -p "$THEMES_DIR"
        cd "$THEMES_DIR"
        $DRY_RUN_CMD rm -f Dracula.xccolortheme
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
    (lib.mkIf (cfg.firefox.enable && config.programs.firefox.enable) {
      programs.firefox.profiles.default.extensions.packages = [
        pkgs.nur.repos.rycee.firefox-addons.dracula-dark-colorscheme
      ];
    })
  ];
}
