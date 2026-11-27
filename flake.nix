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
      # Pinned to a commit rather than v0.1.0: the tag predates `attach` and
      # `--model-token-file`, and the `user` target needs the flag while the `vm`
      # target needs attach. Move this to a tag once one carries both.
      url = "github:aditya-sathish-rao/crew-sandbox/4137d8755db6e7d8fe2805d00c3af5548d4f16b4";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        home-manager.follows = "home-manager";
        nix-darwin.follows = "nix-darwin";
      };
    };

    # The headless layer for a Mac with no keyboard, screen or person in front of
    # it: never sleep, start after a power cut, key-only sshd, and the automatic
    # sign-in that lets a launchd user agent start without anyone logging in.
    #
    # Pinned to a commit rather than a branch: the repository has no tagged
    # releases, and this module changes system settings with admin rights.
    headless = {
      url = "github:kunchenguid/headless/e9168b7977b39c488241fbfb62bbb12268cd2862";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.nix-darwin.follows = "nix-darwin";
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
      headless,
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
              headless
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
          ./nix/guest-fleet.nix
        ];
        extraSpecialArgs = {
          inherit personal;
          # The fleet's tools. `check toolchain --expected-tools` asserts each of
          # these resolves under /nix/store, so a tool that arrives from the
          # distribution or /usr/local fails the gate rather than passing quietly.
          #
          # git and gh are here because a crewmate clones, commits and opens pull
          # requests; herdr is the pane server the first mate spawns into. herdr is
          # not in nixpkgs, so it comes from the pinned crew-tools set.
          extraPackages = [
            pi.packages.aarch64-linux.default
            nixpkgs.legacyPackages.aarch64-linux.git
            nixpkgs.legacyPackages.aarch64-linux.gh
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
      # The mini runs the crew as a dedicated account as well as in the guest, so its
      # gateway serves two clients and needs the operator's token file. The primary
      # runs the crew in the operator's own account and has no second client.
      miniProxyArgs = mini.config.services.crew-sandbox._proxyArgs;
      hasFlag =
        args: flag: value:
        nixpkgs.lib.hasInfix "--${flag} ${value}" (nixpkgs.lib.concatStringsSep " " args);
      # The guest's toolchain gate asserts each of these resolves under /nix/store, so
      # a tool that arrives from the distribution fails rather than passing quietly.
      guestToolNames = map (p: p.name) guestHome.config.home.packages;
      hasGuestTool = name: builtins.any (n: nixpkgs.lib.hasPrefix "${name}-" n) guestToolNames;
      modelWiringCorrect =
        (guestProvider.api or null) == "openai-completions"
        && (guestProvider.baseUrl or null) == "http://host.lima.internal:3130/model"
        && (guestProvider.apiKey or null) == "!cat /etc/crew-model-token"
        && (guestSettings.defaultProvider or null) == personal.model.provider
        && (guestSettings.defaultModel or null) == personal.model.name
        && (guestSettings.defaultThinkingLevel or null) == personal.model.thinkingLevel
        && hasFlag proxyArgs "model-upstream" personal.model.upstream
        && hasFlag proxyArgs "model-key-env" personal.model.keySecret
        && hasFlag brokerArgs "app-id" personal.githubApp.id
        # The `user` target's token file, on the host that has that target.
        && hasFlag miniProxyArgs "model-token-file" "/etc/crew-sandbox/model-token"
        && !(hasFlag proxyArgs "model-token-file" "/etc/crew-sandbox/model-token")
        # `check toolchain --expected-tools "pi git gh herdr"` must be able to pass.
        && hasGuestTool "pi"
        && hasGuestTool "git"
        && hasGuestTool "gh"
        && hasGuestTool "herdr";
      # Every target is evaluated, not just the ones this machine runs. A host file
      # that names a target whose modules no longer evaluate should fail here rather
      # than on the machine it names.
      #
      # The placement itself is asserted, not derived: the account and the token file
      # both follow `crew.targets`, so comparing them to it would prove nothing. What
      # is worth pinning is which machine runs what, because that is the decision
      # docs/host-split-plan.md records and a host file silently losing a target is
      # exactly the drift this catches.
      hosts = {
        inherit primary mini;
      };
      targetsOf = host: hosts.${host}.config.crew.targets;
      expectedTargets = {
        # The laptop: the crew runs in the operator's own account.
        primary = [ "host" ];
        # The mini: nobody sits at it, so the crew runs as a dedicated account and in
        # the Lima guest, and not in the operator's account.
        mini = [
          "user"
          "vm"
        ];
      };
      allTargets = nixpkgs.lib.unique (nixpkgs.lib.concatMap targetsOf (builtins.attrNames hosts));
      knownTargets = [
        "host"
        "user"
        "vm"
      ];
      # The pieces each target must bring with it, checked against the target rather
      # than against each other.
      hasCrewUser = host: hosts.${host}.config.users.users ? crew;
      hasTokenFile =
        host:
        hasFlag hosts.${host}.config.services.crew-sandbox._proxyArgs "model-token-file"
          "/etc/crew-sandbox/model-token";
      targetsCorrect =
        # Every named target is one the option knows about.
        builtins.all (t: builtins.elem t knownTargets) allTargets
        # Each host runs exactly the placement the plan records.
        && builtins.all (host: targetsOf host == expectedTargets.${host}) (builtins.attrNames hosts)
        # The account and its token file follow the `user` target.
        && builtins.all (
          host:
          let
            runsUser = builtins.elem "user" (targetsOf host);
          in
          hasCrewUser host == runsUser && hasTokenFile host == runsUser
        ) (builtins.attrNames hosts)
        # The guest's home config is what the `vm` target runs, so it must evaluate
        # whenever any host claims that target.
        && (
          !(builtins.elem "vm" allTargets)
          || (guestHome.config.home.activationPackage.drvPath or null) != null
        );
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

          # The targets are a placement decision, so a target that is on must have
          # brought its pieces and a target that is off must not have. This is the
          # check that catches a module gated on the wrong target.
          crew-targets = systemPkgs.runCommand "agentic-dev-env-crew-targets" { } (
            if targetsCorrect then
              ''
                mkdir -p $out
              ''
            else
              ''
                echo "crew.targets does not match the modules each host imports:" >&2
                echo "  primary: ${builtins.toJSON (targetsOf "primary")}" >&2
                echo "  mini:    ${builtins.toJSON (targetsOf "mini")}" >&2
                echo "  the 'user' target must add the crew account and its token file," >&2
                echo "  and the 'vm' target must leave the guest's home config evaluating." >&2
                exit 1
              ''
          );
        }
      );
    };
}
