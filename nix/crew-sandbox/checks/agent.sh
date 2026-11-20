#!/usr/bin/env bash
# What a crewmate must not be able to do. Runs inside the guest as `agent`, the
# account the fleet uses. Every check is a capability, not a configuration: it
# would still hold if someone re-enabled sudo or reopened egress.
set -uo pipefail

fail=0

pass() { printf 'PASS  %s\n' "$1"; }
flunk() {
  printf 'FAIL  %s\n' "$1"
  fail=1
}

# expect_fail <label> <command...>
expect_fail() {
  local label=$1
  shift
  if "$@" >/dev/null 2>&1; then
    flunk "$label"
  else
    pass "$label"
  fi
}

if [[ "$(id -un)" == agent ]]; then
  pass "running as agent"
else
  flunk "running as agent (got $(id -un))"
fi

if [[ -e /Users ]]; then
  flunk "the host filesystem is absent"
else
  pass "the host filesystem is absent"
fi

# A virtiofs or 9p mount is a host directory with the host's permissions on it.
if mount | grep -Eq '\b(9p|virtiofs|fuse\.)'; then
  flunk "no host directory is mounted ($(mount | grep -Eo '\b(9p|virtiofs|fuse\.[a-z]+)' | sort -u | tr '\n' ' '))"
else
  pass "no host directory is mounted"
fi

expect_fail "egress to an arbitrary host is blocked" curl -sS -m 5 -o /dev/null https://example.com
expect_fail "a query to an arbitrary resolver is blocked" dig +time=2 +tries=1 @1.1.1.1 example.com
expect_fail "the system resolver cannot resolve" getent hosts example.com
expect_fail "the host is unreachable on any port but the proxy" curl -sS -m 3 -o /dev/null \
  "http://$(ip -4 route show default | awk '{print $3; exit}'):80"
expect_fail "sudo is unavailable" sudo -n true
expect_fail "the firewall cannot be flushed" nft flush ruleset
expect_fail "the firewall ruleset cannot be read" nft list ruleset
expect_fail "the firewall configuration is not writable" test -w /etc/nftables.conf

exit "$fail"
