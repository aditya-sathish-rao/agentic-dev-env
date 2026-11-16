{ config, pkgs, ... }:

let
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
  fonts.fontconfig.enable = true;
  home.sessionVariables.EDITOR = "nvim";
  # Edit in place: the real file stays in my repo, ~/.config just points at it.
  home.file.".config/wezterm".source = 
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/wezterm"; 
}
