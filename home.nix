{ config, pkgs, ... }:

let
  dotfiles = "${config.home.homeDirectory}/github/dotfiles";
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
      cc = "claude --dangerously-skip-permissions";
      co = "codex --full-auto";
    };
  };

  fonts.fontconfig.enable = true;
  home.sessionVariables.EDITOR = "nvim";
  # Edit in place: the real file stays in my repo, ~/.config just points at it.
  home.file.".config/wezterm".source = 
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/wezterm"; 
}
