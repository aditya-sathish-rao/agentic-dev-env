# The headless Mac mini that runs the crew.
#
# It imports the same base as primary.nix, so the two machines stay identical
# until something actually differs. What differs is where the crew runs and that
# nobody sits at this machine: the crew runs as a dedicated account and in the Lima
# guest, and not in the operator's own account.
#
# The headless layer is `kunchenguid/headless`, pinned in flake.nix. It is a module
# rather than a one-off script so a rebuild reproduces the machine: never sleep,
# start after a power cut, key-only sshd, and the automatic sign-in that lets a
# launchd user agent start without anyone logging in.
#
# Automatic sign-in needs FileVault off. That is the Phase 3 decision recorded in
# docs/host-split-plan.md: the mini holds no personal data, so the trade is
# acceptable, and the alternative - a root-only encrypted secret with a non-vault
# backend in crew-sandbox - is not built.
{
  identity,
  headless,
  ...
}:
{
  imports = [
    ./configuration.nix
    ./tailscale.nix
    ./crew-targets.nix
    ./crew-sandbox.nix
    ./crew-user.nix
    ./home-manager.nix
    headless.darwinModules.default
  ];

  # No `host`: the operator's account on this machine is not where the crew runs.
  # `user` is the dedicated account, `vm` the Lima guest. Both reach the same host
  # gateway, which accepts a token per client.
  crew.targets = [
    "user"
    "vm"
  ];

  headless = {
    # The admin account the machine signs in to. It is the operator's account, not
    # `crew`: the crew account is a worker and must not be an administrator.
    user = identity.username;

    # Key-only sshd. The key is the operator's own, so the machine is reachable from
    # a client over Tailscale without a password. The module refuses to evaluate
    # with key-only ssh and no key, which is the assertion that catches a machine
    # nobody could sign in to.
    sshKeys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIITZVYpqPXZoxOLQ/7KgHPB5JDYmvc3/TYNDjkYejO5R aditya.sathish.rao1@gmail.com"
    ];

    # Sign in on the machine's own screen at every start, so the crew-sandbox proxy
    # and broker - launchd *user* agents - start without anyone logging in. Needs
    # FileVault off; the module warns at activation when it is on.
    autoLogin = true;

    # Tailscale is already declared in tailscale.nix as a system daemon, so the
    # module must not install a second copy.
    tailscale.enable = false;
  };
}
