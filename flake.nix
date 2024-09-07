{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";
    nixpkgs-6_9-kernel.url = "github:NixOS/nixpkgs?rev=3bfeae1428eac1e60a304268bf7dc218f152b145";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    ################
    # Home Manager #
    ################
    home-manager.url = "github:nix-community/home-manager/release-24.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    # https://github.com/nix-community/home-manager/issues/5717
    home-manager-unstable.url = "github:nix-community/home-manager?rev=587fcca66e9d11c8e2357053c096a8a727c120ab";
    home-manager-unstable.inputs.nixpkgs.follows = "nixpkgs-unstable";
    ##############
    # Nix Darwin #
    ##############
    nix-darwin.url = "github:lnl7/nix-darwin/master";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
    nix-darwin-unstable.url = "github:lnl7/nix-darwin/master";
    nix-darwin-unstable.inputs.nixpkgs.follows = "nixpkgs-unstable";
    ################
    # Nix Homebrew #
    ################
    nix-homebrew.url = "github:zhaofengli-wip/nix-homebrew";
    nix-homebrew.inputs.nixpkgs.follows = "nixpkgs";
    ##########
    # Agenix #
    ##########
    agenix.url = "github:ryantm/agenix";
    agenix.inputs.nixpkgs.follows = "nixpkgs";
    #######
    # NUR #
    #######
    nur.url = "github:nix-community/NUR";
    ##########################
    # nixpkgs-firefox-darwin #
    ##########################
    nixpkgs-firefox-darwin.url = "github:bandithedoge/nixpkgs-firefox-darwin";
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
        inputs.nixpkgs-unstable.lib.nixosSystem {
          inherit system;
          specialArgs = {
            inherit isVM;
          };
          modules = [
            { nixpkgs.overlays = baseOverlays ++ extraOverlays; }
            hostPath
            inputs.home-manager-unstable.nixosModules.home-manager
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
    in
    {
      ############
      # Linux PC #
      ############
      nixosConfigurations."BrightFalls" = mkBrightFalls {
        system = "x86_64-linux";
        hostPath = ./hosts/Brightfalls;
        userPath = ./hosts/Brightfalls/users/matteo;
        extraOverlays = [
          (import ./overlays/brightfalls.nix)
        ];
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
      #########
      # Nexus #
      #########
      nixosConfigurations."Nexus" = inputs.nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          {
            nixpkgs.overlays = [
              (import ./overlay.nix { inherit inputs; })
              inputs.nur.overlay
              (self: super: rec {

                __6_9_pkgs = import inputs.nixpkgs-6_9-kernel {
                  system = "x86_64-linux";
                  config.allowUnfree = true;
                };
                # https://github.com/NixOS/nixpkgs/issues/332350#issuecomment-2312704717
                linuxPackages_6_9 = __6_9_pkgs.linuxPackages_6_9;
              })
            ];
          }
          ./hosts/Nexus
          inputs.home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.users.matteo = import ./hosts/Nexus/users/matteo;
            home-manager.extraSpecialArgs = {
              inherit inputs;
            };
          }
          inputs.agenix.nixosModules.default
          {
            age.identityPaths = [ "/home/matteo/.age/Nexus.txt" ];
            age.secrets."nexus/disk0".file = ./secrets/nexus/disk0.age;
            age.secrets."nexus/disk1".file = ./secrets/nexus/disk1.age;
            age.secrets."nexus/disk2".file = ./secrets/nexus/disk2.age;
            age.secrets."nexus/disk3".file = ./secrets/nexus/disk3.age;
            age.secrets."nexus/disk4".file = ./secrets/nexus/disk4.age;
            age.secrets."nexus/disk5".file = ./secrets/nexus/disk5.age;
            age.secrets."nexus/disk6".file = ./secrets/nexus/disk6.age;
            age.secrets."nexus/disk7".file = ./secrets/nexus/disk7.age;
            age.secrets."nexus/disk8".file = ./secrets/nexus/disk8.age;
            age.secrets."nexus/disk9".file = ./secrets/nexus/disk9.age;
            age.secrets."nexus/janitor.env".file = ./secrets/nexus/janitor.env.age;
          }
        ];
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
      darwinConfigurations."NightSprings" = inputs.nix-darwin-unstable.lib.darwinSystem {
        system = "aarch64-darwin";
        modules = [
          {
            nixpkgs.overlays = [
              (import ./overlay.nix { inherit inputs; })
              inputs.nur.overlay
              inputs.nixpkgs-firefox-darwin.overlay
            ];
          }
          ./hosts/NightSprings
          inputs.home-manager-unstable.darwinModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.users.matteo = import ./hosts/NightSprings/users/matteo;
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
          inputs.agenix.nixosModules.default
          { age.identityPaths = [ "/home/matteo/.age/NightSprings.txt" ]; }
        ];
      };
      #########################
      # Macbook Pro M1 (Work) #
      #########################
      darwinConfigurations."WorkLaptop" = inputs.nix-darwin-unstable.lib.darwinSystem {
        system = "aarch64-darwin";
        modules = [
          {
            nixpkgs.overlays = [
              inputs.nur.overlay
              inputs.nixpkgs-firefox-darwin.overlay
            ];
          }
          ./hosts/WorkLaptop
          inputs.home-manager-unstable.darwinModules.home-manager
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
      ############################
      # Macbook Pro 2012 (Intel) #
      ############################
      darwinConfigurations."Dusk" = inputs.nix-darwin.lib.darwinSystem {
        system = "x86_64-darwin";
        modules = [
          {
            nixpkgs.overlays = [
              (import ./overlay.nix { inherit inputs; })
              inputs.nur.overlay
              inputs.nixpkgs-firefox-darwin.overlay
            ];
          }
          ./hosts/Dusk
          inputs.home-manager.darwinModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.users.matteo = import ./hosts/Dusk/users/matteo;
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
    };
}
