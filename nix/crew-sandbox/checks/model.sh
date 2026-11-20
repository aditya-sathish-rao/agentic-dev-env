#!/usr/bin/env bash
# Phase 3a-2: the guest reaches the model only through the host gateway, and the
# real key exists only in that proxy's process. Runs inside the guest as `agent`.
set -uo pipefail

fail=0

pass() { printf 'PASS  %s\n' "$1"; }
flunk() {
  printf 'FAIL  %s\n' "$1"
  fail=1
}

gateway="http://host.lima.internal:3128/model"
token_file=/etc/crew-model-token
models=/home/agent/.pi/agent/models.json
settings=/home/agent/.pi/agent/settings.json

if [[ -s "$token_file" ]]; then
  token=$(cat "$token_file")
  pass "the guest holds a model gateway token"
else
  token=""
  flunk "the guest holds a model gateway token"
fi

if [[ -n "$token" && "$token" != sk-* ]]; then
  pass "the gateway token is not a model key"
else
  flunk "the gateway token is not a model key"
fi

# The host passes the fingerprint, never the key. A key copied under another
# variable name still matches, so this proves the value is absent, not just its
# usual name.
if [[ -n "${CREW_REAL_KEY_SHA256:-}" ]]; then
  leaked=0
  while IFS= read -r line; do
    value=${line#*=}
    [[ -n "$value" ]] || continue
    hash=$(printf '%s' "$value" | sha256sum | awk '{print $1}')
    if [[ "$hash" == "$CREW_REAL_KEY_SHA256" ]]; then
      leaked=1
      break
    fi
  done < <(env)
  if [[ "$leaked" -eq 0 ]]; then
    pass "no environment value is the model key"
  else
    flunk "no environment value is the model key"
  fi
else
  flunk "the gate was given the model key's fingerprint"
fi

if [[ -f "$models" ]] && grep -q 'host.lima.internal:3128/model' "$models"; then
  pass "pi's provider points at the gateway"
else
  flunk "pi's provider points at the gateway"
fi

if [[ -f "$models" ]] && grep -q '!cat /etc/crew-model-token' "$models"; then
  pass "pi reads its gateway token from the guest file"
else
  flunk "pi reads its gateway token from the guest file"
fi

if [[ -f "$settings" ]] && grep -q '"defaultProvider": "deepseek"' "$settings"; then
  pass "pi defaults to the proxied provider"
else
  flunk "pi defaults to the proxied provider"
fi

code=$(curl --noproxy '*' -sS -m 10 -o /dev/null -w '%{http_code}' "$gateway/models" 2>/dev/null || echo 000)
if [[ "$code" == 401 ]]; then
  pass "the gateway refuses a request without a token"
else
  flunk "the gateway refuses a request without a token (got ${code})"
fi

code=$(curl --noproxy '*' -sS -m 10 -o /dev/null -w '%{http_code}' \
  -H 'Authorization: Bearer not-the-guest' "$gateway/models" 2>/dev/null || echo 000)
if [[ "$code" == 401 ]]; then
  pass "the gateway refuses a request with the wrong token"
else
  flunk "the gateway refuses a request with the wrong token (got ${code})"
fi

body=$(mktemp)
code=$(curl --noproxy '*' -sS -m 30 -o "$body" -w '%{http_code}' \
  -H "Authorization: Bearer $token" "$gateway/models" 2>/dev/null || echo 000)
if [[ "$code" == 200 ]] && grep -q '"data"' "$body"; then
  pass "the gateway reaches the model API with the host's key"
else
  flunk "the gateway reaches the model API with the host's key (got ${code})"
fi
rm -f "$body"

code=$(curl --noproxy '*' -sS -m 10 -o /dev/null -w '%{http_code}' \
  -H "Authorization: Bearer $token" "$gateway/not-a-model-route" 2>/dev/null || echo 000)
if [[ "$code" == 404 ]]; then
  pass "the gateway refuses paths outside the model API"
else
  flunk "the gateway refuses paths outside the model API (got ${code})"
fi

if curl -sS -m 5 -o /dev/null https://api.deepseek.com/models 2>/dev/null; then
  flunk "the model API is unreachable without the gateway"
else
  pass "the model API is unreachable without the gateway"
fi

if timeout 30 pi --list-models 2>/dev/null | grep -q 'deepseek-flash'; then
  pass "pi lists the proxied deepseek model"
else
  flunk "pi lists the proxied deepseek model"
fi

exit "$fail"
