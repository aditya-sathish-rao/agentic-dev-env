# The dedicated `crew` account, for the `user` target.
#
# A macOS account is the weakest of the three boundaries: it shares the kernel, the
# network and the process list with the operator. What it does buy is a separate
# home, a separate keychain and a separate set of file permissions, which is enough
# to keep the operator's vault, SSH keys and gh token out of a crewmate's reach.
#
# The account is deliberately not an administrator. It cannot install software, so
# Xcode and its licence are the operator's job (see docs/host-split-plan.md), and it
# cannot change the machine's security settings.
{ config, lib, ... }:
let
  runsUser = builtins.elem "user" config.crew.targets;
in
{
  # The group exists even when the target is off, because crew-sandbox.nix names it
  # as the owner of the token directory and a missing group would fail activation
  # rather than skip it.
  users.groups.crew = lib.mkIf runsUser {
    gid = 1001;
    description = "The crew account and the files it may read";
  };

  users.users.crew = lib.mkIf runsUser {
    uid = 1001;
    gid = 1001;
    home = "/Users/crew";
    createHome = true;
    # A real shell, because the account is logged into: a crewmate runs pi, herdr
    # and git interactively. `/usr/bin/false` is for service accounts.
    shell = "/run/current-system/sw/bin/zsh";
    # Hidden from the login window. The account is reached over SSH or Screen
    # Sharing, not by picking it from a list at the console.
    isHidden = true;
  };

  # The account's home config. Declared here rather than in the shared base because
  # only a machine with the `user` target has the account at all. `imports` must be
  # a list, so the gate wraps the attribute rather than its value.
  home-manager.users = lib.mkIf runsUser {
    crew.imports = [ ./crew-home.nix ];
  };
}
