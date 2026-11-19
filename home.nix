{
  config,
  pkgs,
  identity,
  piPackage,
  ...
}:

let
  # rebuild.sh links the clone here, so the repo can be cloned anywhere.
  dotfiles = "${config.home.homeDirectory}/.dotfiles";

  # Every directory under home/.agents/skills is one skill or a bundle of skills,
  # so the skill links are generated and a new skill needs no edit here. Both
  # roots are linked because pi and Copilot scan ~/.agents/skills while Claude
  # Code scans ~/.claude/skills.
  skills = builtins.readDir ./home/.agents/skills;
  skillNames = builtins.filter (name: skills.${name} == "directory") (builtins.attrNames skills);
  skillRoots = [
    ".agents"
    ".claude"
  ];
  skillLinks = builtins.listToAttrs (
    builtins.concatMap (
      name:
      map (root: {
        name = "${root}/skills/${name}";
        value = "home/.agents/skills/${name}";
      }) skillRoots
    ) skillNames
  );

  # $HOME-relative link target -> repo-relative source
  symlinks = {
    ".config/wezterm" = "home/.config/wezterm";
    ".config/nvim" = "home/.config/nvim";
    ".config/herdr" = "home/.config/herdr";
    # Claude reads CLAUDE.md; other agents read AGENTS.md - same file, one copy.
    ".claude/CLAUDE.md" = "home/AGENTS.md";
    ".claude/AGENTS.md" = "home/AGENTS.md";
    # Pi's agent directory. Only the two config files are linked, because pi writes
    # its own runtime state (auth.json, trust.json, sessions) into ~/.pi/agent.
    # settings.json owns the default model every agent starts on; AGENTS.md is the
    # same global instructions file, read here by pi.
    ".pi/agent/settings.json" = "home/.pi/agent/settings.json";
    ".pi/agent/AGENTS.md" = "home/AGENTS.md";
    # firstmate stays a manual clone at ~/firstmate (it updates itself); only its
    # local, gitignored dispatch config comes from here.
    "firstmate/config/crew-dispatch.json" = "home/firstmate/crew-dispatch.json";
    # Shadows the harness so a crewmate pane, which starts without the key `mate`
    # injects, gets DEEPSEEK_API_KEY from the vault for its own lifetime; the
    # wrapper owns why. ~/.local/bin is first on PATH.
    ".local/bin/pi" = "home/.local/bin/pi";
  }
  // skillLinks;

  # rendered, because the paths inside depend on the logged-in user
  rendered = {
    # macOS keeps VS Code user settings outside ~/.config.
    "Library/Application Support/Code/User/settings.json" = "home/.config/vscode/settings.json";
  };
in
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
        source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/${source}";
      }) symlinks
      // builtins.mapAttrs (_: template: {
        text = builtins.replaceStrings [ "@PROFILE_DIRECTORY@" ] [ config.home.profileDirectory ] (
          builtins.readFile (./. + "/${template}")
        );
      }) rendered
      // {
        # Apple's CommandLineTools gitconfig installs an ambient osxkeychain helper, so any
        # process running as me can ask `git credential fill` for a GitHub token. An empty
        # helper resets the inherited list; GitHub auth for this machine is SSH.
        ".config/git/config".text = ''
          [credential]
              helper =
        '';
      };
  };

  programs = {
    zsh = {
      enable = true;
      autosuggestion.enable = true; # ghost text from history
      syntaxHighlighting.enable = true; # commands turn green when valid
      # /etc/zprofile rebuilds PATH with path_helper after .zshenv, so a login shell
      # would drop a .zshenv export. .zshrc runs later, which keeps this one.
      initContent = ''
        export PATH="$HOME/.local/bin:$PATH"
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
        # so swapping the model is one line in that file and needs no rebuild. The
        # key rides along for the mate itself only;
        # crewmate panes come from a herdr server that never saw it, so the pi
        # wrapper in ~/.local/bin injects it per crewmate.
        mate = "(cd ~/firstmate && av inject +DEEPSEEK_API_KEY -- env FM_BACKEND=herdr pi)";
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
