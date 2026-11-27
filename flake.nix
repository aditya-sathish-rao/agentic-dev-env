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

      # The guest's user environment, evaluated for Linux and built inside the VM:
      # this Mac has no Linux builder, and the guest has its own Nix.
      #
      # `nix/guest-pi.nix` overrides the two pi files crew-sandbox ships, so the
      # guest's provider and model come from personal.nix rather than the module's
      # DeepSeek default. Without it the gateway would forward to a vendor the
      # operator may no longer hold a key for.
      guestHome = home-manager.lib.homeManagerConfiguration {
        pkgs = nixpkgs.legacyPackages.aarch64-linux;
        modules = [
          crew-sandbox.homeManagerModules.default
          ./nix/guest-pi.nix
        ];
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
      primary = mkDarwin "primary" ./primary.nix;
      mini = mkDarwin "mini" ./mini.nix;

      # The host services and the guest must name the same provider. They are two
      # separate configurations, so nothing but this check stops them drifting
      # apart again. It reads the settled values, not the inputs: the guest's
      # rendered JSON and the flags launchd would actually be given.
      #
      # Read the guest's rendered pi files defensively: if the override is gone the
      # module ships `source` instead of `text`, and home-manager leaves `text` null.
      # A missing attribute here would surface as an opaque evaluation error rather
      # than this check's own message.
      guestFileText =
        name:
        let
          text = guestHome.config.home.file.${name}.text or null;
        in
        if builtins.isString text then text else "";
      guestModels =
        let
          text = guestFileText ".pi/agent/models.json";
        in
        if text == "" then { } else builtins.fromJSON text;
      guestSettings =
        let
          text = guestFileText ".pi/agent/settings.json";
        in
        if text == "" then { } else builtins.fromJSON text;
      # A missing provider is the drift this check exists to catch. Defaulting to an
      # empty set makes the comparisons below false, so the check fails with its own
      # message instead of an "attribute does not exist" evaluation error.
      guestProvider = guestModels.providers.${personal.model.provider} or { };
      proxyArgs = primary.config.services.crew-sandbox._proxyArgs;
      brokerArgs = primary.config.services.crew-sandbox._brokerArgs;
      hasFlag =
        args: flag: value:
        nixpkgs.lib.hasInfix "--${flag} ${value}" (nixpkgs.lib.concatStringsSep " " args);
      modelWiringCorrect =
        (guestProvider.api or null) == "openai-completions"
        && (guestProvider.baseUrl or null) == "http://host.lima.internal:3130/model"
        && (guestProvider.apiKey or null) == "!cat /etc/crew-model-token"
        && (guestSettings.defaultProvider or null) == personal.model.provider
        && (guestSettings.defaultModel or null) == personal.model.name
        && (guestSettings.defaultThinkingLevel or null) == personal.model.thinkingLevel
        && hasFlag proxyArgs "model-upstream" personal.model.upstream
        && hasFlag proxyArgs "model-key-env" personal.model.keySecret
        && hasFlag brokerArgs "app-id" personal.githubApp.id;
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

      homeConfigurations."agent@aarch64-linux" = guestHome;

      # One builder for every machine. A host file imports the shared base and
      # adds only what is true of that machine; see docs/host-split-plan.md.
      darwinConfigurations = {
        inherit primary mini;
      };

      # A buildable assertion, so `nix flake check` and the pre-commit hook fail
      # when the host and guest stop naming the same provider. The failure is a
      # build-time `exit 1` with a readable message rather than a `throw`, because a
      # throw during evaluation surfaces as an opaque "attribute does not exist".
      checks = forAllSystems (
        systemPkgs: system:
        nixpkgs.lib.optionalAttrs (system == "aarch64-darwin") {
          crew-sandbox-model-wiring = systemPkgs.runCommand "agentic-dev-env-crew-sandbox-model-wiring" { } (
            if modelWiringCorrect then
              ''
                mkdir -p $out
              ''
            else
              ''
                echo "crew-sandbox model wiring does not match personal.nix:" >&2
                echo "  the host gateway and the guest's pi config must name the same provider," >&2
                echo "  model and upstream. See nix/guest-pi.nix and personal.nix." >&2
                exit 1
              ''
          );
        }
      );
    };
}
