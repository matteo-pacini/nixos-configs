{
  pkgs,
  lib,
  config,
  inputs,
  ...
}:
{
  imports = [
    ./gnome.nix
    ./git.nix
    ./zsh.nix
    ./browser.nix
    ./services.nix
    ./gaming.nix
    inputs.hex.homeManagerModules.hex
  ];

  programs.hex = {
    enable = true;
    shortcut = "control+option+space";
    model = "cohere_transcribe";
    installModel = true;
    autostart = true;
    settings.enable_on_launch = true;
    # Replaces the whole Global mode on every activation, so add replacements
    # here rather than in Hex's Modes pane.
    settings."dictation_processing.default_mode" = {
      name = "Global";
      applications = [ ];
      browser_hosts = [ ];
      post_processing = {
        enabled = false;
        deadline_seconds = 30;
        model = null;
        variant = null;
        prompt = "Rewrite the transcript into clear, natural text while preserving the speaker's intended meaning.";
      };
      replacements = [
        {
          matched_phrase = "slash clear";
          output = "/clear";
        }
        {
          matched_phrase = "slash caveman";
          output = "/caveman";
        }
        {
          matched_phrase = "nix packages";
          output = "nixpkgs";
        }
      ];
      transformations = [ ];
    };
  };

  home.username = "matteo";
  home.homeDirectory = "/home/matteo";

  home.sessionVariables = {
    NIXOS_OZONE_WL = "1";
  }
  // lib.optionalAttrs (pkgs.stdenv.hostPlatform.isx86_64) {
    STEAM_EXTRA_COMPAT_TOOL_PATHS = "${config.home.homeDirectory}/.steam/root/compatibilitytools.d";
  };

  home.packages =
    with pkgs;
    [
      #Gnome
      gnomeExtensions.appindicator
      gnome-tweaks
      inputs.magunetto.packages.${stdenv.hostPlatform.system}.default
      # Downloads
      aria2
      # Security
      _1password-gui
      # Development
      gh
      rotate-github-key
      # Other
      nix-output-monitor
      # Virtualisation
      qemu
      quickemu
      # Gaming
      mangohud
      vulkan-tools
      mesa-demos
      prismlauncher
      # Other
      telegram-desktop
      whatsie
      # Mail
      protonmail-bridge-gui
      # Music
      jellyfin-tui
    ]
    ++ lib.optionals (pkgs.stdenv.hostPlatform.isx86_64) [
      # Gaming
      bottles
      pcsx2
      reshade-linux
      heroic
      # Path of Exile 2
      exiled-exchange-2
      path-of-building-poe2
      # Wine/Proton preload runtime
      linuwux-runtime
      # Other
      discord
    ];

  custom.nvf.enable = true;
  custom.ghostty.enable = true;
  custom.nushell.enable = true;
  custom.starship.enable = true;
  custom.claude-code.enable = true;
  custom.claude-code.chrome.enable = true;
  custom.codex.enable = true;
  custom.opencode.enable = true;
  custom.herdr.enable = true;
  custom.phone.scrcpy.enable = true;
  custom.mpv.enable = true;

  dracula.eza.enable = true;
  dracula.fzf.enable = true;
  dracula.bat.enable = true;

  home.stateVersion = "26.05";

  programs.home-manager.enable = true;
}
