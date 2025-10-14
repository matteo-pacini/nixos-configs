{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    ################
    # Home Manager #
    ################
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    ##############
    # Nix Darwin #
    ##############
    nix-darwin.url = "github:lnl7/nix-darwin/master";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
    ################
    # Nix Homebrew #
    ################
    nix-homebrew.url = "github:zhaofengli/nix-homebrew";
    ##########
    # Agenix #
    ##########
    agenix.url = "github:ryantm/agenix";
    agenix.inputs.nixpkgs.follows = "nixpkgs";
    #########
    # Disko #
    #########
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";
    #######
    # NUR #
    #######
    nur.url = "github:nix-community/NUR";
    nur.inputs.nixpkgs.follows = "nixpkgs";
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
    ##################
    # Bore Scheduler #
    ##################
    bore-scheduler-src = {
      url = "github:firelzrd/bore-scheduler";
      flake = false;
    };
  };

  outputs =
    inputs@{ self, ... }:

    let
      baseOverlays = [
        (import ./overlays/brightfalls.nix)
        inputs.nur.overlays.default
      ];
      mkBrightFalls =
        {
          system,
          hostPath,
          userPath,
          extraOverlays ? [ ],
          extraModules ? [ ],
          isVM ? false,
        }:
        inputs.nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = {
            inherit inputs isVM;
          };
          modules = [
            { nixpkgs.overlays = baseOverlays ++ extraOverlays; }
            hostPath
            inputs.home-manager.nixosModules.home-manager
            {
              home-manager.backupFileExtension = "backup";
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.users.matteo = import userPath;
              home-manager.extraSpecialArgs = {
                inherit inputs isVM;
              };
            }
          ]
          ++ extraModules;
        };
    in
    {
      ###################
      # Linux Gaming PC #
      ###################
      nixosConfigurations."BrightFalls" = mkBrightFalls {
        system = "x86_64-linux";
        hostPath = ./hosts/Brightfalls;
        userPath = ./hosts/Brightfalls/users/matteo;
        extraModules = [
          inputs.agenix.nixosModules.default
          {
            age.identityPaths = [ "/etc/.age/Nexus.txt" ];
            age.secrets."nexus/mosquitto-brightfalls-password".file =
              ./secrets/nexus/mosquitto-brightfalls-password.age;
          }
        ];
      };
      nixosConfigurations."BrightFallsVM-x86_64-linux" = mkBrightFalls {
        system = "x86_64-linux";
        hostPath = ./hosts/Brightfalls;
        userPath = ./hosts/Brightfalls/users/matteo;
        isVM = true;
        extraModules = [
          inputs.disko.nixosModules.disko
          ./hosts/Brightfalls/disko.nix
        ];
      };
      nixosConfigurations."BrightFallsVM-aarch64-linux" = mkBrightFalls {
        system = "aarch64-linux";
        hostPath = ./hosts/Brightfalls;
        userPath = ./hosts/Brightfalls/users/matteo;
        isVM = true;
        extraModules = [
          inputs.disko.nixosModules.disko
          ./hosts/Brightfalls/disko.nix
        ];
      };
      #########
      # Nexus #
      #########
      nixosConfigurations."Nexus" = inputs.nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          {
            nixpkgs.overlays = [
              (import ./overlays/nexus.nix)
              inputs.nur.overlays.default
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
            age.secrets."nexus/restic-env".file = ./secrets/nexus/restic-env.age;
            age.secrets."nexus/restic-password".file = ./secrets/nexus/restic-password.age;
            age.secrets."nexus/wireguard.env".file = ./secrets/nexus/wireguard.env.age;
            age.secrets."nexus/route53-env".file = ./secrets/nexus/route53-env.age;
            age.secrets."nexus/mosquitto-brightfalls-password".file =
              ./secrets/nexus/mosquitto-brightfalls-password.age;
            age.secrets."nexus/zigbee2mqtt.env" = {
              file = ./secrets/nexus/zigbee2mqtt.env.age;
              owner = "zigbee2mqtt";
              group = "zigbee2mqtt";
              mode = "770";
            };
            age.secrets."nexus/grafana-admin-password" = {
              file = ./secrets/nexus/grafana-admin-password.age;
              owner = "grafana";
              group = "grafana";
              mode = "770";
            };
            age.secrets."nexus/geoip-license-key".file = ./secrets/nexus/geoip-license-key.age;
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
              (import ./overlays/cauldronlake.nix)
              inputs.nur.overlays.default
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
      #########
      # Queen #
      #########
      nixosConfigurations."Queen" = inputs.nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          {
            nixpkgs.overlays = [
              inputs.nur.overlays.default
            ];
          }
          ./hosts/Queen
          inputs.home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.users.antonella = import ./hosts/Queen/users/antonella;
            home-manager.extraSpecialArgs = {
              inherit inputs;
            };
          }
        ];
      };
      ######################
      # Macbook Pro M1 Max #
      ######################
      darwinConfigurations."NightSprings" = inputs.nix-darwin.lib.darwinSystem {
        system = "aarch64-darwin";
        specialArgs = {
          inherit inputs;
          flake = self;
        };
        modules = [
          {
            nixpkgs.overlays = [
              inputs.nur.overlays.default
              (import ./overlays/nightsprings.nix)
            ];
          }
          ./hosts/NightSprings
          inputs.home-manager.darwinModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.users.matteo = import ./hosts/NightSprings/users/matteo;
            home-manager.extraSpecialArgs = {
              inherit inputs;
            };
            home-manager.backupFileExtension = "backup";
            home-manager.sharedModules = [
              self.homeManagerModules.xcodes
            ];
          }
          inputs.nix-homebrew.darwinModules.nix-homebrew
          {
            nix-homebrew = {
              enable = true;
              user = "matteo";
              taps = {
                "homebrew/homebrew-core" = inputs.homebrew-core;
                "homebrew/homebrew-cask" = inputs.homebrew-cask;
              };
              mutableTaps = false;
            };
          }
          inputs.agenix.nixosModules.default
          { age.identityPaths = [ "/home/matteo/.age/NightSprings.txt" ]; }
        ];
      };
      ##############
      # WorkLaptop #
      ##############
      darwinConfigurations."WorkLaptop" = inputs.nix-darwin.lib.darwinSystem {
        system = "aarch64-darwin";
        specialArgs = {
          inherit inputs;
          flake = self;
        };
        modules = [
          {
            nixpkgs.overlays = [
              inputs.nur.overlays.default
              (import ./overlays/worklaptop.nix)
            ];
          }
          ./hosts/WorkLaptop
          inputs.home-manager.darwinModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.users."matteo.pacini" = import ./hosts/WorkLaptop/users/matteo.pacini;
            home-manager.extraSpecialArgs = {
              inherit inputs;
            };
            home-manager.backupFileExtension = "backup";
            home-manager.sharedModules = [
              self.homeManagerModules.xcodes
            ];
          }
          inputs.nix-homebrew.darwinModules.nix-homebrew
          {
            nix-homebrew = {
              enable = true;
              user = "matteo.pacini";
              taps = {
                "homebrew/homebrew-core" = inputs.homebrew-core;
                "homebrew/homebrew-cask" = inputs.homebrew-cask;
              };
              mutableTaps = false;
            };
          }
        ];
      };
      homeManagerModules = {
        xcodes = import ./modules/home-manager/darwin/xcodes.nix;
      };
    };
}
