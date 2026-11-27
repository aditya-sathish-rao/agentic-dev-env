{
  description = "agentic-dev-env";

  inputs = {
    # Use `github:NixOS/nixpkgs/nixpkgs-26.05-darwin` to use Nixpkgs 26.05.
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-26.05-darwin";
    # Use `github:nix-darwin/nix-darwin/nix-darwin-26.05` to use Nixpkgs 26.05.
    nix-darwin.url = "github:nix-darwin/nix-darwin/nix-darwin-26.05";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";

    home-manager.url = "github:nix-community/home-manager/release-26.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    nix-homebrew.url = "github:zhaofengli/nix-homebrew";

    # The one agent harness every first mate and crewmate runs. Its package brings
    # its own Node and model catalog, so `pi` and everything it needs come from
    # here, pinned by flake.lock instead of a global npm install.
    pi.url = "github:earendil-works/pi/stable";

    crew-sandbox = {
      url = "github:aditya-sathish-rao/crew-sandbox/v0.1.0";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        home-manager.follows = "home-manager";
        nix-darwin.follows = "nix-darwin";
      };
    };

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
      pi,
      crew-sandbox,
      ...
    }:
    let
      identity = import ./identity.nix;
      piPackage = pi.packages.${builtins.currentSystem}.default;
      # Every personal value - model, provider, key secret, proxy upstream, GitHub
      # App id, firstmate fork - comes from one gitignored file. See nix/personal.nix.
      personal = import ./nix/personal.nix;

      # Output attribute names must be pure: home-manager re-evaluates this flake
      # without --impure inside the guest, and builtins.currentSystem is not there.
      systems = [
        "aarch64-darwin"
        "aarch64-linux"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system} system);

      # One builder for every machine. A host file imports the shared base and
      # adds only what is true of that machine; see docs/host-split-plan.md.
      # hostName is the configuration name, handed down so a module can pick the
      # per-host skill directory without reading the environment again.
      mkDarwin =
        hostName: hostModule:
        nix-darwin.lib.darwinSystem {
          specialArgs = {
            inherit
              identity
              piPackage
              crew-sandbox
              automic-vault-tap
              hostName
              personal
              ;
          };
          modules = [
            nix-homebrew.darwinModules.nix-homebrew
            home-manager.darwinModules.home-manager
            crew-sandbox.darwinModules.default
            hostModule
          ];
        };
    in
    {
      # Same tools the checks need, so CI does not pick them up from a runner's
      # registry: nix develop --impure --command ./.githooks/check --all
      devShells = forAllSystems (
        systemPkgs: _: {
          default = systemPkgs.mkShell {
            packages = import ./tools.nix { pkgs = systemPkgs; };
          };
        }
      );

      # Buildable without switching the system, so CI can prove every pin.
      packages = forAllSystems (
        systemPkgs: system:
        {
          crew-tools = systemPkgs.buildEnv {
            name = "crew-tools";
            paths = builtins.attrValues (import ./nix/crew-tools/default.nix { pkgs = systemPkgs; });
          };

          crew-sandbox = crew-sandbox.packages.${system}.default;
        }
        // nixpkgs.lib.optionalAttrs (system == "aarch64-linux") {
          # Inside the guest, `nix run .#home-manager` needs no registry lookup.
          home-manager = home-manager.packages.aarch64-linux.home-manager;
        }
      );

      # The guest's user environment, evaluated for Linux and built inside the VM:
      # this Mac has no Linux builder, and the guest has its own Nix.
      homeConfigurations."agent@aarch64-linux" = home-manager.lib.homeManagerConfiguration {
        pkgs = nixpkgs.legacyPackages.aarch64-linux;
        modules = [ crew-sandbox.homeManagerModules.default ];
        extraSpecialArgs = {
          inherit personal;
          extraPackages = [
            pi.packages.aarch64-linux.default
          ]
          ++ builtins.attrValues (
            import ./nix/crew-tools/default.nix {
              pkgs = nixpkgs.legacyPackages.aarch64-linux;
            }
          );
        };
      };

      # One builder for every machine. A host file imports the shared base and
      # adds only what is true of that machine; see docs/host-split-plan.md.
      darwinConfigurations = {
        primary = mkDarwin "primary" ./primary.nix;
        mini = mkDarwin "mini" ./mini.nix;
      };
    };
}
