{
  config,
  pkgs,
  inputs,
  ...
}: {
  home.file.".config/colorls/dark_colors.yaml".source = "${inputs.colorls-dracula-theme}/dark_colors.yaml";

  programs.autojump = {
    enable = true;
    enableZshIntegration = true;
  };

  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
    defaultOptions = ["--preview 'bat --color=always {}'"];
  };

  programs.bat = {
    enable = true;
    themes = {
      dracula = {
        src = pkgs.fetchFromGitHub {
          owner = "dracula";
          repo = "sublime";
          rev = "26c57ec282abcaa76e57e055f38432bd827ac34e";
          sha256 = "019hfl4zbn4vm4154hh3bwk6hm7bdxbr1hdww83nabxwjn99ndhv";
        };
        file = "Dracula.tmTheme";
      };
    };
    config = {
      theme = "Dracula";
    };
  };

  programs.zsh = {
    enable = true;
    enableCompletion = true;
    enableAutosuggestions = true;
    syntaxHighlighting.enable = true;
    historySubstringSearch.enable = true;
    shellAliases = {
      ls = "colorls --dark";
      reloadDock = ''
        defaults write com.apple.dock ResetLaunchPad -bool true;
        killall Dock;
        defaults write com.apple.dock ResetLaunchPad -bool false
      '';
      reloadSkhd = ''
        launchctl unload /Users/matteo/Library/LaunchAgents/org.nixos.skhd.plist;
        sleep 1;
        launchctl load /Users/matteo/Library/LaunchAgents/org.nixos.skhd.plist;
      '';
      reloadYabai = ''
        launchctl unload /Users/matteo/Library/LaunchAgents/org.nixos.yabai.plist;
        sleep 1;
        launchctl load /Users/matteo/Library/LaunchAgents/org.nixos.yabai.plist;
      '';
    };
  };

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
        "[](bg:black fg:green)"
        "$fill"
        # Right
        "[](bg:black fg:selection)"
        "$character"
        "[](bg:selection fg:comment)"
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
      character = {
        success_symbol = "[](bold bg:selection fg:green)";
        error_symbol = "[](bold bg:selection fg:red)";
        format = "[ $symbol ](bg:selection)";
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
