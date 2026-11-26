# Host split + crew-sandbox extraction: code review

Reviewed 26 November 2026. Staged diff on `main` at `8b6b86b` — 33 files,
+396 / −2506. Line-level findings only; shape and sequencing are in
[`host-split-architecture-review.md`](host-split-architecture-review.md).

Every finding below was reproduced. Commands and outputs are in the finding, or in
§1 of the architecture review. Nothing here is inferred from the diff alone.

> **On the requested skills.** No `matt pocock` skill is installed on this machine
> (searched `~/.agents/skills`, `~/.claude/skills`, `~/.copilot`,
> `~/.vscode/agent-plugins`). I applied the installed `engineering-principles`
> bundle; the ledger is in §6 of the architecture review.

---

## Summary

| #   | Severity | File                                            | Finding                                                                   |
| --- | -------- | ----------------------------------------------- | ------------------------------------------------------------------------- |
| C1  | High     | `crew-sandbox.nix:11-17`                        | Allowlist policy surface dropped; services fall back to embedded examples |
| C2  | High     | `docs/README.md:312`                            | `check all --expected-tools "pi gh"` cannot pass — guest has no `gh`      |
| C3  | High     | `docs/README.md:361`, `GLOSSARY.md:266,296,300` | Model gateway port is 3130, docs say 3128                                 |
| C4  | High     | `docs/README.md:400-404`                        | Gates cannot run beside the always-on agents; `check model` refuses       |
| C5  | Medium   | `.githooks/check:196`, `rebuild.sh:11-12`       | Host list duplicated three times                                          |
| C6  | Medium   | `identity.nix:15-19,29`                         | `identity.host` is dead                                                   |
| C7  | Medium   | `mini.nix`                                      | Enables user agents a headless host cannot start                          |
| C8  | Medium   | `docs/README.md:462-473`                        | Layout map omits six new files, misattributes VS Code                     |
| C9  | Medium   | `docs/adr/0010-crew-runs-in-one-vm.md:32,38`    | `portForwards: []` and "one host port out" are false                      |
| C10 | Medium   | `crew-sandbox.nix:14-15`                        | Guest on DeepSeek, host on OpenRouter, undocumented                       |
| C11 | Low      | `flake.nix:69`                                  | `piPackage` is a dead specialArg in `mkDarwin`                            |
| C12 | Low      | `crew-sandbox.nix:13`                           | Hardcoded `aarch64-darwin` vs `packages.${system}`                        |
| C13 | Low      | `configuration.nix:36`, `crew-sandbox.nix:9`    | `system.primaryUser` set twice                                            |
| C14 | Low      | `crew-sandbox.nix:24-25`                        | PATH override replaces instead of appends                                 |
| C15 | Low      | `docs/README.md:406`                            | "`check all` runs every phase" — it excludes `headless`                   |
| C16 | Low      | `docs/README.md:383-384`                        | "Apply it with / by applying that file" — broken sentence                 |

**Clean:** `statix`, `deadnix`, `shellcheck`, `taplo`, `selene` all pass on the
changed files, and `./.githooks/check --all` passes end to end. Both hosts evaluate.
No lint findings to report.

---

## High

### C1 — The allowlist policy surface was dropped

`crew-sandbox.nix:11-17`:

```nix
services.crew-sandbox = {
  enable = true;
  package = crew-sandbox.packages.aarch64-darwin.default;
  proxy.upstream = "https://api.deepseek.com";
  proxy.keySecret = "DEEPSEEK_API_KEY";
  broker.appID = "5853565";
};
```

No `proxy.allowFile`, no `broker.reposAllow`. Verified:

```console
$ nix eval --impure --json .#darwinConfigurations.primary.config.services.crew-sandbox.proxy.allowFile
null
$ nix eval --impure --json .#darwinConfigurations.primary.config.services.crew-sandbox.broker.reposAllow
null
```

The module documents `null` as "uses the example compiled into the binary". The
deleted `nix/crew-sandbox/egress-allow` and `repos-allow` were the live policy; the
upstream `.example` files differ from them only in the header comment, so the
_current_ behaviour is unchanged — but the operator can no longer change it from
this repo.

```nix
services.crew-sandbox = {
  # …
  proxy.allowFile = ./crew-sandbox/egress-allow;
  broker.reposAllow = ./crew-sandbox/repos-allow;
};
```

with those two files restored from `git show HEAD:nix/crew-sandbox/{egress,repos}-allow`.

### C2 — `check all --expected-tools "pi gh"` cannot pass

`docs/README.md:312`. The toolchain gate requires each named tool to resolve under
`/nix/store` (`verify/gates/toolchain.sh:50-60`). The guest fleet is `pi` plus the
eight `nix/crew-tools` artifacts. Verified:

```console
$ nix eval --impure --json '.#homeConfigurations."agent@aarch64-linux".config.home.packages' \
    --apply 'ps: builtins.filter (p: builtins.match ".*gh-[0-9].*" (baseNameOf p) != null) ps'
[]
```

`lima.yaml` installs only `nftables curl dnsutils` via apt, so there is no `gh`
anywhere in the guest. The upstream README's `"pi gh"` example assumes a consumer
that ships `gh`; this one does not.

```sh
nix run .#crew-sandbox -- check all --expected-tools "pi gh-axi" \
```

### C3 — Model gateway port drift

The pinned proxy serves the gateway on `--model-listen`, default **3130**, and the
pinned guest `models.json` points at `:3130/model`. Verified from the evaluated
guest config:

```console
$ nix eval --impure --raw '.#homeConfigurations."agent@aarch64-linux".config.home.file.".pi/agent/models.json".source'
/nix/store/yq7f1qc52pi1gjv8lxj9p8cvzrz6r0fr-models.json
$ cat /nix/store/yq7f1qc52pi1gjv8lxj9p8cvzrz6r0fr-models.json
{ "providers": { "deepseek": { "baseUrl": "http://host.lima.internal:3130/model", … } } }
```

Four doc sites say 3128:

| File:line            | Current text                                       | Should be                                                    |
| -------------------- | -------------------------------------------------- | ------------------------------------------------------------ |
| `docs/README.md:361` | `http://host.lima.internal:3128/model`             | `:3130/model`                                                |
| `GLOSSARY.md:266`    | diagram `+ model gateway 192.168.5.2:3128`         | `:3128` egress, `:3130` gateway                              |
| `GLOSSARY.md:296`    | "The same listener also carries the model gateway" | a second listener, kept off the egress socket                |
| `GLOSSARY.md:300`    | `…:3128/model` through `guest/models.json`         | `:3130/model`; `guest/models.json` is no longer in this repo |

The split is deliberate upstream — `proxy.mjs` comments that sharing the CONNECT
socket "made the gateway a second egress door".

### C4 — The gates cannot run beside the always-on agents

`docs/README.md:400-404` claims "the gates start temporary services only where
required and stop the services they started". True of the gate; false of the system
it now runs against, because the proxy and broker are launchd user agents that bind
`3128`/`3130` at login.

`verify/gates/check.sh:456-459`:

```sh
if lsof -nP -iTCP:3128 -sTCP:LISTEN >/dev/null 2>&1 ||
  lsof -nP -iTCP:"$model_port" -sTCP:LISTEN >/dev/null 2>&1; then
  echo "model: port 3128 or ${model_port} is already in use; stop that service so this gate controls the key." >&2
  return 1
fi
```

`check proxy` is quieter but also wrong: `start_keyless_proxy` (`check.sh:411-415`)
reuses an existing listener, so the phase documented as "through a keyless proxy"
tests the keyed deployed one.

Either give the gate its own ports (`--port` / `--model-port` are already flags on
`crew-sandbox proxy`), or document the `launchctl bootout` step next to the command
list.

---

## Medium

### C5 — Host list duplicated three times

`flake.nix:129-131` owns it; `.githooks/check:196` and `rebuild.sh:11-12` restate it.

```sh
# .githooks/check:196
for host in primary mini; do
```

```sh
# rebuild.sh:11-12
case "$HOST" in
  primary | mini) ;;
```

A third host file that does not evaluate passes CI, because the loop never names it.
Derive it — this works today:

```console
$ nix eval --impure --json .#darwinConfigurations --apply builtins.attrNames
["mini","primary"]
```

### C6 — `identity.host` is dead

`identity.nix:15-19` computes it, `:29` exports it, nothing reads it:

```console
$ grep -rn 'identity\.host' --include='*.nix' .
(no output)
```

`flake.nix` no longer keys on it; `rebuild.sh` owns host selection. Delete the field
and the `AGENTIC_DEV_ENV_HOST` export at `rebuild.sh:21`, keeping the variable as
`rebuild.sh`'s own input. Then fix `docs/host-split-plan.md:13` and `GLOSSARY.md:93`,
which still describe the old meaning.

### C7 — `mini` enables user agents it cannot start

`mini.nix` imports `crew-sandbox.nix`, so:

```console
$ nix eval --impure --json .#darwinConfigurations.mini.config.services.crew-sandbox.enable
true
```

The module's header explains why that cannot work headless: user agents start with a
GUI login, and the vault answers an unattended read with "human approval required".
`docs/host-split-plan.md:107-111` says the same. The code does not.

Until Phase 3 lands, make it explicit rather than implied:

```nix
# mini.nix
services.crew-sandbox.enable = lib.mkDefault false;  # Phase 3: no GUI login to start the agents
```

or add an `assertions` entry so evaluation fails instead of the service failing at 3am.

### C8 — Layout map is stale

`docs/README.md:462-473`. The `crew-sandbox` input entry was added correctly; the
host-split half is missing.

- `:472` says `home.nix` owns "rendered VS Code settings" — that moved to
  `home-vscode.nix`
- missing: `primary.nix`, `mini.nix`, `home-manager.nix`, `home-vscode.nix`,
  `crew-sandbox.nix`, `docs/host-split-plan.md`

### C9 — ADR-0010 states two false things

`docs/adr/0010-crew-runs-in-one-vm.md:32` — "`mounts: []`, `portForwards: []`". The
pinned `lima.yaml` has a one-entry `ignore` rule. (The old file had the same rule, so
this was already wrong — but the line was edited in this diff and the claim was not
corrected.)

`:38` — "one host port out, reserved for the egress proxy". It is two: `3128` and
`3130`, both opened in the guest's nftables output chain.

### C10 — Provider split-brain

Host fleet: OpenRouter (`home/.pi/agent/settings.json`, `mate`, `home/.local/bin/pi`
inject `OPENROUTER_API_KEY`). Guest fleet: DeepSeek (`crew-sandbox.nix:14-15`, and
the pinned guest `models.json` hardcodes a provider named `deepseek`).

Deliberate or not, it is undocumented. If deliberate, one sentence in
`docs/host-split-plan.md`. If not, the guest module needs the provider name as an
option rather than a hardcoded `deepseek`.

---

## Low

### C11 — `piPackage` is a dead specialArg in `mkDarwin`

`flake.nix:69`. Only `home.nix` uses it, and it arrives via `home-manager.nix`'s
`extraSpecialArgs`. No darwin module reads it. Drop it from `mkDarwin`'s
`specialArgs`.

### C12 — Hardcoded system in `crew-sandbox.nix:13`

`crew-sandbox.packages.aarch64-darwin.default` while `flake.nix:102` uses
`packages.${system}.default`. The module's own `defaultText` says `${system}`. Same
limitation as the plan's open question about `builtins.currentSystem`, expressed
twice.

### C13 — `system.primaryUser` set twice

`configuration.nix:36` and `crew-sandbox.nix:9`, both to `identity.username`.
Harmless today; two owners for one value is how they drift.

### C14 — PATH override replaces rather than appends

`crew-sandbox.nix:24-25` sets a full PATH to reach `/usr/local/bin/av`. The module's
wrapper already prepends its own packages, so this only needs to add
`/usr/local/bin`; replacing the whole value discards anything else launchd provided.

### C15 — "`check all` runs every phase"

`docs/README.md:406`. The pinned `check.sh:603-611` runs guest, root, toolchain,
proxy, model, broker, redteam — **not** `headless`. Say "every guest phase".

### C16 — Broken sentence

`docs/README.md:383-384`:

```
  `bypass_actors` list so the App is not exempt. Apply it with
  by applying that file to the repository; the new CLI has no ruleset-application command.
```

The edit left "Apply it with" dangling. Drop it:

```
  `bypass_actors` list so the App is not exempt. Apply that file to the repository;
  the new CLI has no ruleset-application command.
```

---

## What I verified as correct

So the next reviewer does not redo it.

- `mkDarwin` wires `specialArgs` and `modules` correctly; both hosts produce distinct
  drvs and the shared module list is applied to both.
- `home-manager.nix` correctly re-passes `identity` and `piPackage` — darwin
  `specialArgs` genuinely stop at darwin modules.
- `users.<name>.imports` as a list is what lets `primary.nix` add `home-vscode.nix`;
  the VS Code activation appears on `primary` and not on `mini`.
- The `visual-studio-code` cask moved to `primary.nix` and is absent from `mini`.
- `crew-sandbox.darwinModules.default` is applied to both hosts, and the merged
  launchd `serviceConfig` carries the PATH override with `Label`
  `org.nixos.crew-sandbox-proxy`.
- `homeConfigurations."agent@aarch64-linux"` still evaluates, and `extraPackages` is
  the option the upstream guest module expects.
- The deleted `broker-ruleset.json` is byte-identical to the pinned
  `verify/gates/broker-ruleset.json`.
- The deleted `egress-allow` / `repos-allow` differ from the pinned `.example` files
  only in the header comment — so C1 is a capability loss, not a behaviour change.
- `rebuild.sh`'s new `case` guard is correct and its error message is clear.
- `./.githooks/check --all` passes, including the new two-host evaluation loop.
