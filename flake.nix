{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-23.11";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager.url = "github:nix-community/home-manager/release-23.11";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    firefox-gnome-theme = {
      url = "github:rafaelmardojai/firefox-gnome-theme";
      flake = false;
    };
    nix-darwin.url = "github:lnl7/nix-darwin/master";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
    nix-homebrew.url = "github:zhaofengli-wip/nix-homebrew";
    nix-homebrew.inputs.nixpkgs.follows = "nixpkgs";
    homebrew-core = {
      url = "github:homebrew/homebrew-core";
      flake = false;
    };
    homebrew-cask = {
      url = "github:homebrew/homebrew-cask";
      flake = false;
    };
    homebrew-bundle = {
      url = "github:homebrew/homebrew-bundle";
      flake = false;
    };
    xcode-dracula-theme = {
      url = "github:dracula/xcode";
      flake = false;
    };
    colorls-dracula-theme = {
      url = "github:dracula/colorls";
      flake = false;
    };
    radiogogo.url = "github:matteo-pacini/radiogogo";
    radiogogo.inputs.nixpkgs.follows = "nixpkgs-unstable";
  };

  outputs = inputs: {
    # Gaming PC
    nixosConfigurations."BrightFalls" = inputs.nixpkgs.lib.nixosSystem rec {
      system = "x86_64-linux";
      modules = [
        {
          nixpkgs.overlays = [
            (import ./overlays/unstable.nix {inherit inputs;})
            (import ./overlays/unstable-mesa.nix)
            (import ./overlays/minimal-qemu.nix)
            (import ./overlays/reshade-steam-proton.nix)
            (import ./overlays/fixed-unstable-mangohud.nix)
            (
              final: prev: {
                radiogogo = inputs.radiogogo.packages.${system}.radiogogo;
              }
            )
          ];
        }
        ./hosts/Brightfalls
        inputs.home-manager.nixosModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.users.matteo = import ./hosts/Brightfalls/users/matteo;
          home-manager.extraSpecialArgs = {inherit inputs;};
        }
      ];
    };
    # Razer Laptop
    nixosConfigurations."CauldronLake" = inputs.nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        {
          nixpkgs.overlays = [
            (import ./overlays/unstable.nix {inherit inputs;})
          ];
        }
        ./hosts/CauldronLake
        inputs.home-manager.nixosModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.users.debora = import ./hosts/CauldronLake/users/debora;
          home-manager.extraSpecialArgs = {inherit inputs;};
        }
      ];
    };
    # Macbook Pro M1 Max
    darwinConfigurations."NightSprings" = inputs.nix-darwin.lib.darwinSystem rec {
      system = "aarch64-darwin";
      modules = [
        {
          nixpkgs.overlays = [
            (import ./overlays/unstable.nix {inherit inputs;})
            (
              final: prev: {
                radiogogo = inputs.radiogogo.packages.${system}.radiogogo;
              }
            )
          ];
        }
        ./hosts/NightSprings
        inputs.home-manager.darwinModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.users.matteo = import ./hosts/NightSprings/users/matteo;
          home-manager.extraSpecialArgs = {inherit inputs;};
        }
        inputs.nix-homebrew.darwinModules.nix-homebrew
        {
          nix-homebrew = {
            enable = true;
            user = "matteo";
            taps = {
              "homebrew/homebrew-core" = inputs.homebrew-core;
              "homebrew/homebrew-cask" = inputs.homebrew-cask;
              "homebrew/homebrew-bundle" = inputs.homebrew-bundle;
            };
            mutableTaps = false;
          };
        }
      ];
    };
  };
}
