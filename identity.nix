# Deliberately impure: the tree follows whoever runs it, so the flake is evaluated
# with --impure and these values come from the environment (rebuild.sh exports the
# AGENTIC_DEV_ENV_* variables; the plain USER/HOME are a convenience for manual nix eval).
let
  # getEnv returns "" for an unset variable, so empty counts as unset.
  envOr =
    primary: fallback:
    let
      value = builtins.getEnv primary;
    in
    if value != "" then value else builtins.getEnv fallback;

  username = envOr "AGENTIC_DEV_ENV_USER" "USER";
  homeDirectory = envOr "AGENTIC_DEV_ENV_HOME" "HOME";
  host =
    let
      value = builtins.getEnv "AGENTIC_DEV_ENV_HOST";
    in
    if value != "" then value else username;
in
if username == "" || homeDirectory == "" then
  throw ''
    identity.nix: could not determine the username or home directory from the environment.
    Run ./rebuild.sh, which evaluates this flake with --impure and exports
    AGENTIC_DEV_ENV_USER, AGENTIC_DEV_ENV_HOME and AGENTIC_DEV_ENV_HOST.
  ''
else
  {
    inherit username homeDirectory host;
  }
