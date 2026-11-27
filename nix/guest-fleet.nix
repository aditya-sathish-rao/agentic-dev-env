# The guest's crew, for the `vm` target.
#
# crew-sandbox's guest module gives the VM a user, a home and the harness. It does
# not give it the crew: the first mate's clone, its dispatch config, herdr and the
# `mate` alias are this repo's business, and they are the same ones the operator
# has on the host.
#
# The clone is pinned to `home/firstmate/expected-commit`, the same file rebuild.sh
# reads, so the guest and the host run the same firstmate. The pin is applied at
# clone time only, which is what lets `/updatefirstmate` still fast-forward.
#
# Self-update is disabled inside the guest. The guest is a disposable boundary: a
# firstmate that fast-forwards itself would drift from the pin the host was built
# against, and the drift would be invisible until a crewmate behaved differently in
# one place than the other. The pin moves by rebuilding, not by updating in place.
{
  config,
  lib,
  personal,
  ...
}:
let
  # The same pin rebuild.sh reads. A single file, so the two cannot disagree.
  expectedCommit = lib.removeSuffix "\n" (builtins.readFile ../home/firstmate/expected-commit);

  # The first mate's clone. It is a git checkout rather than a store path because
  # firstmate writes into its own tree: config/, state and the worktree pool all
  # live beside the code.
  firstmate = "${config.home.homeDirectory}/firstmate";

  # The gateway is the host's, reached over the Lima shared network. The guest's
  # firewall opens only this port and the egress proxy's.
  gateway = "http://host.lima.internal:3130/model";
in
{
  # herdr arrives through `extraPackages` in flake.nix, not here: the guest module
  # is explicit that the fleet's tools come from the consumer, so this module names
  # no tool set of its own.

  # The model files are generated rather than linked, so the provider and model are
  # declared in personal.nix and nowhere else. The key is the guest's own token,
  # which the host proxy created inside the VM; the real model key never enters it.
  #
  # The first mate's dispatch config and supervision pins are generated from
  # personal.nix for the same reason.
  home = {
    file = {
      ".pi/agent/models.json".text = builtins.toJSON {
        "$schema" = "https://pi.dev/schemas/models.schema.json";
        providers.${personal.model.provider} = {
          api = "openai-completions";
          baseUrl = gateway;
          apiKey = "!cat /etc/crew-model-token";
        };
      };
      ".pi/agent/settings.json".text = builtins.toJSON {
        "$schema" = "https://pi.dev/schemas/settings.schema.json";
        defaultProvider = personal.model.provider;
        defaultModel = personal.model.name;
        defaultThinkingLevel = personal.model.thinkingLevel;
      };
      "firstmate/config/crew-dispatch.json".text = builtins.toJSON {
        shared_quota = true;
        default = [
          {
            harness = "pi";
            provider = personal.model.provider;
          }
        ];
      };
      "firstmate/config/supervision-branch-model".text =
        "${personal.model.supervision.provider}/${personal.model.supervision.name}";
      "firstmate/config/supervision-branch-effort".text = personal.model.supervision.thinkingLevel;
    };

    # The clone itself. `git clone` refuses a non-empty directory, and activation has
    # already created firstmate/config/ for the files above, so the clone is made into
    # a temporary directory and moved into place. The pin is checked out detached and
    # then a branch is created on it, because firstmate's own guards skip a detached
    # HEAD.
    #
    # The clone is skipped when the tree is already a checkout, so a rebuild does not
    # throw away the guest's worktree pool.
    # Runs before linkGeneration, so the clone lands first and home-manager then
    # replaces the clone's own config/ files with the links above. The other order
    # would let the clone overwrite the links.
    activation.firstmateClone = lib.hm.dag.entryBefore [ "linkGeneration" ] ''
      fork=${lib.escapeShellArg personal.firstmate.fork}
      if [[ ! -d ${firstmate}/.git ]]; then
        if [[ -z $fork ]]; then
          echo "firstmate: personal.nix has no firstmate.fork; the guest has no clone." >&2
        else
          echo "firstmate: cloning $fork at ${expectedCommit}" >&2
          tmp=$(mktemp -d)
          run git clone --quiet "$fork" "$tmp/firstmate"
          # -B rather than -c: the clone already has the default branch, so creating
          # it again would fail. -B moves it onto the pin and leaves HEAD attached,
          # which firstmate's own guards require.
          run git -C "$tmp/firstmate" checkout --quiet -B main ${expectedCommit}
          run mkdir -p ${firstmate}
          run cp -R "$tmp/firstmate/." ${firstmate}/
          run rm -rf "$tmp"
        fi
      fi
    '';

    activation.firstmateNoSelfUpdate = lib.hm.dag.entryAfter [ "firstmateClone" ] ''
      if git -C ${firstmate} remote get-url origin >/dev/null 2>&1; then
        run git -C ${firstmate} remote remove origin
      fi
      if ! git -C ${firstmate} remote get-url upstream >/dev/null 2>&1; then
        run git -C ${firstmate} remote add upstream ${lib.escapeShellArg personal.firstmate.upstream}
      fi
    '';
  };

  # `mate` is the operator's alias minus the vault: the guest has no `av`, so the
  # key cannot be injected here and the gateway supplies the model instead.
  programs.zsh = {
    enable = true;
    shellAliases = {
      mate = "(cd ~/firstmate && env FM_BACKEND=herdr pi)";
    };
  };
}
