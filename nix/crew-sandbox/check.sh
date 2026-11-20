# shellcheck shell=bash
# Phase gates for the crew VM. Each phase is one command that proves the phase's
# boundary still holds on the guest as it is right now, not as it was built.
set -euo pipefail

name=crew
# Injected by nix/crew-sandbox/default.nix; defaults keep this file standalone.
agent_checks=${agent_checks:-}
root_checks=${root_checks:-}
proxy_check=${proxy_check:-}
model_check=${model_check:-}
toolchain_check=${toolchain_check:-}
expected_pi=${expected_pi:-}
proxy_script=${proxy_script:-}
egress_allow=${egress_allow:-}
broker_check=${broker_check:-}
broker_script=${broker_script:-}
broker_app_id=${broker_app_id:-}
broker_repos_file=${broker_repos_file:-}

usage() {
  echo "usage: crew-sandbox check [box|proxy|model|toolchain|broker]"
}

phase=${1:-box}
case "$phase" in
  box | proxy | model | toolchain | broker) ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    echo "crew-sandbox check: no gate for '$phase'" >&2
    usage >&2
    exit 2
    ;;
esac

status=0
service_pid=""
key_hash_file=""

# shellcheck disable=SC2329  # invoked by the EXIT trap below
cleanup() {
  if [[ -n "$service_pid" ]]; then kill "$service_pid" 2>/dev/null || true; fi
  if [[ -n "$key_hash_file" ]]; then rm -f "$key_hash_file"; fi
  if [[ "$phase" != broker ]]; then
    limactl shell "$name" -- sudo -n rm -f /tmp/crew-agent-checks.sh /tmp/crew-root-checks.sh \
      /tmp/crew-proxy-checks.sh /tmp/crew-model-checks.sh /tmp/crew-toolchain-checks.sh \
      >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

# The broker is a host service, so its gate does not need the guest to be running.
if [[ "$phase" == broker ]]; then
  if ! command -v av >/dev/null 2>&1; then
    echo "broker: av is not on PATH; it is what injects GITHUB_APP_PRIVATE_KEY" >&2
    exit 1
  fi
  broker_port=${CREW_BROKER_PORT:-3139}
  if lsof -nP -iTCP:"$broker_port" -sTCP:LISTEN >/dev/null 2>&1; then
    echo "broker: port ${broker_port} is already in use; stop that broker and rerun." >&2
    exit 1
  fi
  echo "broker: starting the broker with the vault key for the duration of this gate"
  echo "broker: approve the vault prompt if one appears"
  av inject +GITHUB_APP_PRIVATE_KEY -- env CREW_APP_ID="$broker_app_id" \
    CREW_BROKER_REPOS_FILE="$broker_repos_file" CREW_BROKER_PORT="$broker_port" \
    node "$broker_script" &
  service_pid=$!
  for _ in {1..600}; do
    if curl -fsS -m 1 "http://127.0.0.1:${broker_port}/health" >/dev/null 2>&1; then
      break
    fi
    if ! kill -0 "$service_pid" 2>/dev/null; then
      break
    fi
    sleep 0.2
  done
  if ! curl -fsS -m 1 "http://127.0.0.1:${broker_port}/health" >/dev/null 2>&1; then
    echo "broker: the broker did not start." >&2
    exit 1
  fi
  CREW_BROKER_PORT="$broker_port" bash "$broker_check" || status=1
  if [[ "$status" -eq 0 ]]; then
    printf '\nbroker: pass\n'
  else
    printf '\nbroker: fail\n' >&2
  fi
  exit "$status"
fi

if [[ "$(limactl list "$name" --format '{{.Status}}')" != Running ]]; then
  echo "crew-sandbox check: the crew VM is not running; start it with 'crew-sandbox up'." >&2
  exit 1
fi

# The scripts are copied in rather than piped: the halves need different users, and
# a pty is the wrong place to carry a script.
limactl copy "$agent_checks" "$name:/tmp/crew-agent-checks.sh"
limactl copy "$root_checks" "$name:/tmp/crew-root-checks.sh"

if [[ "$phase" == proxy ]]; then
  if lsof -nP -iTCP:3128 -sTCP:LISTEN >/dev/null 2>&1; then
    echo "proxy: already listening on 127.0.0.1:3128"
  else
    echo "proxy: starting one for the duration of this gate"
    node "$proxy_script" --listen 3128 --allow "$egress_allow" &
    service_pid=$!
    for _ in {1..50}; do
      if curl -s -o /dev/null -m 1 -x http://127.0.0.1:3128 https://cache.nixos.org/nix-cache-info; then
        break
      fi
      sleep 0.2
    done
  fi
fi

if [[ "$phase" == model ]]; then
  if ! command -v av >/dev/null 2>&1; then
    echo "model: av is not on PATH; it is what injects DEEPSEEK_API_KEY" >&2
    exit 1
  fi
  token=$(limactl shell "$name" -- sudo -n cat /etc/crew-model-token 2>/dev/null | tr -d '[:space:]' || true)
  if [[ -z "$token" ]]; then
    echo "model: /etc/crew-model-token is missing; re-create the VM from the current lima.yaml." >&2
    exit 1
  fi
  if lsof -nP -iTCP:3128 -sTCP:LISTEN >/dev/null 2>&1; then
    echo "model: port 3128 is already in use; stop that proxy so this gate controls the key." >&2
    exit 1
  fi
  key_hash_file=$(mktemp)
  echo "model: starting the proxy with the vault key for the duration of this gate"
  echo "model: approve the vault prompt if one appears"
  av inject +DEEPSEEK_API_KEY -- env CREW_MODEL_TOKEN="$token" \
    node "$proxy_script" --listen 3128 --allow "$egress_allow" --key-hash-out "$key_hash_file" &
  service_pid=$!
  for _ in {1..600}; do
    if [[ -s "$key_hash_file" ]] && lsof -nP -iTCP:3128 -sTCP:LISTEN >/dev/null 2>&1; then
      break
    fi
    if ! kill -0 "$service_pid" 2>/dev/null; then
      break
    fi
    sleep 0.2
  done
  if [[ ! -s "$key_hash_file" ]]; then
    echo "model: the vault returned no DEEPSEEK_API_KEY." >&2
    exit 1
  fi
  if ! lsof -nP -iTCP:3128 -sTCP:LISTEN >/dev/null 2>&1; then
    echo "model: the proxy did not start." >&2
    exit 1
  fi
fi

printf '\nphase 1: the box\n'
limactl shell "$name" -- sudo -n -u agent -H bash /tmp/crew-agent-checks.sh || status=1
limactl shell "$name" -- sudo -n bash /tmp/crew-root-checks.sh || status=1

if [[ "$phase" == proxy ]]; then
  printf '\nphase 3a: the egress proxy\n'
  limactl copy "$proxy_check" "$name:/tmp/crew-proxy-checks.sh"
  limactl shell "$name" -- sudo -n -u agent -H bash /tmp/crew-proxy-checks.sh || status=1
fi

if [[ "$phase" == model ]]; then
  printf '\nphase 3a-2: the model key\n'
  limactl copy "$model_check" "$name:/tmp/crew-model-checks.sh"
  limactl shell "$name" -- sudo -n -u agent -H env \
    CREW_REAL_KEY_SHA256="$(cat "$key_hash_file")" bash -l /tmp/crew-model-checks.sh || status=1
fi

if [[ "$phase" == toolchain ]]; then
  printf '\nphase 2: the toolchain\n'
  limactl copy "$toolchain_check" "$name:/tmp/crew-toolchain-checks.sh"
  limactl shell "$name" -- sudo -n -u agent -H env CREW_EXPECTED_PI="$expected_pi" \
    bash -l /tmp/crew-toolchain-checks.sh || status=1
fi

if [[ "$status" -eq 0 ]]; then
  printf '\n%s: pass\n' "$phase"
else
  printf '\n%s: fail\n' "$phase" >&2
fi

exit "$status"
