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
  status   show Lima's view of it
  shell    open a shell inside it, or run the arguments there
  check    run the phase gates against it
  proxy    run the guest's egress proxy in the foreground
  broker   run the token broker in the foreground (reads GITHUB_APP_PRIVATE_KEY)
EOF
}

status_of() {
  limactl list "$name" --format '{{.Status}}' 2>/dev/null || true
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
  proxy) exec node "$proxy_script" --listen "${CREW_PROXY_PORT:-3128}" --allow "$egress_allow" ;;
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
