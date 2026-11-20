# shellcheck shell=bash
# Phase gates for the crew VM. Each phase is one command that proves the phase's
# boundary still holds on the guest as it is right now, not as it was built.
set -euo pipefail

name=crew
# Injected by nix/crew-sandbox/default.nix; defaults keep this file standalone.
agent_checks=${agent_checks:-}
root_checks=${root_checks:-}

usage() {
  echo "usage: crew-sandbox check [box]"
}

phase=${1:-box}
case "$phase" in
  box) ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    echo "crew-sandbox check: no gate for '$phase' yet" >&2
    usage >&2
    exit 2
    ;;
esac

if [[ "$(limactl list "$name" --format '{{.Status}}')" != Running ]]; then
  echo "crew-sandbox check: the crew VM is not running; start it with 'crew-sandbox up'." >&2
  exit 1
fi

status=0

# The scripts are copied in rather than piped: the two halves need different users,
# and a pty is the wrong place to carry a script.
limactl copy "$agent_checks" "$name:/tmp/crew-agent-checks.sh"
limactl copy "$root_checks" "$name:/tmp/crew-root-checks.sh"

printf '\nphase 1: the box\n'
limactl shell "$name" -- sudo -n -u agent -H bash /tmp/crew-agent-checks.sh || status=1
limactl shell "$name" -- sudo -n bash /tmp/crew-root-checks.sh || status=1

limactl shell "$name" -- sudo -n rm -f /tmp/crew-agent-checks.sh /tmp/crew-root-checks.sh

if [[ "$status" -eq 0 ]]; then
  printf '\nphase 1: pass\n'
else
  printf '\nphase 1: fail\n' >&2
fi

exit "$status"
