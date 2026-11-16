#!/usr/bin/env bash
# Clone -> fully provisioned dev env on a fresh macOS box. Safe to re-run.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
HOST="${DOTFILES_HOST:-m2-pro}"
# home.nix reads its files through this link, so the repo can be cloned anywhere.
ln -sfn "$DIR" "$HOME/.dotfiles"
# Tracked hooks run formatters and linters before every commit.
git -C "$DIR" config core.hooksPath .githooks

if ! xcode-select -p >/dev/null 2>&1; then
  echo "Xcode command line tools are missing - starting the installer." >&2
  echo "Re-run this script once it finishes." >&2
  xcode-select --install || true
  exit 1
fi

NIX=/nix/var/nix/profiles/default/bin/nix
if [ ! -x "$NIX" ]; then
  echo "Installing Determinate Nix..." >&2
  curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix |
    sh -s -- install --determinate
fi

# Build as the user who owns the clone, then escalate only for activation. Root
# cannot evaluate a git flake owned by another user (libgit2: "repository path is
# not owned by current user"), which is exactly what a fresh clone is.
SYSTEM="$HOME/.dotfiles-system"
"$NIX" build "$DIR#darwinConfigurations.$HOST.system" --out-link "$SYSTEM"
sudo -H "${NIX%/*}/nix-env" --profile /nix/var/nix/profiles/system --set "$SYSTEM"
exec sudo -H "$SYSTEM/activate"
