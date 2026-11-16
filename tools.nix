# Formatters and linters the checks run. Installed for the user in home.nix and
# exposed as a dev shell so CI (and a machine without home-manager) runs the same ones.
{ pkgs }:
with pkgs;
[
  nixfmt
  shfmt
  stylua
  prettier
  taplo
  statix
  deadnix
  shellcheck
  selene
]
