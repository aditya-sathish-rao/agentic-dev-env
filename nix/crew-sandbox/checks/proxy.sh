#!/usr/bin/env bash
# What the guest may and may not reach once a proxy session exists. Runs inside the
# guest as `agent`, so it proves the boundary from the side that could abuse it.
set -uo pipefail

fail=0

pass() { printf 'PASS  %s\n' "$1"; }
flunk() {
  printf 'FAIL  %s\n' "$1"
  fail=1
}

host=$(ip -4 route show default | awk '{print $3; exit}')
proxy="http://${host}:3128"

if curl -fsS -m 20 -x "$proxy" https://cache.nixos.org/nix-cache-info | grep -q '^StoreDir:'; then
  pass "an allowlisted host answers through the proxy"
else
  flunk "an allowlisted host answers through the proxy"
fi

if curl -fsS -m 10 -o /dev/null -x "$proxy" https://example.com 2>/dev/null; then
  flunk "a host off the allowlist is refused over https"
else
  pass "a host off the allowlist is refused over https"
fi

code=$(curl -sS -m 10 -o /dev/null -w '%{http_code}' -x "$proxy" http://example.com 2>/dev/null || echo 000)
if [[ "$code" == 403 ]]; then
  pass "a host off the allowlist is refused over http"
else
  flunk "a host off the allowlist is refused over http (got ${code})"
fi

if curl -fsS -m 10 -o /dev/null -x "$proxy" https://github.com:22 2>/dev/null; then
  flunk "a non-web port is refused even on an allowlisted host"
else
  pass "a non-web port is refused even on an allowlisted host"
fi

if curl -fsS -m 5 -o /dev/null https://cache.nixos.org/nix-cache-info 2>/dev/null; then
  flunk "the guest still cannot reach the internet without the proxy"
else
  pass "the guest still cannot reach the internet without the proxy"
fi

exit "$fail"
