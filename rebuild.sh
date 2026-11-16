#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ln -sfn "$DIR" ~/.dotfiles
DARWIN_REBUILD=/run/current-system/sw/bin/darwin-rebuild
# Nothing is installed yet on a fresh machine - bootstrap first.
[ -x "$DARWIN_REBUILD" ] || exec "$DIR/bootstrap.sh"

# Build as the user who owns the clone, then escalate only for activation. Root
# cannot evaluate a git flake owned by another user (libgit2: "repository path is
# not owned by current user").
NIX=/nix/var/nix/profiles/default/bin/nix
SYSTEM="$HOME/.dotfiles-system"
"$NIX" build "$DIR#darwinConfigurations.m2-pro.system" --out-link "$SYSTEM"
sudo -H "${NIX%/*}/nix-env" --profile /nix/var/nix/profiles/system --set "$SYSTEM"
exec sudo -H "$SYSTEM/activate"
