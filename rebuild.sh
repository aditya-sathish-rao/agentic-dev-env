#!/usr/bin/env bash
# One entry point: provision a fresh macOS machine or re-apply changes. Safe to re-run.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

USER_NAME="${DOTFILES_USER:-$(id -un)}"
HOME_DIR="${DOTFILES_HOME:-$HOME}"
HOST="${DOTFILES_HOST:-$USER_NAME}"
# Impure evaluation reads these, so the flake follows whoever is logged in.
export DOTFILES_USER="$USER_NAME"
export DOTFILES_HOME="$HOME_DIR"
export DOTFILES_HOST="$HOST"

# First, before any git call: on a fresh Mac /usr/bin/git is a stub that prompts
# for the Xcode tools, and that prompt aborts the script under set -e.
if ! xcode-select -p >/dev/null 2>&1; then
  echo "==> tools: Xcode command line tools missing - the installer was started." >&2
  echo "    Re-run ./rebuild.sh when it finishes." >&2
  xcode-select --install || true
  exit 1
fi

echo "==> link: $HOME_DIR/.dotfiles -> $DIR"
if [[ -e "$HOME_DIR/.dotfiles" && ! -L "$HOME_DIR/.dotfiles" ]]; then
  echo "==> link: $HOME_DIR/.dotfiles exists and is not a symlink; move it aside first." >&2
  exit 1
fi
ln -sfn "$DIR" "$HOME_DIR/.dotfiles"

git -C "$DIR" config core.hooksPath .githooks

NIX=/nix/var/nix/profiles/default/bin/nix
echo "==> nix: $NIX"
if [[ ! -x "$NIX" ]]; then
  echo "    installing Determinate Nix..."
  curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix |
    sh -s -- install --determinate
  if [[ ! -x "$NIX" ]]; then
    echo "==> nix: install did not complete; re-run ./rebuild.sh." >&2
    exit 1
  fi
fi

# Build as the user who owns the clone, then escalate only for activation. Root
# cannot evaluate a git flake owned by another user (libgit2: "repository path is
# not owned by current user"), which is exactly what a fresh clone is.
echo "==> build: $DIR#darwinConfigurations.$HOST.system"
SYSTEM="$HOME_DIR/.dotfiles-system"
"$NIX" build --impure "$DIR#darwinConfigurations.$HOST.system" --out-link "$SYSTEM"

echo "==> activate: $SYSTEM"
sudo -H "${NIX%/*}/nix-env" --profile /nix/var/nix/profiles/system --set "$SYSTEM"
exec sudo -H "$SYSTEM/activate"
