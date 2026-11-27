{
  config,
  lib,
  pkgs,
  identity,
  piPackage,
  hostName,
  personal,
  ...
}:

let
  # rebuild.sh links the clone here, so the repo can be cloned anywhere.
  agenticDevEnv = "${config.home.homeDirectory}/.agentic-dev-env";

  # The crew's CLIs, pinned in nix/crew-tools. A separate seam from tools.nix so
  # the CI dev shell does not carry a second Node runtime, and named here so the
  # launchd agent below can point at one binary in the store.
  crewTools = import ./crew-tools.nix { inherit pkgs; };

  # The model files are generated from personal.nix rather than linked, so the
  # provider, model and effort are declared in exactly one place. pi writes
  # lastChangelogVersion into settings.json, so a generated file is replaced on
  # every activation; that is the price of one source of truth.
  modelFiles = {
    ".pi/agent/settings.json" = {
      "$schema" = "https://pi.dev/schemas/settings.schema.json";
      defaultProvider = personal.model.provider;
      defaultModel = personal.model.name;
      defaultThinkingLevel = personal.model.thinkingLevel;
    };
    "firstmate/config/crew-dispatch.json" = {
      shared_quota = true;
      default = [
        {
          harness = "pi";
          provider = personal.model.provider;
        }
      ];
    };
  };

  # The supervision branch triages fleet wakes, so it runs the cheaper model at the
  # lower effort while the captain's conversation keeps its own. /supervision-model
  # rewrites these files in place; run ./rebuild.sh to put the pins back.
  supervisionFiles = {
    "firstmate/config/supervision-branch-model" =
      "${personal.model.supervision.provider}/${personal.model.supervision.name}";
    "firstmate/config/supervision-branch-effort" = personal.model.supervision.thinkingLevel;
  };

  # Every directory under home/.agents/skills is one skill or a bundle of skills,
  # so the skill links are generated and a new skill needs no edit here. Both
  # roots are linked because pi and Copilot scan ~/.agents/skills while Claude
  # Code scans ~/.claude/skills.
  #
  # A skill that belongs to one machine only goes in home/.agents/skills-<host>,
  # which is linked on that host and nowhere else. The host comes from the
  # configuration name in flake.nix, not from the environment, so CI evaluating
  # both hosts still checks both directories.
  skillRoots = [
    ".agents"
    ".claude"
  ];
  skillDirs = [
    "home/.agents/skills"
    "home/.agents/skills-${hostName}"
  ];
  # One entry per (root, skill) pair, before listToAttrs collapses them.
  skillNamesByDir = map (
    dir:
    let
      entries = builtins.readDir (./. + "/${dir}");
    in
    builtins.filter (name: entries.${name} == "directory") (builtins.attrNames entries)
  ) skillDirs;
  skillEntries = builtins.concatLists (
    builtins.genList (
      i:
      let
        dir = builtins.elemAt skillDirs i;
        names = builtins.elemAt skillNamesByDir i;
      in
      builtins.concatMap (
        name:
        map (root: {
          name = "${root}/skills/${name}";
          value = "${dir}/${name}";
        }) skillRoots
      ) names
    ) (builtins.length skillDirs)
  );
  skillLinks = builtins.listToAttrs skillEntries;

  # listToAttrs keeps the first of a duplicate name and drops the rest, so a
  # per-host skill that reuses a shared skill's name would silently never link.
  # Catch it here instead of shipping a skill that looks installed and is not.
  allSkillNames = builtins.concatLists skillNamesByDir;
  duplicateSkillNames = builtins.filter (
    name: builtins.length (builtins.filter (other: other == name) allSkillNames) > 1
  ) allSkillNames;

  # $HOME-relative link target -> repo-relative source
  symlinks = {
    ".config/wezterm" = "home/.config/wezterm";
    ".config/nvim" = "home/.config/nvim";
    # Only config.toml: herdr writes its runtime state (sockets, logs, session
    # snapshots) into ~/.config/herdr, and linking the directory put all of it in
    # this repo. Same reason as ~/.pi/agent below.
    ".config/herdr/config.toml" = "home/.config/herdr/config.toml";
    # Claude reads CLAUDE.md; other agents read AGENTS.md - same file, one copy.
    ".claude/CLAUDE.md" = "home/AGENTS.md";
    ".claude/AGENTS.md" = "home/AGENTS.md";
    # Pi's agent directory. Only the two config files are linked, because pi writes
    # its own runtime state (auth.json, trust.json, sessions) into ~/.pi/agent.
    # settings.json is generated from personal.nix (see home.file below), so the
    # model lives in one file; AGENTS.md is the same global instructions file, read
    # here by pi.
    ".pi/agent/AGENTS.md" = "home/AGENTS.md";
    # firstmate stays a manual clone at ~/firstmate (it updates itself); only its
    # local, gitignored dispatch config and supervision pins come from here, and
    # all three are generated from personal.nix so the model is declared once.
    # Shadows the harness so a crewmate pane, which starts without the key `mate`
    # injects, gets the model key from the vault for its own lifetime; the wrapper
    # owns why. ~/.local/bin is first on PATH.
    ".local/bin/pi" = "home/.local/bin/pi";
  }
  // skillLinks;

  # mkOutOfStoreSymlink never checks that its target exists, so a typo in the table
  # above would activate a dangling link and the config would silently be absent.
  missingSources = builtins.filter (target: !builtins.pathExists (./. + "/${symlinks.${target}}")) (
    builtins.attrNames symlinks
  );
in
assert lib.assertMsg (missingSources == [ ])
  "home.nix: these link targets do not exist in the repo: ${lib.concatStringsSep ", " missingSources}";
assert lib.assertMsg (duplicateSkillNames == [ ])
  "home.nix: these skills are defined in more than one skill directory: ${lib.concatStringsSep ", " duplicateSkillNames}";
{
  home = {
    inherit (identity) username homeDirectory;
    stateVersion = "24.11";
    packages =
      with pkgs;
      [
        # cli use i constantly
        ripgrep # fast search
        fd # fast find
        fzf # fuzzy finder
        jq # json on command line
        lazygit
        neovim
        # Swift linting and formatting for the Swift projects. Both are standalone
        # binaries, so no Xcode toolchain comes with them. Run them in strict mode:
        # swiftlint lint --strict, swift-format lint --strict.
        swiftlint
        swift-format
        # the font everything renders in
        nerd-fonts.hack
      ]
      # formatters and linters the checks shell out to, defined once in tools.nix
      ++ (import ./tools.nix { inherit pkgs; })
      # The crew's CLIs and the single Node runtime they are wrapped with, so no
      # tool here floats on an npm global or a curl | sh installer.
      ++ builtins.attrValues crewTools
      ++ [ nodejs_24 ]
      # The agent harness. It comes from the pi flake input rather than nixpkgs
      # because the flake pins the release and ships the Node runtime with it.
      ++ [ piPackage ];
    # firstmate's treehouse and no-mistakes installers put their binaries here
    # (they fall back to a sudo write of /usr/local/bin when this is not on PATH).
    # PATH itself is exported in programs.zsh initContent: .zshenv is wiped by
    # path_helper in a login shell.
    sessionVariables.EDITOR = "nvim";
    # Edit in place: the real file stays in my repo, ~/.config (or Library) points at it.
    file =
      builtins.mapAttrs (_: source: {
        source = config.lib.file.mkOutOfStoreSymlink "${agenticDevEnv}/${source}";
      }) symlinks
      // {
        # Apple's CommandLineTools gitconfig installs an ambient osxkeychain helper, so any
        # process running as me can ask `git credential fill` for a GitHub token. An empty
        # helper resets the inherited list; GitHub auth for this machine is SSH.
        ".config/git/config".text = ''
          [credential]
              helper =
        '';
      }
      // builtins.mapAttrs (_: value: { text = builtins.toJSON value; }) modelFiles
      // builtins.mapAttrs (_: text: { inherit text; }) supervisionFiles
      // {
        # The pi wrapper reads the secret's name from here, so the name lives in
        # personal.nix and not in a tracked script.
        ".config/agentic-dev-env/model-key-secret".text = personal.model.keySecret;
      };

    # A generation that linked the whole ~/.config/herdr directory made the repo's
    # own config.toml the link target, so activating the file link above wrote a
    # store link over that file and closed a loop: ~/.config/herdr -> store -> repo
    # -> store -> ... herdr then failed every config read with "Too many levels of
    # symbolic links" and silently ran on defaults. Only a leftover directory
    # symlink is replaced, because ~/.config/herdr must stay a real directory that
    # herdr writes its sockets, logs and session snapshots into.
    activation.herdr-config-dir = lib.hm.dag.entryBefore [ "linkGeneration" ] ''
      if [[ -L "$HOME/.config/herdr" ]]; then
        run rm -f "$HOME/.config/herdr"
        run mkdir -p "$HOME/.config/herdr"
      fi
    '';
  };

  # no-mistakes runs a background daemon, and its curl | sh installer wrote a
  # plist pointing at ~/.no-mistakes/bin - a path a Nix bump cannot move. Owning
  # the agent here regenerates the plist with the store path; home-manager
  # re-bootstraps an agent whose plist changed, so a bump restarts the daemon on
  # the new binary. The attribute name has to equal Label: home-manager boots the
  # agent out by plist filename.
  launchd.agents."com.kunchenguid.no-mistakes.daemon" = {
    enable = true;
    config = {
      Label = "com.kunchenguid.no-mistakes.daemon";
      ProgramArguments = [
        "${crewTools.no-mistakes}/bin/no-mistakes"
        "daemon"
        "run"
        "--root"
        "${config.home.homeDirectory}/.no-mistakes"
      ];
      WorkingDirectory = "${config.home.homeDirectory}/.no-mistakes";
      # launchd hands an agent a bare PATH. The daemon shells out to git, gh and
      # pi, and pi's wrapper lives in ~/.local/bin.
      EnvironmentVariables = {
        HOME = config.home.homeDirectory;
        PATH = lib.concatStringsSep ":" [
          "${config.home.homeDirectory}/.local/bin"
          "${config.home.profileDirectory}/bin"
          "/opt/homebrew/bin"
          "/opt/homebrew/sbin"
          "/usr/local/bin"
          "/usr/bin"
          "/bin"
          "/usr/sbin"
          "/sbin"
        ];
      };
      StandardOutPath = "${config.home.homeDirectory}/.no-mistakes/logs/daemon-launchd.log";
      StandardErrorPath = "${config.home.homeDirectory}/.no-mistakes/logs/daemon-launchd.log";
      RunAtLoad = true;
      KeepAlive = true;
    };
  };

  programs = {
    zsh = {
      enable = true;
      autosuggestion.enable = true; # ghost text from history
      syntaxHighlighting.enable = true; # commands turn green when valid
      # /etc/zprofile rebuilds PATH with path_helper after .zshenv, so a login shell
      # would drop a .zshenv export. .zshrc runs later, which keeps this one.
      # typeset -U stops a nested shell from appending a second copy of the entry.
      initContent = ''
        typeset -U path
        path=("$HOME/.local/bin" $path)
        bindkey '^f' autosuggest-accept
      '';
      shellAliases = {
        ".." = "cd ..";
        add = "git add .";
        push = "git push";
        pull = "git pull";
        m = "git switch main";
        # The first mate: pi in ~/firstmate, spawning crewmates into herdr. The model
        # is not named here on purpose: pi reads it from ~/.pi/agent/settings.json,
        # which is generated from personal.nix, so swapping the model is one edit
        # there and a rebuild. The key rides along for the mate itself only;
        # crewmate panes come from a herdr server that never saw it, so the pi
        # wrapper in ~/.local/bin injects it per crewmate.
        mate = "(cd ~/firstmate && av inject +${personal.model.keySecret} -- env FM_BACKEND=herdr pi)";
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

    # Apple stores the SSH key passphrase once and hands it back here, so git over SSH
    # works without retyping it (`av scan`: openssh wants the key encrypted at rest).
    ssh = {
      enable = true;
      enableDefaultConfig = false;
      settings."*" = {
        AddKeysToAgent = "yes";
        UseKeychain = "yes";
        IdentityFile = "~/.ssh/id_ed25519";
      };
    };
  };

  fonts.fontconfig.enable = true;
}
