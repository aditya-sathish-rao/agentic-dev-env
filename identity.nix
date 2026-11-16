# Deliberately impure: the tree follows whoever runs it, so the flake is evaluated
# with --impure and these values come from the environment (rebuild.sh exports the
# DOTFILES_* variables; the plain USER/HOME are a convenience for manual nix eval).
let
  # getEnv returns "" for an unset variable, so empty counts as unset.
  envOr =
    primary: fallback:
    let
      value = builtins.getEnv primary;
    in
    if value != "" then value else builtins.getEnv fallback;

  username = envOr "DOTFILES_USER" "USER";
  homeDirectory = envOr "DOTFILES_HOME" "HOME";
  host =
    let
      value = builtins.getEnv "DOTFILES_HOST";
    in
    if value != "" then value else username;
in
if username == "" || homeDirectory == "" then
  throw ''
    identity.nix: could not determine the username or home directory from the environment.
    Run ./rebuild.sh, which evaluates this flake with --impure and exports
    DOTFILES_USER, DOTFILES_HOME and DOTFILES_HOST.
  ''
else
  {
    inherit username homeDirectory host;
  }
