{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    ################
    # Home Manager #
    ################
    home-manager.url = "github:nix-community/home-manager/release-24.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    ##############
    # Nix Darwin #
    ##############
    nix-darwin.url = "github:lnl7/nix-darwin/master";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
    ################
    # Nix Homebrew #
    ################
    nix-homebrew.url = "github:zhaofengli-wip/nix-homebrew";
    nix-homebrew.inputs.nixpkgs.follows = "nixpkgs";
    #######
    # NUR #
    #######
    nur.url = "github:nix-community/NUR";
    #################
    # Homebrew Taps #
    #################
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
    ###########
    # Dracula #
    ###########
    xcode-dracula-theme = {
      url = "github:dracula/xcode";
      flake = false;
    };
    colorls-dracula-theme = {
      url = "github:dracula/colorls";
      flake = false;
    };
    sublime-dracula-theme = {
      url = "github:dracula/sublime";
      flake = false;
    };
    dracula-wallpaper = {
      url = "github:dracula/wallpaper";
      flake = false;
    };
    ###############
    # Gnome theme #
    ###############
    firefox-gnome-theme = {
      url = "github:rafaelmardojai/firefox-gnome-theme";
      flake = false;
    };
  };

  outputs =
    inputs:

    let
      baseOverlays = [
        (import ./overlay.nix { inherit inputs; })
        inputs.nur.overlay
      ];
      mkBrightFalls =
        {
          system,
          hostPath,
          userPath,
          extraOverlays ? [ ],
          isVM ? false,
        }:
        inputs.nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = {
            inherit isVM;
          };
          modules = [
            { nixpkgs.overlays = baseOverlays ++ extraOverlays; }
            hostPath
            inputs.home-manager.nixosModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.users.matteo = import userPath;
              home-manager.extraSpecialArgs = {
                inherit inputs isVM;
              };
            }
          ];
        };
      mkNightSprings =
        {
          system,
          hostPath,
          userPath,
          extraOverlays ? [ ],
        }:
        inputs.nix-darwin.lib.darwinSystem {
          inherit system;
          modules = [
            { nixpkgs.overlays = baseOverlays ++ extraOverlays; }
            hostPath
            inputs.home-manager.darwinModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.users.matteo = import userPath;
              home-manager.extraSpecialArgs = {
                inherit inputs;
              };
              home-manager.backupFileExtension = "backup";
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
    in
    {
      ############
      # Linux PC #
      ############
      nixosConfigurations."BrightFalls" = mkBrightFalls {
        system = "x86_64-linux";
        hostPath = ./hosts/Brightfalls;
        userPath = ./hosts/Brightfalls/users/matteo;
        extraOverlays = [ ];
      };
      nixosConfigurations."BrightFallsVM-x86_64-linux" = mkBrightFalls {
        system = "x86_64-linux";
        hostPath = ./hosts/Brightfalls;
        userPath = ./hosts/Brightfalls/users/matteo;
        extraOverlays = [ ];
        isVM = true;
      };
      nixosConfigurations."BrightFallsVM-aarch64-linux" = mkBrightFalls {
        system = "aarch64-linux";
        hostPath = ./hosts/Brightfalls;
        userPath = ./hosts/Brightfalls/users/matteo;
        extraOverlays = [ ];
        isVM = true;
      };
      ################
      # Razer Laptop #
      ################
      nixosConfigurations."CauldronLake" = inputs.nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          {
            nixpkgs.overlays = [
              (import ./overlay.nix { inherit inputs; })
              inputs.nur.overlay
            ];
          }
          ./hosts/CauldronLake
          inputs.home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.users.debora = import ./hosts/CauldronLake/users/debora;
            home-manager.extraSpecialArgs = {
              inherit inputs;
            };
          }
        ];
      };
      ######################
      # Macbook Pro M1 Max #
      ######################
      darwinConfigurations."NightSprings" = mkNightSprings {
        system = "aarch64-darwin";
        hostPath = ./hosts/NightSprings;
        userPath = ./hosts/NightSprings/users/matteo;
        extraOverlays = [ ];
      };
      # Old Intel Macbook Pro (2012) reusing the same configuration
      darwinConfigurations."Dusk" = mkNightSprings {
        system = "x86_64-darwin";
        hostPath = ./hosts/NightSprings;
        userPath = ./hosts/NightSprings/users/matteo;
        extraOverlays = [ ];
      };
      #########################
      # Macbook Pro M1 (Work) #
      #########################
      darwinConfigurations."WorkLaptop" = inputs.nix-darwin.lib.darwinSystem {
        system = "aarch64-darwin";
        modules = [
          {
            nixpkgs.overlays = [
              (import ./overlay.nix { inherit inputs; })
              inputs.nur.overlay
            ];
          }
          ./hosts/WorkLaptop
          inputs.home-manager.darwinModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.users.admin = import ./hosts/WorkLaptop/users/admin;
            home-manager.extraSpecialArgs = {
              inherit inputs;
            };
            home-manager.backupFileExtension = "backup";
          }
          inputs.nix-homebrew.darwinModules.nix-homebrew
          {
            nix-homebrew = {
              enable = true;
              user = "admin";
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
