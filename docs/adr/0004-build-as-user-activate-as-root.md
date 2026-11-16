# 0004. Build as the user, activate as root

- Status: Accepted
- Date: 2026-11-16

## Context

A nix-darwin switch needs two things: an evaluation of this flake, and root for the
activation step, which writes `/etc`, `/run` and the system profile.

Root cannot evaluate a git flake that another user owns. `libgit2` refuses with
`repository path is not owned by current user`, so `sudo darwin-rebuild switch` fails on a
clone owned by the login user. It also needs `darwin-rebuild` to exist, which it does not
on a fresh machine.

Running the whole script as root has the matching problem in reverse: it would clone,
evaluate and build a store path owned by root, and every later build by the user would
diverge.

## Decision

Split the two halves. `rebuild.sh` runs as the invoking user and does the evaluation and
build:

```sh
nix build --impure "$DIR#darwinConfigurations.$HOST.system" --out-link "$SYSTEM"
sudo -H "${NIX%/*}/nix-env" --profile /nix/var/nix/profiles/system --set "$SYSTEM"
exec sudo -H "$SYSTEM/activate"
```

The flake is evaluated impurely, so the identity comes from the environment of the user
who ran the script rather than from a literal in the tree.

`darwin-rebuild` is not a dependency, so a fresh machine and an existing one take the same
path.

## Consequences

- The store path is built by, and owned by, the user who owns the clone.
- Only `nix-env --set` and `activate` run as root, behind one `sudo` prompt.
- No script may assume `darwin-rebuild` exists; anything that used to shell out to it has
  to call `rebuild.sh` instead.
- `--impure` is required, because evaluation reads `DOTFILES_USER`, `DOTFILES_HOME` and
  `DOTFILES_HOST` from the environment.
