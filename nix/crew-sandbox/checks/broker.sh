#!/usr/bin/env bash
# Phase 3b: the broker mints a token for one repository, GitHub refuses it
# elsewhere, and a revoke makes it unusable. Runs on the host, not in the guest.
set -uo pipefail

fail=0

pass() { printf 'PASS  %s\n' "$1"; }
flunk() {
  printf 'FAIL  %s\n' "$1"
  fail=1
}

base="http://127.0.0.1:${CREW_BROKER_PORT:-3139}"
task="gate-$$"
token=""

# shellcheck disable=SC2329  # invoked by the EXIT trap below
cleanup() {
  if [[ -n "$token" ]]; then
    curl -sS -m 10 -o /dev/null -X DELETE "$base/token/$task" 2>/dev/null || true
  fi
}
trap cleanup EXIT

if curl -fsS -m 5 "$base/health" >/dev/null 2>&1; then
  pass "the broker answers on its health route"
else
  flunk "the broker answers on its health route"
  exit 1
fi

repos=$(curl -fsS -m 5 "$base/health" | jq -r '.repos[]?' | head -1)
if [[ -n "$repos" ]]; then
  pass "the broker names an allowlisted repository ($repos)"
else
  flunk "the broker names an allowlisted repository"
  exit 1
fi

code=$(curl -sS -m 10 -o /dev/null -w '%{http_code}' -X POST -H 'content-type: application/json' \
  -d "{\"task\":\"$task\",\"repo\":\"not-in-allowlist\"}" "$base/token" 2>/dev/null || echo 000)
if [[ "$code" == 403 ]]; then
  pass "a repository outside the allowlist is refused before minting"
else
  flunk "a repository outside the allowlist is refused before minting (got ${code})"
fi

mint=$(curl -sS -m 20 -X POST -H 'content-type: application/json' \
  -d "{\"task\":\"$task\",\"repo\":\"$repos\"}" "$base/token" 2>/dev/null)
token=$(printf '%s' "$mint" | jq -r '.token // empty')
if [[ -n "$token" ]]; then
  pass "the broker mints a token for $repos"
else
  flunk "the broker mints a token for $repos"
  exit 1
fi

full=$(curl -sS -m 20 -H "Authorization: token $token" \
  https://api.github.com/installation/repositories 2>/dev/null | jq -r '.repositories[0].full_name // empty')
owner=${full%%/*}
if [[ -n "$full" ]]; then
  pass "the token sees its own repository ($full)"
else
  flunk "the token sees its own repository"
fi

code=$(curl -sS -m 20 -o /dev/null -w '%{http_code}' -H "Authorization: token $token" \
  "https://api.github.com/repos/${full}" 2>/dev/null || echo 000)
if [[ "$code" == 200 ]]; then
  pass "the token reads its own repository"
else
  flunk "the token reads its own repository (got ${code})"
fi

# GitHub validates a request body before it authorizes, so an invalid body says
# nothing about permission. A real file is the honest write probe: create one and
# delete it, in the token's own repository and in another one.
probe_path="crew-gate-probe-$$-$(date +%s).txt"
probe_body=$(printf '{"message":"crew gate probe","content":"%s"}' \
  "$(printf 'crew gate %s' "$task" | base64 | tr -d '\n')")
own_body=$(mktemp)

code=$(curl -sS -m 30 -o "$own_body" -w '%{http_code}' -X PUT -H "Authorization: token $token" \
  -H 'content-type: application/json' -d "$probe_body" \
  "https://api.github.com/repos/${full}/contents/${probe_path}" 2>/dev/null || echo 000)
if [[ "$code" == 200 || "$code" == 201 ]]; then
  pass "the token may write its own repository"
  sha=$(jq -r '.content.sha // empty' "$own_body")
  if [[ -n "$sha" ]]; then
    cleanup_body=$(printf '{"message":"crew gate probe cleanup","sha":"%s"}' "$sha")
    code=$(curl -sS -m 30 -o /dev/null -w '%{http_code}' -X DELETE \
      -H "Authorization: token $token" -H 'content-type: application/json' -d "$cleanup_body" \
      "https://api.github.com/repos/${full}/contents/${probe_path}" 2>/dev/null || echo 000)
    if [[ "$code" != 200 ]]; then
      flunk "the gate removes its probe file from its own repository (got ${code})"
    fi
  else
    flunk "the gate reads the sha of its own probe file"
  fi
else
  flunk "the token may write its own repository (got ${code})"
fi
rm -f "$own_body"

other=${CREW_BROKER_OTHER_REPO:-${owner}/agentic-dev-env}
if [[ "$other" == "$full" ]]; then
  flunk "the gate has a different repository to test"
else
  other_body=$(mktemp)
  code=$(curl -sS -m 30 -o "$other_body" -w '%{http_code}' -X PUT -H "Authorization: token $token" \
    -H 'content-type: application/json' -d "$probe_body" \
    "https://api.github.com/repos/${other}/contents/${probe_path}" 2>/dev/null || echo 000)
  if [[ "$code" == 403 || "$code" == 404 || "$code" == 401 ]]; then
    pass "GitHub refuses the token a write on another repository (${code})"
  elif [[ "$code" == 200 || "$code" == 201 ]]; then
    flunk "GitHub refuses the token a write on another repository (it created a file)"
    sha=$(jq -r '.content.sha // empty' "$other_body")
    if [[ -n "$sha" ]]; then
      cleanup_body=$(printf '{"message":"crew gate probe cleanup","sha":"%s"}' "$sha")
      curl -sS -m 30 -o /dev/null -X DELETE -H "Authorization: token $token" \
        -H 'content-type: application/json' -d "$cleanup_body" \
        "https://api.github.com/repos/${other}/contents/${probe_path}" 2>/dev/null || true
    fi
  else
    flunk "GitHub refuses the token a write on another repository (got ${code})"
  fi
  rm -f "$other_body"
fi

code=$(curl -sS -m 20 -o /dev/null -w '%{http_code}' -X DELETE "$base/token/$task" 2>/dev/null || echo 000)
if [[ "$code" == 204 ]]; then
  pass "the broker revokes the token"
else
  flunk "the broker revokes the token (got ${code})"
fi

code=$(curl -sS -m 20 -o /dev/null -w '%{http_code}' -H "Authorization: token $token" \
  "https://api.github.com/repos/${full}" 2>/dev/null || echo 000)
if [[ "$code" == 401 ]]; then
  pass "GitHub refuses the revoked token"
else
  flunk "GitHub refuses the revoked token (got ${code})"
fi
token=""

exit "$fail"
