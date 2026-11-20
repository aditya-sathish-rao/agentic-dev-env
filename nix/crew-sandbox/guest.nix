# The guest's toolchain: the same pins as the host, installed for the agent user.
#
# Nothing here may need root. `agent` has no sudo, so this module is the whole
# definition of what the fleet can run inside the VM.
{ pkgs, piPackage, ... }:
let
  # Two shell hooks need the same environment, and they run in different places:
  # initExtra for interactive shells, profileExtra for login shells such as the
  # one `limactl shell` and every ssh session start with.
  environment = ''
    # Single-user Nix keeps its profile in ~/.nix-profile; home-manager owns
    # .profile now, so this is what puts nix and nix-store back on PATH.
    if [ -e "$HOME/.nix-profile/etc/profile.d/nix.sh" ]; then
      . "$HOME/.nix-profile/etc/profile.d/nix.sh"
    fi

  '';
in
{
  # Not NixOS: this makes home-manager set PATH, XDG variables and locale the way
  # a plain Linux distribution expects.
  targets.genericLinux.enable = true;

  home = {
    username = "agent";
    homeDirectory = "/home/agent";
    stateVersion = "26.05";
    packages = [
      piPackage
    ]
    ++ builtins.attrValues (import ../crew-tools/default.nix { inherit pkgs; });
  };

  # The proxy lives in /etc/profile.d/crew-proxy.sh, which every login shell reads;
  # this covers interactive shells that never see a login.
  programs.bash = {
    enable = true;
    initExtra = environment;
  };
}
