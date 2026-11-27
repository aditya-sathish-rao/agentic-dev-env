# This machine: the Mac you sit at.
#
# It imports the shared base and holds only what is true here. The mini imports
# the same base and none of this.
{ identity, ... }:
{
  imports = [
    ./configuration.nix
    ./tailscale.nix
    ./crew-sandbox.nix
    ./home-manager.nix
  ];

  # VS Code is installed and configured here only. The mini is headless and runs
  # the crew, so it has no editor.
  homebrew.casks = [ "visual-studio-code" ];

  home-manager.users.${identity.username}.imports = [ ./home-vscode.nix ];
}
