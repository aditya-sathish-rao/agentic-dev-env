{
  config,
  pkgs,
  identity,
  ...
}:

let
  # rebuild.sh links the clone here, so the repo can be cloned anywhere.
  dotfiles = "${config.home.homeDirectory}/.dotfiles";

  # $HOME-relative link target -> repo-relative source
  symlinks = {
    ".config/wezterm" = "home/.config/wezterm";
    ".config/nvim" = "home/.config/nvim";
    ".config/herdr" = "home/.config/herdr";
    ".claude/settings.json" = "home/.claude/settings.json";
    # Claude reads CLAUDE.md; other agents read AGENTS.md - same file, one copy.
    ".claude/CLAUDE.md" = "home/AGENTS.md";
    ".claude/AGENTS.md" = "home/AGENTS.md";
    # Universal (user-level) skills. lavish is shared with other agents via ~/.agents.
    ".claude/skills/stow" = "home/.claude/skills/stow";
    ".claude/skills/lavish" = "home/.agents/skills/lavish";
    ".agents/skills/lavish" = "home/.agents/skills/lavish";
    # Crew: opencode runs the crewmates. Only the file is linked, because opencode
    # writes its own runtime state into ~/.config/opencode.
    ".config/opencode/opencode.json" = "home/.config/opencode/opencode.json";
    # firstmate stays a manual clone at ~/firstmate (it updates itself); only its
    # local, gitignored dispatch config comes from here.
    "firstmate/config/crew-dispatch.json" = "home/firstmate/crew-dispatch.json";
  };

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
        opencode # crewmate harness, see home/firstmate/crew-dispatch.json
        # the font everything renders in
        nerd-fonts.hack
      ]
      # formatters and linters the checks shell out to, defined once in tools.nix
      ++ (import ./tools.nix { inherit pkgs; });
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
      initContent = ''
        bindkey '^f' autosuggest-accept
      '';
      shellAliases = {
        ".." = "cd ..";
        add = "git add .";
        push = "git push";
        pull = "git pull";
        m = "git switch main";
        # Automic Vault has no claude hardener, so the key is injected at launch from
        # Secret Custody, together with the OpenRouter base URL. The tracked
        # settings.json therefore carries no env block at all.
        cc = "av inject +ANTHROPIC_AUTH_TOKEN -- env ANTHROPIC_BASE_URL=https://openrouter.ai/api claude --dangerously-skip-permissions";
        # The first mate: claude in ~/firstmate, spawning crewmates into herdr. The
        # DeepSeek keys ride along so the crewmates inherit them (opencode.json reads
        # them from the environment).
        mate = "(cd ~/firstmate && av inject +ANTHROPIC_AUTH_TOKEN +DEEPSEEK_API_KEY +OPENROUTER_API_KEY -- env ANTHROPIC_BASE_URL=https://openrouter.ai/api FM_BACKEND=herdr claude --dangerously-skip-permissions)";
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
