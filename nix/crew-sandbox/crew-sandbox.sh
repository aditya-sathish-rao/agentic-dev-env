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
broker_ruleset=${broker_ruleset:-}
guest_flake=${guest_flake:-}

usage() {
  cat >&2 <<'EOF'
usage: crew-sandbox <command>

  up       create the crew VM if it is missing, then start it
  down     stop it
  destroy  stop it and delete its disk
  kill     stop the VM and revoke every token the running broker issued
  status   show Lima's view of it
  shell    open a shell inside it, or run the arguments there
  apply    install the pinned guest toolchain with home-manager (inside the VM)
  check    run the phase gates against it
  proxy    run the egress proxy and model gateway in the foreground
           (needs the VM and DEEPSEEK_API_KEY from the vault)
  broker   run the token broker in the foreground (reads GITHUB_APP_PRIVATE_KEY)
  ruleset  apply the pinned branch ruleset to a repository
           (needs gh on PATH and admin on the repository)
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
    # Order matters. While the broker is open (finding C1) any crewmate can mint a
    # token, so revoking first leaves a window where a fresh token is issued after
    # the sweep and outlives it. Stop the VM first: with the guest down nothing can
    # ask, so the revoke then sweeps a set that can no longer grow.
    broker_port=${CREW_BROKER_PORT:-3129}

    stopped="the VM was not running"
    if [[ "$(status_of)" == Running ]]; then
      # errexit is on, and a failed stop must not skip the revoke, so the failure
      # is caught and reported instead of aborting the command.
      if limactl stop "$name"; then
        stopped="VM stopped"
      else
        stopped="the VM did not stop; revoking anyway"
      fi
    fi
    echo "crew: ${stopped}"

    revoked="no broker was running; tokens expire on their own"
    if lsof -nP -iTCP:"$broker_port" -sTCP:LISTEN >/dev/null 2>&1; then
      if response=$(curl -fsS -m 30 -X POST "http://127.0.0.1:${broker_port}/revoke-all" 2>/dev/null); then
        revoked=$response
      else
        revoked="the broker did not answer; tokens will expire on their own"
      fi
    fi
    echo "crew: ${revoked}"

    # Either half alone leaves a credential alive, so a silent partial kill is the
    # dangerous outcome and it has to change the exit status.
    if [[ "$stopped" != "VM stopped" && "$stopped" != "the VM was not running" ]]; then
      exit 1
    fi
    case "$revoked" in
      *'"revoked"'*) ;;
      "no broker was running; tokens expire on their own") ;;
      *) exit 1 ;;
    esac
    ;;
  apply)
    # M1: nothing applied guest.nix, so a rebuilt VM had no toolchain at all and
    # `check toolchain` failed on every line. This runs the same pinned
    # home-manager configuration the flake defines, evaluated inside the guest
    # because this Mac has no aarch64-linux builder.
    case "$(status_of)" in
      Running) ;;
      *)
        echo "crew-sandbox apply: the crew VM is not running; start it with 'crew-sandbox up'." >&2
        exit 1
        ;;
    esac
    # The flake has to travel to the guest: host store paths do not exist inside
    # the VM, and this Mac cannot build the Linux derivation. Copy the pinned
    # source over and evaluate it there.
    staging=/tmp/crew-flake
    echo "apply: staging the flake for the guest"
    # root:crew 0775 for the same reason as the gate directory: `limactl copy`
    # runs as the admin account, not as root, so an agent-owned 0700 directory
    # refuses it. Ownership is handed to agent after the copy.
    limactl shell "$name" -- sudo -n rm -rf "$staging"
    limactl shell "$name" -- sudo -n install -d -o root -g crew -m 0775 "$staging"
    # The exit status is not trustworthy: rsync reports failure when it cannot
    # chmod or retime the root-owned directory itself, while copying every file
    # successfully. Verify the result instead of the status.
    limactl copy --backend=rsync "$guest_flake/." "${name}:${staging}" >/dev/null 2>&1 || true
    if ! limactl shell "$name" -- test -f "${staging}/flake.nix"; then
      echo "crew-sandbox apply: could not stage the flake into the guest" >&2
      exit 1
    fi
    limactl shell "$name" -- sudo -n chown -R agent:agent "$staging"
    echo "apply: installing the pinned guest toolchain (this builds inside the VM)"
    # Nix is installed in `agent`'s profile, so this must run as that user; root
    # here has no nix at all. home-manager also needs to own ~/.nix-profile.
    # `-b backup` because `useradd` already wrote stock ~/.bashrc and ~/.profile;
    # without it home-manager refuses to activate and `apply` is not idempotent
    # on a fresh VM, which is what made `check toolchain` fail on every line.
    limactl shell "$name" -- sudo -n -u agent -H bash -lc \
      "nix run 'path:${staging}#home-manager' -- switch -b backup --flake 'path:${staging}#agent@aarch64-linux'"
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
  ruleset)
    repo=${1:-}
    if [[ -z "$repo" ]]; then
      echo "usage: crew-sandbox ruleset <owner/repo>" >&2
      exit 2
    fi
    if ! command -v gh >/dev/null 2>&1; then
      echo "crew-sandbox ruleset: gh is not on PATH" >&2
      exit 1
    fi
    # Idempotent: a repository that already has the ruleset is left as it is, so a
    # rerun is safe and a repository that drifted shows up as a diff, not a duplicate.
    existing=$(gh api "repos/${repo}/rulesets" --jq '.[] | select(.name == "crew-gate: human merge only") | .id' 2>/dev/null | head -1)
    if [[ -n "$existing" ]]; then
      gh api -X PUT "repos/${repo}/rulesets/${existing}" --input "$broker_ruleset" >/dev/null
      echo "crew-sandbox ruleset: updated ruleset ${existing} on ${repo}"
    else
      gh api -X POST "repos/${repo}/rulesets" --input "$broker_ruleset" >/dev/null
      echo "crew-sandbox ruleset: created the ruleset on ${repo}"
    fi
    gh api "repos/${repo}/rules/branches/$(gh api "repos/${repo}" --jq .default_branch)" \
      --jq '[.[] | .type] | join(", ")' 2>/dev/null |
      sed 's/^/crew-sandbox ruleset: the default branch now requires: /'
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
