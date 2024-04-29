{ pkgs, ... }: {
      
      environment.systemPackages =
      [
           
      ];

      services.nix-daemon.enable = true;

      nix.settings.experimental-features = "nix-command flakes";

      programs.zsh.enable = true;

      system.stateVersion = 4;

      nixpkgs.hostPlatform = "aarch64-darwin";

}