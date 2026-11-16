#!/usr/bin/env bash
# Clone -> fully provisioned dev env on a fresh macOS box. Safe to re-run.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
HOST="${DOTFILES_HOST:-m2-pro}"
# home.nix reads its files through this link, so the repo can be cloned anywhere.
ln -sfn "$DIR" "$HOME/.dotfiles"

if ! xcode-select -p >/dev/null 2>&1; then
  echo "Xcode command line tools are missing - starting the installer." >&2
  echo "Re-run this script once it finishes." >&2
  xcode-select --install || true
  exit 1
fi

NIX=/nix/var/nix/profiles/default/bin/nix
if [ ! -x "$NIX" ]; then
  echo "Installing Determinate Nix..." >&2
  curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix \
    | sh -s -- install --determinate
fi

REBUILD=/run/current-system/sw/bin/darwin-rebuild
if [ ! -x "$REBUILD" ]; then
  # First switch: darwin-rebuild isn't installed yet, so build the pinned
  # system closure from flake.lock and run the copy inside it.
  "$NIX" build "$HOME/.dotfiles#darwinConfigurations.$HOST.system" \
    --out-link "$HOME/.dotfiles-system"
  REBUILD="$HOME/.dotfiles-system/sw/bin/darwin-rebuild"
  PATH="/nix/var/nix/profiles/default/bin:$PATH"
fi

exec sudo -H env PATH="$PATH" "$REBUILD" switch --flake "$HOME/.dotfiles#$HOST"
