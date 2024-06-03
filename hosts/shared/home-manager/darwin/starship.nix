{
  config,
  pkgs,
  inputs,
  ...
}:
{
  programs.starship = {
    enable = true;
    enableZshIntegration = true;
    package = pkgs.unstable.starship;
    settings = {
      scan_timeout = 10;
      format = builtins.concatStringsSep "" [
        # Left
        "[](comment)"
        "$os"
        "$username"
        "[](bg:purple fg:comment)"
        "$directory"
        "[](bg:green fg:purple)"
        "$git_branch"
        "$git_status"
        "[](bg:pink fg:green)"
        "$direnv"
        "[](bg:black fg:pink)"
        "$fill"
        # Right
        "[](bg:black fg:selection)"
        "$character"
        "[](bg:selection fg:purple)"
        "$nix_shell"
        "[](bg:purple fg:comment)"
        "$time"
        "$line_break$line_break"
        "[ 󰌌 ](bg:selection fg:foreground)"
        "[ ](bg:black fg:selection)"
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
        format = "[ $user ]($style)";
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
        format = "[[($all_status$ahead_behind )](fg:black bg:green)]($style)";
      };
      direnv = {
        disabled = false;
        style = "bold bg:pink fg:black";
        format = "[ $symbol $loaded ($allowed) ]($style)";
        symbol = "direnv";
      };
      fill = {
        symbol = " ";
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
}
