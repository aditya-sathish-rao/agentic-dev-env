# The machine owner's personal values, in one file.
#
# `personal.nix` at the repo root is gitignored: it holds the model and provider,
# the vault secret that holds the model key, the proxy upstream, the GitHub App id
# and the firstmate fork. Copy `personal.nix.example` to `personal.nix` and edit.
# A secret's NAME belongs there; its value belongs in Automic Vault.
#
# The file is imported by absolute path because a flake in a git repository only
# sees tracked files, and personal.nix is deliberately untracked. rebuild.sh and
# .githooks/check export AGENTIC_DEV_ENV_PERSONAL for that reason. When it is
# absent the generic defaults below apply, so a fresh clone still evaluates.
let
  path = builtins.getEnv "AGENTIC_DEV_ENV_PERSONAL";

  defaults = {
    model = {
      provider = "<provider>";
      name = "<model>";
      thinkingLevel = "high";
      keySecret = "MODEL_API_KEY";
      upstream = "https://api.example.com";
      supervision = {
        provider = "<provider>";
        name = "<model>";
        thinkingLevel = "low";
      };
    };
    githubApp.id = "<app-id>";
    firstmate = {
      fork = "";
      upstream = "https://github.com/kunchenguid/firstmate";
    };
  };

  # A partial personal.nix is enough: anything it omits keeps the default above.
  # Written out rather than using lib.recursiveUpdate so this file evaluates with
  # a bare `nix eval`, which rebuild.sh relies on before the flake is built.
  merge =
    base: over:
    base
    // builtins.mapAttrs (
      name: value:
      if builtins.isAttrs value && builtins.hasAttr name base && builtins.isAttrs base.${name} then
        merge base.${name} value
      else
        value
    ) over;
in
merge defaults (if path != "" && builtins.pathExists path then import path else { })
