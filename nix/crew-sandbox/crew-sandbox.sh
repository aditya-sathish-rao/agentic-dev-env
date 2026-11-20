# shellcheck shell=bash
# The operator's handle on the crew VM. One entry point, so the VM is only ever
# created from the pinned definition and every gate runs the same way.
name=crew
# Injected by nix/crew-sandbox/default.nix; defaults keep this file standalone.
config=${config:-}
check=${check:-}
proxy_script=${proxy_script:-}
egress_allow=${egress_allow:-}
broker_script=${broker_script:-}
broker_app_id=${broker_app_id:-}
broker_repos_file=${broker_repos_file:-}

usage() {
  cat >&2 <<'EOF'
usage: crew-sandbox <command>

  up       create the crew VM if it is missing, then start it
  down     stop it
  destroy  stop it and delete its disk
  kill     stop the VM and revoke every token the running broker issued
  status   show Lima's view of it
  shell    open a shell inside it, or run the arguments there
  check    run the phase gates against it
  proxy    run the egress proxy and model gateway in the foreground
           (needs the VM and DEEPSEEK_API_KEY from the vault)
  broker   run the token broker in the foreground (reads GITHUB_APP_PRIVATE_KEY)
EOF
}

status_of() {
  limactl list "$name" --format '{{.Status}}' 2>/dev/null || true
}

# The gateway token lives only in the guest. Reading it here keeps it out of the
# repo and out of the host's environment until the proxy needs it.
model_token() {
  limactl shell "$name" -- sudo -n cat /etc/crew-model-token 2>/dev/null | tr -d '[:space:]' || true
}

command=${1:-}
[[ $# -gt 0 ]] && shift

case "$command" in
  up)
    case "$(status_of)" in
      Running) echo "crew: already running" ;;
      "") limactl start --name="$name" --tty=false "$config" ;;
      *) limactl start --tty=false "$name" ;;
    esac
    ;;
  down)
    if [[ "$(status_of)" == Running ]]; then
      limactl stop "$name"
    else
      echo "crew: not running"
    fi
    ;;
  destroy)
    limactl stop --force "$name" 2>/dev/null || true
    limactl delete --force "$name"
    ;;
  kill)
    broker_port=${CREW_BROKER_PORT:-3129}
    revoked="no broker was running; tokens expire on their own"
    if lsof -nP -iTCP:"$broker_port" -sTCP:LISTEN >/dev/null 2>&1; then
      if response=$(curl -fsS -m 30 -X POST "http://127.0.0.1:${broker_port}/revoke-all" 2>/dev/null); then
        revoked=$response
      else
        revoked="the broker did not answer; tokens will expire on their own"
      fi
    fi
    if [[ "$(status_of)" == Running ]]; then
      limactl stop "$name"
      echo "crew: VM stopped"
    else
      echo "crew: VM was not running"
    fi
    echo "crew: ${revoked}"
    ;;
  status) limactl list ;;
  shell)
    # `crew-sandbox shell -- cmd` and `crew-sandbox shell cmd` both mean the same
    # thing; limactl takes the command after its own `--`.
    [[ ${1:-} == -- ]] && shift
    if [[ $# -gt 0 ]]; then
      limactl shell "$name" -- "$@"
    else
      limactl shell "$name"
    fi
    ;;
  check) exec "$check" "$@" ;;
  proxy)
    if ! command -v av >/dev/null 2>&1; then
      echo "crew-sandbox proxy: av is not on PATH; it is what injects DEEPSEEK_API_KEY" >&2
      exit 1
    fi
    token=$(model_token)
    if [[ -z "$token" ]]; then
      echo "crew-sandbox proxy: the crew VM is not running or /etc/crew-model-token is missing." >&2
      echo "Start it with 'crew-sandbox up'; a VM created before the token existed must be re-created." >&2
      exit 1
    fi
    exec av inject +DEEPSEEK_API_KEY -- env CREW_MODEL_TOKEN="$token" \
      node "$proxy_script" --listen "${CREW_PROXY_PORT:-3128}" --allow "$egress_allow" "$@"
    ;;
  broker)
    exec av inject +GITHUB_APP_PRIVATE_KEY -- env \
      CREW_APP_ID="$broker_app_id" CREW_BROKER_REPOS_FILE="$broker_repos_file" \
      node "$broker_script" "$@"
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    usage
    exit 2
    ;;
esac
