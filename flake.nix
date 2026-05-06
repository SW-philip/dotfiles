{
  description = "NixOS flake: desktop (unstable) + surface/family (25.11) + vm-niri";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixos-hardware.url = "github:NixOS/nixos-hardware";
    home-manager.url = "github:nix-community/home-manager/release-25.11";
    home-manager-unstable.url = "github:nix-community/home-manager/master";
    sops-nix.url = "github:Mic92/sops-nix";
    lanzaboote.url = "github:nix-community/lanzaboote/v0.4.1";
    claude-code.url = "github:sadjow/claude-code-nix";
    helium.url = "gitlab:ntgn/helium-flake";
    ignis.url = "github:linkfrg/ignis";
    nur.url = "github:nix-community/NUR";
    nur.inputs.nixpkgs.follows = "nixpkgs"; # Follow your nixpkgs ver
    lix = {
      url = "https://git.lix.systems/lix-project/lix/archive/main.tar.gz";
      flake = false;
    };
    lix-module = {
      url = "https://git.lix.systems/lix-project/nixos-module/archive/main.tar.gz";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.lix.follows = "lix";
    };
    posys-cursor = {
      url = "github:Morxemplum/posys-cursor-scalable";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

  };

  outputs = inputs@{
    self,
    nixpkgs,
    nixpkgs-unstable,
    nixos-hardware,
    home-manager,
    home-manager-unstable,
    lanzaboote,
    claude-code,
    lix,
    lix-module,
    ...
  }:
  let
    system = "x86_64-linux";
    pkgsFor = system:
      import nixpkgs {
        inherit system;
        overlays = [ self.overlays.default ];
        config.allowUnfree = true;
      };
    pkgsUnstableFor = system:
      import nixpkgs-unstable {
        inherit system;
        overlays = [ self.overlays.default ];
        config.allowUnfree = true;
      };
    overlayModule = {
      nixpkgs.overlays = [
        self.overlays.default
        claude-code.overlays.default
      ];
    };
    allowUnfreeModule = {
      nixpkgs.config.allowUnfree = true;
    };
    # Shared HM options
    hmBase = {
      home-manager.useGlobalPkgs = true;
      home-manager.useUserPackages = true;
      home-manager.extraSpecialArgs = { inherit inputs; };
    };
    # Per-host home profiles for prepko
    hmPrepkoDesktop = {
      home-manager.users.prepko = ./profiles/home/desktop.nix;
    };
    hmPrepkoSurface = {
      home-manager.users.prepko = ./profiles/home/surface.nix;
    };
    # Family home profile
    hmFamily = {
      home-manager.users.family = ./profiles/home/family.nix;
    };
  in
  {
    overlays.default = final: prev: {
      sqlch     = prev.callPackage ./pkgs/sqlch { };
      uniremote = prev.callPackage ./pkgs/uniremote { };
      pandora   = prev.callPackage ./pkgs/pandora { };
    };
    packages.${system} = {
      default = (pkgsFor system).sqlch;
      uniremote = (pkgsFor system).uniremote;
    };
    nixosConfigurations = {
      surface = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = {
          inherit inputs;
          pkgsUnstable = pkgsUnstableFor system;
        };
        modules = [
          overlayModule
          allowUnfreeModule
          lanzaboote.nixosModules.lanzaboote
          lix-module.nixosModules.default
          ./hosts/surface/config.nix
          home-manager.nixosModules.home-manager
          hmBase
          hmPrepkoSurface
          { system.stateVersion = "25.11"; }
        ];
      };
      desktop = nixpkgs-unstable.lib.nixosSystem {
        inherit system;
        specialArgs = {
          inherit inputs;
          pkgsUnstable = pkgsUnstableFor system;
        };
        modules = [
          overlayModule
          allowUnfreeModule
          lix-module.nixosModules.default
          ./hosts/desktop/config.nix
          ./modules/virt.nix
          lanzaboote.nixosModules.lanzaboote
          home-manager-unstable.nixosModules.home-manager
          hmBase
          hmPrepkoDesktop
          { system.stateVersion = "25.11"; }
        ];
      };

      family = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit inputs; };
        modules = [
          overlayModule
          allowUnfreeModule
          ./hosts/family/config.nix
          home-manager.nixosModules.home-manager
          hmBase
          hmFamily
          { system.stateVersion = "25.11"; }
        ];
      };

      vm-niri = nixpkgs-unstable.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit inputs; };
        modules = [
          overlayModule
          allowUnfreeModule
          ./hosts/vm-niri/config.nix
          { system.stateVersion = "25.11"; }
        ];
      };
    };
  };
}
