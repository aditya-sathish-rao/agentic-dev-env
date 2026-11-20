#!/usr/bin/env bash
# The only writer of pins.nix and locks/. Run it by hand, outside any agent
# sandbox: a sandboxed agent that can rewrite its own pins defeats the point of
# pinning them.
#
#   ./nix/crew-tools/update.sh gh-axi 0.1.52   # one tool, explicit version
#   ./nix/crew-tools/update.sh treehouse       # latest, subject to the gates
#
# Gates, in order: the version must be at least 14 days old, the bytes are
# cross-checked against the publisher's own checksums, npm dependencies are
# signature audited, and the lock diff is printed for review. A hash proves the
# bytes did not change; it cannot prove who wrote them, which is what the gates
# are for.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$DIR/../.." && pwd)"
PINS="$DIR/pins.nix"
LOCKS="$DIR/locks"
MIN_AGE_DAYS=14

usage() {
  cat >&2 <<'EOF'
usage: update.sh <tool> [version]

  npm tools:     gh-axi chrome-devtools-axi tasks-axi quota-axi lavish-axi
                 chrome-devtools-mcp
  release tools: treehouse no-mistakes

With no version the latest published one is used, subject to the 14-day gate.
Review the printed lock diff afterwards, then run ./.githooks/check --all.
EOF
  exit 2
}

die() {
  echo "update: $*" >&2
  exit 1
}

[[ $# -ge 1 && $# -le 2 ]] || usage
tool="$1"
version="${2:-}"

# pins.nix is edited as text: one scalar (version, tarballHash, npmDepsHash) or
# one per-system hash. Both edits are scoped to this tool's block, so a bump
# cannot touch a neighbouring pin.
edit_pin() { # mode tool key value
  python3 - "$PINS" "$@" <<'PY'
import re, sys

path, mode, tool, *rest = sys.argv[1:]
text = open(path).read()
start = text.index(f"\n    {tool} = {{")
end = text.index("\n    };", start)
block = text[start:end]

if mode == "scalar":
    key, value = rest
    pattern = re.compile(r'(\n\s*' + re.escape(key) + r' = )"[^"]*"(;)')
    label = key
else:
    system, value = rest
    pattern = re.compile(r'("' + re.escape(system) + r'" = )"[^"]*"(;)')
    label = system

new_block, count = pattern.subn(lambda m: f'{m.group(1)}"{value}"{m.group(2)}', block, count=1)
if count != 1:
    sys.exit(f"edit_pin: {tool}: no {label} pin found in pins.nix")

open(path, "w").write(text[:start] + new_block + text[end:])
PY
}

is_release_tool() {
  sed -n "/^    $tool = {/,/^    };/p" "$PINS" | grep -q "^      hash = {"
}

iso_to_epoch() {
  python3 -c 'import sys,datetime; print(int(datetime.datetime.fromisoformat(sys.stdin.read().strip().replace("Z","+00:00")).timestamp()))'
}

age_gate() { # label published-epoch
  local label="$1" published="$2" age_days
  age_days=$((($(date +%s) - published) / 86400))
  if ((age_days < MIN_AGE_DAYS)); then
    die "$label is ${age_days}d old; the gate wants ${MIN_AGE_DAYS}d so a bad release has time to be pulled."
  fi
  echo "==> gate: $label is ${age_days}d old"
}

npm_published_epoch() { # version
  npm view "$tool" time --json --silent |
    python3 -c 'import json,sys,datetime; t=json.load(sys.stdin); v=sys.argv[1]
print(int(datetime.datetime.fromisoformat(t[v].replace("Z","+00:00")).timestamp()))' "$1"
}

update_npm() {
  local version="$1" work tgz hex sri out got published
  echo "==> $tool: resolve $version"

  published=$(npm_published_epoch "$version") || die "no publish time for $tool@$version"
  age_gate "$tool@$version" "$published"

  # Pin the bytes users get: the published tarball, not a repo build.
  work=$(mktemp -d)
  tgz="$work/pkg.tgz"
  curl -fsSL "https://registry.npmjs.org/$tool/-/$tool-$version.tgz" -o "$tgz"
  hex=$(nix hash file --type sha256 --base16 "$tgz")
  sri=$(nix hash convert --hash-algo sha256 --from base16 --to sri "$hex")

  # Generate the lock inside the unpacked tarball. Installing the package as a
  # *dependency* of a scratch project resolves only its production tree, and the
  # build then fails because the package's own dev tree is missing from the cache.
  tar -xzf "$tgz" -C "$work"
  (
    cd "$work/package"
    npm install --package-lock-only --ignore-scripts --no-audit --no-fund >/dev/null
    npm ci --omit=dev --ignore-scripts --no-audit --no-fund >/dev/null 2>&1 || true
    npm audit signatures 2>&1 | tail -3
  )
  mkdir -p "$LOCKS/$tool"
  cp "$work/package/package-lock.json" "$LOCKS/$tool/package-lock.json"
  rm -rf "$work"

  echo "==> $tool: lock diff (review this, not just the version)"
  git -C "$REPO" --no-pager diff --stat -- "nix/crew-tools/locks/$tool" || true
  git -C "$REPO" --no-pager diff -- "nix/crew-tools/locks/$tool" | head -80 || true

  # npmDepsHash is only knowable by making Nix report it once.
  edit_pin scalar "$tool" version "$version"
  edit_pin scalar "$tool" tarballHash "$sri"
  edit_pin scalar "$tool" npmDepsHash "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
  out=$(cd "$REPO" && nix build --impure --keep-going --no-link ".#crew-tools" 2>&1 || true)
  got=$(printf '%s\n' "$out" | awk -v t="$tool" '
    /hash mismatch in fixed-output derivation/ { want = index($0, "-" t "-") > 0; next }
    want && /got:/ { print $2; exit }')
  if [[ -z "$got" ]]; then
    printf '%s\n' "$out" | tail -20 >&2
    die "$tool: Nix reported no npmDepsHash; pins left with a placeholder hash"
  fi
  edit_pin scalar "$tool" npmDepsHash "$got"
  echo "==> $tool: $version pinned"
}

update_release() {
  local version="$1" work checksums asset hex sri published
  echo "==> $tool: resolve v$version"

  published=$(gh release view "v$version" --repo "kunchenguid/$tool" --json publishedAt -q .publishedAt | iso_to_epoch)
  age_gate "$tool v$version" "$published"

  work=$(mktemp -d)
  gh release download "v$version" --repo "kunchenguid/$tool" --pattern checksums.txt --dir "$work" >/dev/null
  checksums="$work/checksums.txt"

  for system in aarch64-darwin x86_64-darwin aarch64-linux x86_64-linux; do
    case "$system" in *darwin*) os=darwin ;; *) os=linux ;; esac
    case "$system" in aarch64*) arch=arm64 ;; *) arch=amd64 ;; esac
    asset="$tool-v$version-$os-$arch.tar.gz"
    hex=$(awk -v a="$asset" '$2 == a || $2 == "*" a { print $1 }' "$checksums")
    [[ -n "$hex" ]] || die "$tool: $asset is not in checksums.txt"
    sri=$(nix hash convert --hash-algo sha256 --from base16 --to sri "$hex")
    edit_pin hash "$tool" "$system" "$sri"
  done
  rm -rf "$work"

  edit_pin scalar "$tool" version "$version"
  echo "==> $tool: $version pinned from the publisher's checksums"
}

if [[ -z "$version" ]]; then
  if is_release_tool; then
    version=$(gh release view --repo "kunchenguid/$tool" --json tagName -q .tagName | sed 's/^v//')
  else
    version=$(npm view "$tool" version --silent)
  fi
fi

if is_release_tool; then
  update_release "$version"
else
  update_npm "$version"
fi

echo "==> build: nix build --impure .#crew-tools"
(cd "$REPO" && nix build --impure ".#crew-tools" --no-link)
echo "==> done. Review the lock diff, then run ./.githooks/check --all"
