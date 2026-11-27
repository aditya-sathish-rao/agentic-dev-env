# The dedicated `crew` account's home, for the `user` target.
#
# This is the operator's home config with the operator's things removed. What is
# left is what a crewmate needs to do the work: the harness, the crew CLIs, herdr,
# git, the first mate's clone and its dispatch config. What is gone is everything
# that belongs to a person rather than a worker - the vault, the GitHub CLI's
# hardening, VS Code, the editor and the shell's history.
#
# The boundary this account draws is macOS user permissions, which is weaker than
# the VM: it shares the kernel, the network and the process list. It stops the
# operator's secrets, not their source. See docs/host-split-plan.md.
#
# The model key is deliberately absent. The account reaches the model through the
# host gateway on loopback, presenting a token the operator owns; the real key
# stays in the operator's vault and never enters this home.
{
  pkgs,
  piPackage,
  personal,
  ...
}:
let
  # The crew's CLIs, pinned in nix/crew-tools. The same seam home.nix uses, so the
  # two accounts run the same bytes.
  crewTools = import ./crew-tools.nix { inherit pkgs; };

  # The gateway listens on loopback only, so the account reaches it at 127.0.0.1.
  # The guest reaches the same gateway at host.lima.internal; both are the same
  # proxy, and it accepts a token per client.
  gateway = "http://127.0.0.1:3130/model";

  # The token file the operator owns. crew-sandbox.nix creates the directory with
  # group `crew` and mode 0750, so this account can read the token and nobody else
  # can. The path is repeated rather than imported because the two files are
  # evaluated in different module trees.
  tokenFile = "/etc/crew-sandbox/model-token";
in
{
  home = {
    username = "crew";
    homeDirectory = "/Users/crew";
    stateVersion = "24.11";

    packages =
      with pkgs;
      [
        # What a crewmate actually runs. Deliberately short: every package here is
        # one more thing the account can do that the operator did not intend.
        ripgrep
        fd
        jq
        git
        gh
        nodejs_24
      ]
      # Every pinned crew tool, herdr included: it is the pane server the first mate
      # spawns crewmates into, and it is not in nixpkgs.
      ++ builtins.attrValues crewTools
      ++ [ piPackage ];

    # The model files are generated rather than linked, so the provider and model
    # are declared in personal.nix and nowhere else. The key is the token file, not
    # the model key: the gateway holds the key.
    #
    # The first mate reads its dispatch config and supervision pins from its own
    # tree; they are generated from personal.nix for the same reason.
    file = {
      ".pi/agent/models.json".text = builtins.toJSON {
        "$schema" = "https://pi.dev/schemas/models.schema.json";
        providers.${personal.model.provider} = {
          api = "openai-completions";
          baseUrl = gateway;
          apiKey = "!cat ${tokenFile}";
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
      # The supervision branch triages fleet wakes, so it runs the cheaper model at
      # the lower effort while the captain's conversation keeps its own.
      "firstmate/config/supervision-branch-model".text =
        "${personal.model.supervision.provider}/${personal.model.supervision.name}";
      "firstmate/config/supervision-branch-effort".text = personal.model.supervision.thinkingLevel;
    };
  };

  # The first mate is a clone, not a package: it fast-forwards itself and writes
  # into its own tree. rebuild.sh clones it for the operator; this account's clone
  # is made by the same script when it runs as `crew`, and the pin is the same
  # file, so both accounts run the same commit.
  #
  # `mate` is the operator's alias minus the vault: this account has no `av`, so
  # the key cannot be injected here and the gateway supplies the model instead.
  programs = {
    zsh = {
      enable = true;
      autosuggestion.enable = true;
      syntaxHighlighting.enable = true;
      initContent = ''
        typeset -U path
        path=("$HOME/.local/bin" $path)
      '';
      shellAliases = {
        mate = "(cd ~/firstmate && env FM_BACKEND=herdr pi)";
      };
    };

    starship = {
      enable = true;
      settings = {
        add_newline = false;
        format = "$directory$git_branch$git_status$cmd_duration$line_break$character";
        character = {
          success_symbol = "[❯](purple)";
          error_symbol = "[❯](red)";
        };
        cmd_duration.format = "[$duration]($style) ";
      };
    };

    # The account is a worker, not a person: it has no vault, so it cannot unlock an
    # SSH key and does not need one. Git over HTTPS with the broker's token is the
    # path, and the broker is the operator's.
    ssh = {
      enable = true;
      enableDefaultConfig = false;
    };
  };
}
