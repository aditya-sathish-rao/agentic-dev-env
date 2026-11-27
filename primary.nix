# This machine: the Mac you sit at.
#
# It imports the shared base and holds only what is true here. The mini imports
# the same base and none of this.
{ identity, ... }:
{
  imports = [
    ./configuration.nix
    ./tailscale.nix
    ./crew-targets.nix
    ./crew-sandbox.nix
    ./home-manager.nix
  ];

  # The crew runs in the operator's own account here: this is the machine someone
  # sits at, and the boundary that matters is the one around the laptop, not around
  # a second account on it.
  crew.targets = [ "host" ];

  # VS Code is installed and configured here only. The mini is headless and runs
  # the crew, so it has no editor.
  homebrew.casks = [ "visual-studio-code" ];

  home-manager.users.${identity.username}.imports = [ ./home-vscode.nix ];
}
