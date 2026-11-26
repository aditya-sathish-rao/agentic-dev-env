# The headless Mac mini that runs the crew.
#
# It imports the same base as primary.nix, so the two machines stay identical
# until something actually differs. The headless-only settings (never sleep,
# key-only sshd, Screen Sharing recovery, Tailscale as a system daemon) and the
# unattended-secret decision are Phase 3 in docs/host-split-plan.md.
{ ... }:
{
  imports = [
    ./configuration.nix
    ./tailscale.nix
    ./crew-sandbox.nix
    ./home-manager.nix
  ];
}
