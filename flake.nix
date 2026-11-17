{
  description = "dotfiles";

  inputs = {
    # Use `github:NixOS/nixpkgs/nixpkgs-26.05-darwin` to use Nixpkgs 26.05.
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-26.05-darwin";
    # Use `github:nix-darwin/nix-darwin/nix-darwin-26.05` to use Nixpkgs 26.05.
    nix-darwin.url = "github:nix-darwin/nix-darwin/nix-darwin-26.05";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";

    home-manager.url = "github:nix-community/home-manager/release-26.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    nix-homebrew.url = "github:zhaofengli/nix-homebrew";

    # Homebrew tap with the Automic Vault cask (it is not in homebrew-cask).
    # Pinned by flake.lock and installed as a declarative tap; see configuration.nix.
    automic-vault-tap = {
      url = "github:automic-vault/homebrew-isotopes";
      flake = false;
    };
  };

  outputs =
    {
      nix-darwin,
      home-manager,
      nix-homebrew,
      automic-vault-tap,
      nixpkgs,
      ...
    }:
    let
      identity = import ./identity.nix;
      pkgs = nixpkgs.legacyPackages.${builtins.currentSystem};
    in
    {
      # Same tools the checks need, so CI does not pick them up from a runner's
      # registry: nix develop --impure --command ./.githooks/check --all
      devShells.${builtins.currentSystem}.default = pkgs.mkShell {
        packages = import ./tools.nix { inherit pkgs; };
      };

      darwinConfigurations.${identity.host} = nix-darwin.lib.darwinSystem {
        specialArgs = { inherit identity automic-vault-tap; };
        modules = [
          nix-homebrew.darwinModules.nix-homebrew
          ./configuration.nix
          ./tailscale.nix
          home-manager.darwinModules.home-manager
          {
            home-manager = {
              # darwin specialArgs stop at the darwin modules, so identity has to be
              # handed to the home-manager modules again.
              extraSpecialArgs = { inherit identity; };
              useGlobalPkgs = true;
              useUserPackages = true;
              # A file that exists but is not a home-manager link (an old generated
              # ~/.config/git/config, say) is moved aside instead of aborting the
              # whole activation before any link is written.
              backupFileExtension = "hm-bak";
              users.${identity.username} = import ./home.nix;
            };
          }
        ];
      };
    };
}
