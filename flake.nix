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
    xcode-dracula-theme = {
      url = "github:dracula/xcode/master";
      flake = false;
    };
  };

  outputs = inputs: {
    nixosConfigurations."BrightFalls" = inputs.nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        {
          nixpkgs.overlays = [
            (import ./overlays/unstable.nix {inherit inputs;})
            (import ./overlays/unstable-mesa.nix)
            (import ./overlays/minimal-qemu.nix)
            (import ./overlays/reshade-steam-proton.nix)
            (import ./overlays/radiogogo.nix)
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
    darwinConfigurations."NightSprings" = inputs.nix-darwin.lib.darwinSystem {
      system = "aarch64-darwin";
      modules = [
        {
          nixpkgs.overlays = [
            (import ./overlays/unstable.nix {inherit inputs;})
            (import ./overlays/darwin)
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
      ];
    };
  };
}
