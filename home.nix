{ config, pkgs, ... }:

let
  # bootstrap.sh always links the clone here, so the repo can be cloned anywhere.
  dotfiles = "${config.home.homeDirectory}/.dotfiles";
in
{
  home = {
    username = "m2-pro";
    homeDirectory = "/Users/m2-pro";
    stateVersion = "24.11";
    packages = with pkgs; [
      # cli use i constantly
      ripgrep # fast search
      fd # fast find
      fzf # fuzzy finder
      jq # json on command line
      lazygit
      neovim
      # formatters and linters the pre-commit hook shells out to
      nixfmt
      shfmt
      stylua
      prettier
      taplo
      statix
      deadnix
      shellcheck
      selene
      # the font everything renders in
      nerd-fonts.hack
    ];
    sessionVariables.EDITOR = "nvim";
    file = {
      # Edit in place: the real file stays in my repo, ~/.config just points at it.
      ".config/wezterm".source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/wezterm";
      ".config/nvim".source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/nvim";
      ".config/herdr".source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/herdr";
      # macOS keeps VS Code user settings outside ~/.config.
      "Library/Application Support/Code/User/settings.json".source =
        config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/vscode/settings.json";
      ".claude/settings.json".source =
        config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.claude/settings.json";
      # Claude reads CLAUDE.md; other agents read AGENTS.md - same file, one copy.
      ".claude/CLAUDE.md".source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/AGENTS.md";
      ".claude/AGENTS.md".source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/AGENTS.md";
      # Apple's CommandLineTools gitconfig installs an ambient osxkeychain helper, so any
      # process running as me can ask `git credential fill` for a GitHub token. An empty
      # helper resets the inherited list; GitHub auth for this machine is SSH.
      ".config/git/config".text = ''
        [credential]
            helper =
      '';
      # Universal (user-level) skills. lavish is shared with other agents via ~/.agents.
      ".claude/skills/stow".source =
        config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.claude/skills/stow";
      ".claude/skills/lavish".source =
        config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.agents/skills/lavish";
      ".agents/skills/lavish".source =
        config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.agents/skills/lavish";
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
        # Automic Vault has no claude hardener, so the token is injected at launch
        # from Secret Custody instead of living in settings.json.
        cc = "av inject +ANTHROPIC_AUTH_TOKEN -- claude --dangerously-skip-permissions";
        co = "codex --full-auto";
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
