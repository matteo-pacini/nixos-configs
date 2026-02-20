{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.custom.starship;
in
{
  options.custom.starship = {
    enable = lib.mkEnableOption "Starship prompt with Dracula theme";
  };

  config = lib.mkIf cfg.enable {
    programs.starship = {
      enable = true;
      enableZshIntegration = true;
      package = pkgs.starship;
      settings = {
        scan_timeout = 10;
        format = builtins.concatStringsSep "" [
          # Left
          "[](comment)"
          "$os"
          "$username"
          "$hostname"
          "[ ](bg:comment)"
          "[](bg:purple fg:comment)"
          "$directory"
          "[](bg:green fg:purple)"
          "$git_branch"
          "$git_status"
          "[](bg:pink fg:green)"
          "$direnv"
          "[](fg:pink)"
          "$line_break$line_break"
          "[ 󰌌 ](bg:selection fg:foreground)"
          "[ ](bg:black fg:selection)"
        ];
        right_format = builtins.concatStringsSep "" [
          "[](fg:selection)"
          "$character"
          "[](bg:selection fg:purple)"
          "$nix_shell"
          "[](bg:purple fg:comment)"
          "$time"
        ];
        os = {
          disabled = false;
          symbols = {
            Linux = "";
            Macos = "";
          };
          style = "bold bg:comment fg:foreground";
        };
        username = {
          show_always = true;
          style_user = "bold bg:comment fg:foreground";
          style_root = "bold bg:comment fg:red";
          format = "[ $user]($style)";
        };
        hostname = {
          ssh_only = true;
          ssh_symbol = "";
          style = "bold bg:comment fg:cyan";
          format = "[@$hostname]($style)";
        };
        directory = {
          style = "bold bg:purple fg:black";
          format = "[  $path ]($style)";
          truncation_length = 3;
          truncation_symbol = "…/";
          home_symbol = " ";
          substitutions = {
            "Documents" = "󰈙 ";
            "Downloads" = " ";
            "Music" = "󰝚 ";
            "Pictures" = " ";
          };
        };
        git_branch = {
          symbol = "";
          style = "bg:green";
          format = "[[ $symbol $branch ](bold fg:black bg:green)]($style)";
        };
        git_status = {
          style = "bg:green";
          format = "[[($conflicted$stashed$staged$renamed$deleted$modified$untracked$ahead_behind )](bold fg:black bg:green)]($style)";
          conflicted = "=$count";
          ahead = "⇡$count";
          behind = "⇣$count";
          diverged = "⇡$ahead_count⇣$behind_count";
          up_to_date = "";
          stashed = "*$count";
          staged = "+$count";
          renamed = "»$count";
          deleted = "✘$count";
          modified = "!$count";
          untracked = "?$count";
        };
        direnv = {
          disabled = false;
          style = "bold bg:pink fg:black";
          format = "[ $symbol $loaded ($allowed) ]($style)";
          symbol = "direnv";
        };
        character = {
          success_symbol = "[](bold bg:selection fg:green)";
          error_symbol = "[](bold bg:selection fg:red)";
          format = "[ $symbol ](bg:selection)";
        };
        nix_shell = {
          style = "bold bg:purple fg:black";
          format = "[ $symbol$state (\($name\)) ]($style)";
          symbol = " ";
        };
        time = {
          disabled = false;
          time_format = "%R";
          style = "bold bg:comment fg:foreground";
          format = "[  $time ]($style)";
        };
        palette = "Dracula";
        palettes.Dracula = {
          black = "#282a36";
          selection = "#44475a";
          foreground = "#f8f8f2";
          comment = "#6272a4";
          cyan = "#8be9fd";
          green = "#50fa7b";
          orange = "#ffb86c";
          pink = "#ff79c6";
          purple = "#bd93f9";
          red = "#ff5555";
          yellow = "#f1fa8c";
        };
      };
    };
  };
}
