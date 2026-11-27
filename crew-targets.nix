# Which places the crew stack runs on this machine.
#
# The crew is one stack - herdr, the first mate, the crewmates and the worktree
# pool - and it is placed as a unit. There are three places it can live, and they
# differ only in where the boundary is:
#
#   host  the operator's own macOS account. No boundary: the stack runs with the
#         operator's files, gh token and network. This is the laptop.
#   user  a dedicated macOS account. The boundary is macOS user permissions, so
#         it stops the operator's secrets but not their source. Apple builds work,
#         unsigned. This is the mini before the VM.
#   vm    the Lima guest. The boundary is the guest kernel, nftables and the
#         proxy. No Apple builds, because Linux cannot run Xcode.
#
# A host file names the targets it serves; every module that belongs to one target
# gates on it with `lib.mkIf (builtins.elem "<target>" config.crew.targets)`. The
# default is `[ "host" ]`, which is what a single-Mac checkout is.
#
# See docs/host-split-plan.md for the per-target wiring and what each boundary
# actually stops.
{ lib, ... }:
{
  options.crew.targets = lib.mkOption {
    type = lib.types.listOf (
      lib.types.enum [
        "host"
        "user"
        "vm"
      ]
    );
    default = [ "host" ];
    example = [
      "user"
      "vm"
    ];
    description = ''
      The places the crew stack runs on this machine. `host` is the operator's own
      account, `user` a dedicated macOS account, and `vm` the Lima guest. A module
      that belongs to one target gates on it, so a host file names only what is
      true of that machine.
    '';
  };
}
