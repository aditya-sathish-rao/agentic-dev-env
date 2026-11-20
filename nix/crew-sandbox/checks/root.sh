#!/usr/bin/env bash
# The other half of the phase 1 gate: properties only root can inspect. Runs
# inside the guest as the administration account.
set -uo pipefail

fail=0

pass() { printf 'PASS  %s\n' "$1"; }
flunk() {
  printf 'FAIL  %s\n' "$1"
  fail=1
}

if [[ "$(id -un)" == root ]]; then
  pass "inspecting as root"
else
  flunk "inspecting as root (got $(id -un))"
fi

drops=$(nft list ruleset | grep -c 'policy drop' || true)
if [[ "$drops" -ge 2 ]]; then
  pass "input and output both default to drop"
else
  flunk "input and output both default to drop (found $drops)"
fi

if nft list ruleset | grep -q 'dport 3128 accept'; then
  pass "the proxy port is the one allowed destination"
else
  flunk "the proxy port is the one allowed destination"
fi

owner=$(stat -c '%U:%a' /etc/nftables.conf)
if [[ "$owner" == root:644 ]]; then
  pass "the ruleset is owned by root ($owner)"
else
  flunk "the ruleset is owned by root (got $owner)"
fi

if id -nG agent | tr ' ' '\n' | grep -qxE 'sudo|admin|wheel'; then
  flunk "agent is in no privileged group"
else
  pass "agent is in no privileged group"
fi

if grep -rqs '^[^#]*agent' /etc/sudoers /etc/sudoers.d/; then
  flunk "agent appears in no sudoers rule"
else
  pass "agent appears in no sudoers rule"
fi

if [[ -e /etc/crew-provisioned ]]; then
  pass "bootstrap is marked complete, so a reboot will not reopen egress"
else
  flunk "bootstrap is marked complete, so a reboot will not reopen egress"
fi

if ss -Hlnt 'sport = :22' | grep -q .; then
  pass "the guest accepts ssh from the host"
else
  flunk "the guest accepts ssh from the host"
fi

exit "$fail"
