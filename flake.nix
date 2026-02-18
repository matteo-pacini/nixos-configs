{
  nixConfig = {
    extra-substituters = [
      "https://zpnixcache.fly.dev/BrightFalls"
      "https://zpnixcache.fly.dev/BrightFallsVM-x86_64-linux"
      "https://zpnixcache.fly.dev/BrightFallsVM-aarch64-linux"
      "https://zpnixcache.fly.dev/Nexus"
      "https://zpnixcache.fly.dev/CauldronLake"
      "https://zpnixcache.fly.dev/NightSprings"
      "https://zpnixcache.fly.dev/WorkLaptop"
    ];
    extra-trusted-public-keys = [
      "BrightFalls:gMudzNSdeCzW745O/B5VSeCLUnpoD1Vj0EbsIV0X6C4="
      "BrightFallsVM-x86_64-linux:L798OfLl6Hcelm1lvSnoisSlUNvlQqIyyOo4UfwLjH8="
      "BrightFallsVM-aarch64-linux:LRzMt4Uzp6sjrCC9Bo1l1ZUJkNM0K6sS8mWmTS2KWmg="
      "Nexus:KhHzSL94AngTFwzZHLZldWY8GIdCGNx0ZsN5w1HqwS8="
      "CauldronLake:AyKsbh7J70m93eOsZJvjtHzgrUgUrPmCY7aOSVQAVF0="
      "NightSprings:iCflayy0sY61Irqnschj7glvKedEEY3mlODEVe61CkY="
      "WorkLaptop:YGElmUpcb7tiuwhpX2gzsEEh4uMQeqKZVYLNF2h0Krg="
    ];
  };

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
    ################
    # Mac App Util #
    ################
    mac-app-util.url = "github:hraban/mac-app-util";
    #######
    # nvf #
    #######
    nvf.url = "github:NotAShelf/nvf";
    nvf.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    inputs@{ self, ... }:

    let
      baseOverlays = [
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
            self.nixosModules.default
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
              home-manager.sharedModules = [
                inputs.nvf.homeManagerModules.default
                self.homeManagerModules.default
              ];
            }
          ]
          ++ extraModules;
        };
    in
    {
      nixosModules.default = {
        imports = [
          ./modules/nixos/nix-core.nix
          ./modules/nixos/locale.nix
          ./modules/nixos/bluetooth.nix
          ./modules/nixos/fonts.nix
          ./modules/nixos/kernel.nix
          ./modules/nixos/apcupsd-multi.nix
        ];
      };

      darwinModules.default = {
        imports = [
          ./modules/darwin/nix-core.nix
          ./modules/darwin/system-defaults.nix
          ./modules/darwin/fonts.nix
        ];
      };

      homeManagerModules.default = {
        imports = [
          ./modules/home-manager/firefox.nix
          ./modules/home-manager/dracula.nix
          ./modules/home-manager/git.nix
          ./modules/home-manager/ssh.nix
          ./modules/home-manager/atuin.nix
          ./modules/home-manager/zsh.nix
          ./modules/home-manager/shell-tools.nix
          ./modules/home-manager/tmux.nix
          ./modules/home-manager/nvf.nix
          ./modules/home-manager/vscode.nix
          ./modules/home-manager/starship.nix
          ./modules/home-manager/wezterm.nix
        ];
      };

      ###################
      # Linux Gaming PC #
      ###################
      nixosConfigurations."BrightFalls" = mkBrightFalls {
        system = "x86_64-linux";
        hostPath = ./hosts/Brightfalls;
        userPath = ./hosts/Brightfalls/users/matteo;
        extraOverlays = [
          (import ./overlays/brightfalls.nix { isVM = false; })
        ];
        extraModules = [
          inputs.disko.nixosModules.disko
          ./hosts/Brightfalls/disko-physical.nix
        ];
      };
      nixosConfigurations."BrightFallsVM-x86_64-linux" = mkBrightFalls {
        system = "x86_64-linux";
        hostPath = ./hosts/Brightfalls;
        userPath = ./hosts/Brightfalls/users/matteo;
        isVM = true;
        extraOverlays = [
          (import ./overlays/brightfalls.nix { isVM = true; })
        ];
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
        extraOverlays = [
          (import ./overlays/brightfalls.nix { isVM = true; })
        ];
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
        specialArgs = {
          inherit inputs;
        };
        modules = [
          {
            nixpkgs.overlays = [
              (import ./overlays/nexus.nix)
              inputs.nur.overlays.default
            ];
          }
          self.nixosModules.default
          ./hosts/Nexus
          inputs.home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.users.matteo = import ./hosts/Nexus/users/matteo;
            home-manager.extraSpecialArgs = {
              inherit inputs;
            };
            home-manager.sharedModules = [
              inputs.nvf.homeManagerModules.default
              self.homeManagerModules.default
            ];
          }
          inputs.agenix.nixosModules.default
          {
            age.identityPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
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
            age.secrets."nexus/nextcloud-admin-password" = {
              file = ./secrets/nexus/nextcloud-admin-password.age;
              owner = "nextcloud";
              group = "nextcloud";
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
        specialArgs = {
          inherit inputs;
        };
        modules = [
          {
            nixpkgs.overlays = [
              (import ./overlays/cauldronlake.nix)
              inputs.nur.overlays.default
            ];
          }
          self.nixosModules.default
          ./hosts/CauldronLake
          inputs.home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.users.debora = import ./hosts/CauldronLake/users/debora;
            home-manager.extraSpecialArgs = {
              inherit inputs;
            };
            home-manager.sharedModules = [
              inputs.nvf.homeManagerModules.default
              self.homeManagerModules.default
            ];
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
          self.darwinModules.default
          ./hosts/NightSprings
          inputs.mac-app-util.darwinModules.default
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
              inputs.mac-app-util.homeManagerModules.default
              inputs.nvf.homeManagerModules.default
              self.homeManagerModules.default
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
          self.darwinModules.default
          ./hosts/WorkLaptop
          inputs.mac-app-util.darwinModules.default
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
              inputs.mac-app-util.homeManagerModules.default
              inputs.nvf.homeManagerModules.default
              self.homeManagerModules.default
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
