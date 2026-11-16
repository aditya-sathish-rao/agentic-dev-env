{ config, pkgs, ... }:

let
  # bootstrap.sh always links the clone here, so the repo can be cloned anywhere.
  dotfiles = "${config.home.homeDirectory}/.dotfiles";
in

{
  home.username = "m2-pro";
  home.homeDirectory = "/Users/m2-pro";
  home.stateVersion = "24.11";
  home.packages = with pkgs; [
   # cli use i constantly
   ripgrep # fast search
   fd # fast find
   fzf # fuzzy finder
   jq # json on command line
   lazygit
   neovim
   # the font everything renders in
   nerd-fonts.hack
  ];
  
   programs.zsh = {
    enable = true;
    autosuggestion.enable = true;      # ghost text from history
    syntaxHighlighting.enable = true;  # commands turn green when valid
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

  programs.starship = {
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

  fonts.fontconfig.enable = true;
  home.sessionVariables.EDITOR = "nvim";
  # Edit in place: the real file stays in my repo, ~/.config just points at it.
  home.file.".config/wezterm".source = 
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/wezterm";
  
  home.file.".config/nvim".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/nvim";
  
  home.file.".config/herdr".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/herdr";
  
  # macOS keeps VS Code user settings outside ~/.config.
  home.file."Library/Application Support/Code/User/settings.json".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/vscode/settings.json";
  
  home.file.".claude/settings.json".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.claude/settings.json";
  # Claude reads CLAUDE.md; other agents read AGENTS.md - same file, one copy.
  home.file.".claude/CLAUDE.md".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/AGENTS.md";
  home.file.".claude/AGENTS.md".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/AGENTS.md";

  # Apple stores the SSH key passphrase once and hands it back here, so git over SSH
  # works without retyping it (`av scan`: openssh wants the key encrypted at rest).
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    settings."*" = {
      AddKeysToAgent = "yes";
      UseKeychain = "yes";
      IdentityFile = "~/.ssh/id_ed25519";
    };
  };

  # Apple's CommandLineTools gitconfig installs an ambient osxkeychain helper, so any
  # process running as me can ask `git credential fill` for a GitHub token. An empty
  # helper resets the inherited list; GitHub auth for this machine is SSH.
  home.file.".config/git/config".text = ''
    [credential]
    	helper =
  '';

  # Universal (user-level) skills. lavish is shared with other agents via ~/.agents.
  home.file.".claude/skills/stow".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.claude/skills/stow";
  home.file.".claude/skills/lavish".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.agents/skills/lavish";
  home.file.".agents/skills/lavish".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.agents/skills/lavish";
}
