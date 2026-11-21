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
broker_ruleset=${broker_ruleset:-}
broker_script=${broker_script:-}
broker_app_id=${broker_app_id:-}
broker_repos_file=${broker_repos_file:-}

# The gate directory. Owned by root, group-writable by the Lima admin account so
# `limactl copy` can stage into it, and not writable by `agent`. Copying into
# world-writable /tmp let a crewmate pre-own the path root later executes; this
# makes that impossible rather than merely awkward. `agent` is not in `crew`, so
# the group bit buys it nothing.
gate_dir=/run/crew-gate

usage() {
  cat >&2 <<'EOF'
usage: crew-sandbox check <phase>

  box        the boundary itself: no mounts, no sudo, default-deny egress
  toolchain  the guest's tools, from the same pins as the host
  proxy      the egress allowlist, through a keyless proxy
  model      the model key stays on the host, through a keyed proxy
  broker     one repo, one token, revocable, and main refuses the token
  all        every phase above, in one run
EOF
}

phase=${1:-box}
case "$phase" in
  box | proxy | model | toolchain | broker | all) ;;
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
# Set by the host-side assertions in phase 1, which print their own lines because
# their subject is the host's state rather than a script running in the guest.
fail=0
# The listener probe's PID file inside the guest, and whether one is running.
probe_pid_file=/home/agent/.crew-forward-probe.pid
probe_started=0
service_pid=""
# Every port this run started a service on. A phase can start more than one
# service (the model phase starts a keyed proxy, the broker phase a broker), and
# a later phase overwrites service_pid, so cleanup needs the full set or it
# orphans the earlier listener and the next run fails on "port already in use".
service_ports=()
key_hash_file=""

# stop_service: kill the service this gate started and wait for it to be gone.
# Signalling is not enough. A child that inherited the caller's stdout keeps that
# pipe open after we exit, so `crew-sandbox check | tail` hangs forever even
# though the gate finished. We redirect the service's stdio below and reap it here.
#
# `av inject` is a wrapper: it forks the real process, so the PID we track is not
# the one holding the port. Killing only that leaves an orphaned listener that
# makes the next phase fail with "port 3128 is already in use". The port is the
# identity that matters, so the listener is stopped by port as well.
# shellcheck disable=SC2329  # reached via cleanup, which the EXIT trap invokes
stop_service() {
  local port=${1:-}
  if [[ -n "$service_pid" ]]; then
    kill "$service_pid" 2>/dev/null || true
    local _i
    for _i in {1..25}; do
      kill -0 "$service_pid" 2>/dev/null || break
      sleep 0.1
    done
    kill -9 "$service_pid" 2>/dev/null || true
    wait "$service_pid" 2>/dev/null || true
    service_pid=""
  fi
  [[ -n "$port" ]] || return 0
  local _pid
  for _pid in $(lsof -nP -iTCP:"$port" -sTCP:LISTEN -t 2>/dev/null); do
    kill "$_pid" 2>/dev/null || true
  done
  local _i
  for _i in {1..25}; do
    lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1 || return 0
    sleep 0.1
  done
  for _pid in $(lsof -nP -iTCP:"$port" -sTCP:LISTEN -t 2>/dev/null); do
    kill -9 "$_pid" 2>/dev/null || true
  done
}

# shellcheck disable=SC2329  # invoked by the EXIT trap below
cleanup() {
  local _p
  for _p in "${service_ports[@]}"; do stop_service "$_p"; done
  if [[ -n "$key_hash_file" ]]; then rm -f "$key_hash_file"; fi
  # A probe cut off before its own cleanup must not leave a listener for the next
  # run to trip over.
  if [[ "$probe_started" -eq 1 ]]; then stop_probe_listener; fi
  if [[ "$phase" != broker ]]; then
    limactl shell "$name" -- sudo -n rm -rf "$gate_dir" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

# run_broker_gate: the broker is a host service, so its gate needs no guest.
run_broker_gate() {
  if ! command -v av >/dev/null 2>&1; then
    echo "broker: av is not on PATH; it is what injects GITHUB_APP_PRIVATE_KEY" >&2
    return 1
  fi
  local broker_port=${CREW_BROKER_PORT:-3139}
  if lsof -nP -iTCP:"$broker_port" -sTCP:LISTEN >/dev/null 2>&1; then
    echo "broker: port ${broker_port} is already in use; stop that broker and rerun." >&2
    return 1
  fi
  echo "broker: starting the broker with the vault key for the duration of this gate"
  echo "broker: approve the vault prompt if one appears"
  av inject +GITHUB_APP_PRIVATE_KEY -- env CREW_APP_ID="$broker_app_id" \
    CREW_BROKER_REPOS_FILE="$broker_repos_file" CREW_BROKER_PORT="$broker_port" \
    node "$broker_script" &
  service_pid=$!
  service_ports+=("$broker_port")
  local _i
  for _i in {1..600}; do
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
    return 1
  fi
  local rc=0
  CREW_BROKER_PORT="$broker_port" broker_ruleset="$broker_ruleset" \
    bash "$broker_check" || rc=1
  return "$rc"
}

# ensure_gate_dir: create the root-owned staging directory. /run is tmpfs, so it
# is recreated per run rather than provisioned once. 0775 with the admin group:
# root owns it, `limactl copy` (which runs as the admin account) can stage into
# it, and `agent` is not in that group, so it cannot write there at all.
ensure_gate_dir() {
  if ! limactl shell "$name" -- sudo -n install -d -o root -g crew -m 0775 "$gate_dir" >/dev/null 2>&1; then
    printf 'FAIL  the gate could not create %s\n' "$gate_dir" >&2
    printf '      the guest may be interfering with the gate\n' >&2
    return 1
  fi
}

# stage <host-file> <guest-name>: put a check script where root will run it.
# A copy failure is tampering, not infrastructure: the only way it fails is that
# something in the guest owns the path, and that has to read as a named failure.
# The file is installed root-owned, so the account that staged it cannot rewrite
# what root is about to execute.
stage() {
  local src=$1 dest=$2 err
  ensure_gate_dir || return 1
  if ! err=$(limactl copy "$src" "$name:${gate_dir}/.${dest}.new" 2>&1); then
    printf 'FAIL  the gate could not stage %s\n' "$dest"
    printf '      %s\n' "$err" >&2
    printf '      the guest may be interfering with the gate\n' >&2
    return 1
  fi
  if ! limactl shell "$name" -- sudo -n install -o root -g root -m 0755 \
    "${gate_dir}/.${dest}.new" "${gate_dir}/${dest}" >/dev/null 2>&1; then
    printf 'FAIL  the gate could not install %s as root\n' "$dest"
    return 1
  fi
  limactl shell "$name" -- sudo -n rm -f "${gate_dir}/.${dest}.new" >/dev/null 2>&1 || true
}

require_vm() {
  if [[ "$(limactl list "$name" --format '{{.Status}}')" != Running ]]; then
    echo "crew-sandbox check: the crew VM is not running; start it with 'crew-sandbox up'." >&2
    return 1
  fi
}

pass() { printf 'PASS  %s\n' "$1"; }
flunk() {
  printf 'FAIL  %s\n' "$1"
  fail=1
}

# free_host_port: the first port in a short range nothing on the host is using.
# The probe publishes a guest listener on the host loopback if the boundary is
# broken, so the port has to be free here or the test would prove nothing.
free_host_port() {
  local p
  for p in 18080 18081 18082 18083 18084 18085 18086 18087; do
    if ! lsof -nP -iTCP:"$p" -sTCP:LISTEN >/dev/null 2>&1; then
      printf '%s\n' "$p"
      return 0
    fi
  done
  return 1
}

# probe_no_forward <bind-address> <label>: start a listener inside the guest as
# `agent` and require the host's loopback to stay empty.
#
# Lima's host agent appends a fallback rule that publishes every guest listener on
# the host's own 127.0.0.1, on the same port, for all ports and both protocols, and
# `portForwards: []` does not remove it — the instance definition needs the `ignore`
# rule. The forward rides the guest agent rather than the network, so the guest's
# input chain never sees the connection: a crewmate could put a service on the
# operator's loopback with one command. Only the host can observe that, so this
# assertion lives here and not in checks/agent.sh.
#
# The listener is `nc`, not a web server: the guest's resolver is closed on purpose
# and Python's http.server resolves its own bind address at startup, so it comes up
# seconds after a gate would have given up on it.
# stop_probe_listener: leave no listener behind, on every path including a failure.
stop_probe_listener() {
  [[ "$probe_started" -eq 1 ]] || return 0
  limactl shell "$name" -- sudo -n -u agent -H bash -c \
    "kill \$(cat ${probe_pid_file}) 2>/dev/null; rm -f ${probe_pid_file}" >/dev/null 2>&1 || true
  probe_started=0
}

probe_no_forward() {
  local bind=$1 label=$2 port _i
  if ! port=$(free_host_port); then
    flunk "$label (no free host port to test with)"
    return
  fi
  probe_started=1
  limactl shell "$name" -- sudo -n -u agent -H bash -c \
    "nohup timeout 300 nc -l -k -s ${bind} -p ${port} >/dev/null 2>&1 &
     echo \$! > ${probe_pid_file}" >/dev/null 2>&1 || true
  # If the listener is not up, the host probe would fail for the wrong reason and
  # report a boundary that was never exercised.
  local up=0
  for _i in {1..25}; do
    if limactl shell "$name" -- sudo -n -u agent -H bash -c \
      "nc -z -w 1 127.0.0.1 ${port}" >/dev/null 2>&1; then
      up=1
      break
    fi
    sleep 0.2
  done
  if [[ "$up" -ne 1 ]]; then
    flunk "$label (could not start a listener inside the guest)"
    stop_probe_listener
    return
  fi
  # Watch for a few seconds rather than sampling once: the guest agent reports
  # listening ports on its own interval, so a single early look could miss the
  # forward and pass a boundary that does not exist.
  local forwarded=0
  for _i in {1..20}; do
    if lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1 ||
      nc -z -w 1 127.0.0.1 "$port" >/dev/null 2>&1; then
      forwarded=1
      break
    fi
    sleep 0.2
  done
  if [[ "$forwarded" -eq 1 ]]; then
    flunk "$label (the guest published 127.0.0.1:${port} on the host)"
  else
    pass "$label"
  fi
  stop_probe_listener
}

# phase_box: the boundary. Root-owned directory, so it must be created first.
phase_box() {
  require_vm || return 1
  ensure_gate_dir || return 1
  local rc=0
  stage "$agent_checks" crew-agent-checks.sh || rc=1
  stage "$root_checks" crew-root-checks.sh || rc=1
  if [[ "$rc" -ne 0 ]]; then
    return 1
  fi
  printf '\nphase 1: the box\n'
  limactl shell "$name" -- sudo -n -u agent -H bash "${gate_dir}/crew-agent-checks.sh" || rc=1
  limactl shell "$name" -- sudo -n bash "${gate_dir}/crew-root-checks.sh" || rc=1
  # The guest cannot see the host's loopback, so the ingress half of the boundary
  # is asserted from here, against a listener the gate starts as `agent`.
  probe_no_forward 0.0.0.0 "a guest listener on every address stays off the host"
  probe_no_forward 127.0.0.1 "a guest listener on loopback stays off the host"
  [[ "$fail" -eq 0 ]] || rc=1
  return "$rc"
}

# proxy_selftest: the ClientHello parser is the only thing standing between an
# allowlisted address and any other host on the same CDN, so prove it before
# trusting a tunnel. It needs no network and no VM, so every phase that relies on
# the allowlist can afford it.
proxy_selftest() {
  if node "$proxy_script" --selftest --allow "$egress_allow" >/dev/null 2>&1; then
    printf 'PASS  the ClientHello parser reads the name a tunnel asks for\n'
  else
    printf 'FAIL  the ClientHello parser reads the name a tunnel asks for\n'
    return 1
  fi
}

phase_proxy() {
  proxy_selftest || return 1
  local started=0
  if lsof -nP -iTCP:3128 -sTCP:LISTEN >/dev/null 2>&1; then
    echo "proxy: already listening on 127.0.0.1:3128"
  else
    echo "proxy: starting one for the duration of this gate"
    node "$proxy_script" --listen 3128 --allow "$egress_allow" \
      >/dev/null 2>&1 &
    service_pid=$!
    service_ports+=(3128)
    started=1
    local _i
    for _i in {1..50}; do
      if curl -s -o /dev/null -m 1 -x http://127.0.0.1:3128 https://cache.nixos.org/nix-cache-info; then
        break
      fi
      sleep 0.2
    done
  fi
  local rc=0
  stage "$proxy_check" crew-proxy-checks.sh || return 1
  printf '\nphase 3a: the egress proxy\n'
  limactl shell "$name" -- sudo -n -u agent -H bash "${gate_dir}/crew-proxy-checks.sh" || rc=1
  # Stop the keyless proxy we started, so the next phase can bind 3128 with the
  # key. A proxy the operator already had running is left alone.
  if [[ "$started" -eq 1 ]]; then stop_service 3128; fi
  return "$rc"
}

phase_model() {
  if ! command -v av >/dev/null 2>&1; then
    echo "model: av is not on PATH; it is what injects DEEPSEEK_API_KEY" >&2
    return 1
  fi
  local token
  token=$(limactl shell "$name" -- sudo -n cat /etc/crew-model-token 2>/dev/null | tr -d '[:space:]' || true)
  if [[ -z "$token" ]]; then
    echo "model: /etc/crew-model-token is missing; re-create the VM from the current lima.yaml." >&2
    return 1
  fi
  if lsof -nP -iTCP:3128 -sTCP:LISTEN >/dev/null 2>&1; then
    echo "model: port 3128 is already in use; stop that proxy so this gate controls the key." >&2
    return 1
  fi
  key_hash_file=$(mktemp)
  echo "model: starting the proxy with the vault key for the duration of this gate"
  echo "model: approve the vault prompt if one appears"
  av inject +DEEPSEEK_API_KEY -- env CREW_MODEL_TOKEN="$token" \
    node "$proxy_script" --listen 3128 --allow "$egress_allow" --key-hash-out "$key_hash_file" \
    >/dev/null 2>&1 &
  service_pid=$!
  service_ports+=(3128)
  local _i
  for _i in {1..600}; do
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
    return 1
  fi
  if ! lsof -nP -iTCP:3128 -sTCP:LISTEN >/dev/null 2>&1; then
    echo "model: the proxy did not start." >&2
    return 1
  fi
  local rc=0
  stage "$model_check" crew-model-checks.sh || return 1
  printf '\nphase 3a-2: the model key\n'
  limactl shell "$name" -- sudo -n -u agent -H env \
    CREW_REAL_KEY_SHA256="$(cat "$key_hash_file")" bash -l "${gate_dir}/crew-model-checks.sh" || rc=1
  # The keyed proxy enforces the same allowlist as the keyless one, so the egress
  # assertions run here too. A gate that proves the key stays home while the
  # allowlist is wrong would report a boundary that does not exist.
  proxy_selftest || return 1
  stage "$proxy_check" crew-proxy-checks.sh || return 1
  printf '\nphase 3a: the egress proxy (through the keyed proxy)\n'
  limactl shell "$name" -- sudo -n -u agent -H bash "${gate_dir}/crew-proxy-checks.sh" || rc=1
  # Stop the keyed proxy here rather than leaving it to the EXIT trap: the broker
  # gate starts its own service and overwrites service_pid, so a later phase would
  # orphan this listener and the next run would fail on "port 3128 is already in
  # use". Each phase owns the service it started.
  stop_service 3128
  return "$rc"
}

phase_toolchain() {
  local rc=0
  stage "$toolchain_check" crew-toolchain-checks.sh || return 1
  printf '\nphase 2: the toolchain\n'
  limactl shell "$name" -- sudo -n -u agent -H env CREW_EXPECTED_PI="$expected_pi" \
    bash -l "${gate_dir}/crew-toolchain-checks.sh" || rc=1
  return "$rc"
}

# Each phase is named literally rather than dispatched through a variable so
# the linter can see each call, and a typo'd phase name fails the build.
#
# `all` exists because a boundary that holds in isolation can still fail in
# combination: phase 1 tears down the gate directory that phases 2-4 reuse, and
# the broker gate revokes the very token the model gate needs. Running them in
# one process is what catches that. The broker gate is a host service, so it runs
# whether or not the guest is up.
case "$phase" in
  box) phase_box || status=1 ;;
  toolchain) phase_toolchain || status=1 ;;
  proxy) phase_proxy || status=1 ;;
  model) phase_model || status=1 ;;
  broker) run_broker_gate || status=1 ;;
  all)
    phase_box || status=1
    phase_toolchain || status=1
    phase_proxy || status=1
    phase_model || status=1
    run_broker_gate || status=1
    ;;
esac

if [[ "$status" -eq 0 ]]; then
  printf '\n%s: pass\n' "$phase"
else
  printf '\n%s: fail\n' "$phase" >&2
fi

exit "$status"
