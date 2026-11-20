#!/usr/bin/env bash
# Phase 2: the guest can actually run the fleet's tools. Runs as `agent` in a
# login shell, because that is the shell an operator and an ssh session get.
set -uo pipefail
cd /tmp || exit 1

fail=0
pass() { printf 'PASS  %s\n' "$1"; }
flunk() {
  printf 'FAIL  %s\n' "$1"
  fail=1
}

if [[ -n "${https_proxy:-}" ]]; then
  pass "a login shell knows the proxy (${https_proxy})"
else
  flunk "a login shell knows the proxy"
fi

# command -v reports the profile symlink; what matters is where it lands. A tool
# from Ubuntu or /usr/local would resolve outside the store and fail here.
from_store() {
  local path
  path=$(command -v "$1" 2>/dev/null) || return 1
  [[ -n "$path" ]] && [[ "$(readlink -f "$path")" == /nix/store/* ]]
}

if from_store nix; then
  pass "nix resolves under /nix/store"
else
  flunk "nix resolves under /nix/store (got '$(readlink -f "$(command -v nix 2>/dev/null)" 2>/dev/null || echo nothing)')"
fi

if [[ "$(nix-store --verify 2>&1 | grep -c 'error')" -eq 0 ]]; then
  pass "the Nix store verifies clean"
else
  flunk "the Nix store verifies clean"
fi

installed=$(pi --version 2>/dev/null || true)
if [[ -n "${CREW_EXPECTED_PI:-}" && "$installed" == "$CREW_EXPECTED_PI" ]]; then
  pass "pi matches the pinned harness ($installed)"
else
  flunk "pi matches the pinned harness (want '${CREW_EXPECTED_PI:-unset}', got '${installed:-none}')"
fi

for tool in treehouse no-mistakes gh-axi tasks-axi quota-axi lavish-axi chrome-devtools-axi chrome-devtools-mcp; do
  if from_store "$tool"; then
    pass "$tool resolves under /nix/store"
  else
    flunk "$tool resolves under /nix/store"
  fi
done

exit "$fail"
