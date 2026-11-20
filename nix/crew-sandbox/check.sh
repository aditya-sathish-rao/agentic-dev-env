# shellcheck shell=bash
# Phase gates for the crew VM. Each phase is one command that proves the phase's
# boundary still holds on the guest as it is right now, not as it was built.
set -euo pipefail

name=crew
# Injected by nix/crew-sandbox/default.nix; defaults keep this file standalone.
agent_checks=${agent_checks:-}
root_checks=${root_checks:-}
proxy_check=${proxy_check:-}
toolchain_check=${toolchain_check:-}
expected_pi=${expected_pi:-}
proxy_script=${proxy_script:-}
egress_allow=${egress_allow:-}

usage() {
  echo "usage: crew-sandbox check [box|proxy|toolchain]"
}

phase=${1:-box}
case "$phase" in
  box | proxy | toolchain) ;;
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

if [[ "$(limactl list "$name" --format '{{.Status}}')" != Running ]]; then
  echo "crew-sandbox check: the crew VM is not running; start it with 'crew-sandbox up'." >&2
  exit 1
fi

status=0
proxy_pid=""

# shellcheck disable=SC2329  # invoked by the EXIT trap below
cleanup() {
  if [[ -n "$proxy_pid" ]]; then kill "$proxy_pid" 2>/dev/null || true; fi
  limactl shell "$name" -- sudo -n rm -f /tmp/crew-agent-checks.sh /tmp/crew-root-checks.sh \
    /tmp/crew-proxy-checks.sh /tmp/crew-toolchain-checks.sh >/dev/null 2>&1 || true
}
trap cleanup EXIT

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
    proxy_pid=$!
    for _ in {1..50}; do
      if curl -s -o /dev/null -m 1 -x http://127.0.0.1:3128 https://cache.nixos.org/nix-cache-info; then
        break
      fi
      sleep 0.2
    done
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
