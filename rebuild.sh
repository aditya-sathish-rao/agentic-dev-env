#!/usr/bin/env bash
# One entry point: provision a fresh macOS machine or re-apply changes. Safe to re-run.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

USER_NAME="${AGENTIC_DEV_ENV_USER:-$(id -un)}"
HOME_DIR="${AGENTIC_DEV_ENV_HOME:-$HOME}"
HOST="${AGENTIC_DEV_ENV_HOST:-$USER_NAME}"
# Impure evaluation reads these, so the flake follows whoever is logged in.
export AGENTIC_DEV_ENV_USER="$USER_NAME"
export AGENTIC_DEV_ENV_HOME="$HOME_DIR"
export AGENTIC_DEV_ENV_HOST="$HOST"

# First, before any git call: on a fresh Mac /usr/bin/git is a stub that prompts
# for the Xcode tools, and that prompt aborts the script under set -e.
if ! xcode-select -p >/dev/null 2>&1; then
  echo "==> tools: Xcode command line tools missing - the installer was started." >&2
  echo "    Re-run ./rebuild.sh when it finishes." >&2
  xcode-select --install || true
  exit 1
fi

echo "==> link: $HOME_DIR/.agentic-dev-env -> $DIR"
if [[ -e "$HOME_DIR/.agentic-dev-env" && ! -L "$HOME_DIR/.agentic-dev-env" ]]; then
  echo "==> link: $HOME_DIR/.agentic-dev-env exists and is not a symlink; move it aside first." >&2
  exit 1
fi
ln -sfn "$DIR" "$HOME_DIR/.agentic-dev-env"

git -C "$DIR" config core.hooksPath .githooks

# firstmate is the one mutable tree: it fast-forwards itself on /updatefirstmate.
# Establish it here, before activation links into its config/, so a fresh machine
# never needs a manual clone first. HTTPS needs no SSH key or vault on a new Mac.
FIRSTMATE="$HOME_DIR/firstmate"
FIRSTMATE_URL="https://github.com/aditya-sathish-rao/firstmate"
FIRSTMATE_UPSTREAM="https://github.com/kunchenguid/firstmate"
EXPECTED_COMMIT="$(<"$DIR/home/firstmate/expected-commit")"
stub_backup=""
if [[ -d "$FIRSTMATE" && ! -d "$FIRSTMATE/.git" ]]; then
  # A previous activation can leave a config/ stub. Only a stub of links is safe
  # to move aside; any real file means a human owns this directory.
  unexpected=$(find "$FIRSTMATE" -type f -print -quit)
  if [[ -n "$unexpected" ]]; then
    echo "==> firstmate: $FIRSTMATE is not a git checkout and contains $unexpected; move it aside first." >&2
    exit 1
  fi
  stub_backup="${FIRSTMATE}.hm-stub.$(date +%s)"
  mv "$FIRSTMATE" "$stub_backup"
  echo "==> firstmate: moved the activation stub to $stub_backup"
fi
if [[ ! -d "$FIRSTMATE/.git" ]]; then
  echo "==> firstmate: clone $FIRSTMATE_URL -> $FIRSTMATE"
  git clone "$FIRSTMATE_URL" "$FIRSTMATE"
  git -C "$FIRSTMATE" remote add upstream "$FIRSTMATE_UPSTREAM"
  # The pin has to sit on the fork's default branch. Resetting the branch to a
  # commit off it would leave the clone unable to fast-forward on /updatefirstmate,
  # which is the one workflow this clone exists for.
  default_ref=$(git -C "$FIRSTMATE" symbolic-ref --quiet --short refs/remotes/origin/HEAD || echo origin/main)
  if ! git -C "$FIRSTMATE" merge-base --is-ancestor "$EXPECTED_COMMIT" "$default_ref"; then
    echo "==> firstmate: $EXPECTED_COMMIT is not on $default_ref; update home/firstmate/expected-commit." >&2
    exit 1
  fi
  git -C "$FIRSTMATE" reset --hard "$EXPECTED_COMMIT"
  if [[ -n "$stub_backup" ]]; then
    rm -rf "$stub_backup"
    echo "==> firstmate: removed the stub backup after a clean clone"
  fi
fi
actual=$(git -C "$FIRSTMATE" rev-parse HEAD)
if [[ "$actual" == "$EXPECTED_COMMIT" ]]; then
  echo "==> firstmate: HEAD == expected $EXPECTED_COMMIT"
else
  echo "==> firstmate: HEAD $actual differs from expected $EXPECTED_COMMIT (reported only; self-update owns this tree)."
fi

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
SYSTEM="$HOME_DIR/.agentic-dev-env-system"
"$NIX" build --impure "$DIR#darwinConfigurations.$HOST.system" --out-link "$SYSTEM"

echo "==> activate: $SYSTEM"
sudo -H "${NIX%/*}/nix-env" --profile /nix/var/nix/profiles/system --set "$SYSTEM"
exec sudo -H "$SYSTEM/activate"
