#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ln -sfn "$DIR" ~/.dotfiles
DARWIN_REBUILD=/run/current-system/sw/bin/darwin-rebuild
# Nothing is installed yet on a fresh machine - bootstrap first.
[ -x "$DARWIN_REBUILD" ] || exec "$DIR/bootstrap.sh"

exec sudo -H "$DARWIN_REBUILD" switch --flake "$HOME/.dotfiles#m2-pro"
