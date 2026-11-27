# Host split + crew-sandbox extraction: architecture review

Reviewed 26 November 2026. Change set: the staged diff on `main` at `8b6b86b`
(33 files, +396 / −2506). Two things happen in one wave:

1. **Host split.** One `darwinConfigurations.${identity.host}` becomes two named
   configurations, `primary` and `mini`, built by a shared `mkDarwin` helper.
2. **crew-sandbox extraction.** The in-repo `nix/crew-sandbox/` tree (~2400 lines:
   Lima definition, proxy, broker, gates, allowlists) is deleted and replaced by a
   pinned flake input, `github:aditya-sathish-rao/crew-sandbox/v0.1.0`.

Companion: [`host-split-code-review.md`](host-split-code-review.md) — the line-level
findings. This file is about shape, seams, and what the change makes hard later.

> **On the requested skills.** There is no `matt pocock` skill installed on this
> machine — I searched `~/.agents/skills`, `~/.claude/skills`, `~/.copilot`, and
> `~/.vscode/agent-plugins`. What is installed is the `engineering-principles`
> bundle (the pstack set, vendored under `software-engineering-principles/`) plus a
> `typescript-setup` plugin skill. I applied the engineering-principles leaves and
> name each one that changed a decision in §6. If "matt pocock" means a specific
> external skill, it needs installing before it can be applied.

---

## 1. How this was checked

Not read-only. Every claim below was reproduced against the tree or the pinned input.

| Check                    | Command                                                                                               | Result                                                                                                                      |
| ------------------------ | ----------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------- |
| Both hosts evaluate      | `nix eval --impure --raw .#darwinConfigurations.{primary,mini}.system.drvPath`                        | **pass**, two distinct drvs                                                                                                 |
| Repo gate                | `./.githooks/check --all`                                                                             | **pass** (statix, deadnix, shellcheck, taplo, selene, both-host eval)                                                       |
| VS Code moved correctly  | `nix eval .#darwinConfigurations.{primary,mini}.config.home-manager.users.<u>.home.activation`        | `primary` has `vscode-settings`, `mini` has none                                                                            |
| Casks split              | `nix eval .#darwinConfigurations.{primary,mini}.config.homebrew.casks`                                | `primary` 3 (incl. `visual-studio-code`), `mini` 2                                                                          |
| Services on both hosts   | `nix eval .#darwinConfigurations.mini.config.services.crew-sandbox.enable`                            | `true`                                                                                                                      |
| Power settings           | `nix eval .#darwinConfigurations.{primary,mini}.config.power`                                         | all `null` on both                                                                                                          |
| Guest fleet              | `nix eval '.#homeConfigurations."agent@aarch64-linux".config.home.packages'`                          | `pi` + 8 crew-tools, **no `gh`**                                                                                            |
| Guest model endpoint     | `nix eval ...config.home.file.".pi/agent/models.json".source`                                         | `http://host.lima.internal:3130/model`                                                                                      |
| Merged launchd config    | `nix eval .#darwinConfigurations.primary.config.launchd.user.agents.crew-sandbox-proxy.serviceConfig` | PATH override applied, `Label` = `org.nixos.crew-sandbox-proxy`                                                             |
| Pinned input source      | `/nix/store/2dz0r98…-source` (rev `9e3dd9a`)                                                          | read `nix/modules/darwin.nix`, `nix/guest/`, `internal/lima/lima.yaml`, `verify/gates/check.sh`, `cmd/crew-sandbox/main.go` |
| Deleted data vs embedded | `diff` old `egress-allow`/`repos-allow`/`broker-ruleset.json` against the pinned input                | ruleset **byte-identical**; allowlists differ only in header comment                                                        |

**Not run:** `crew-sandbox check model` / `check broker` (need vault approval and a
real App key), and any `rebuild.sh` activation. Findings that depend on those are
marked as read-from-source, not observed.

---

## 2. Verdict

The **shape** is right and it is the shape the plan argues for. Two named hosts, one
builder, a host file that is a seam rather than a stub, and the sandbox moved to a
pinned input instead of living as 2400 lines of bespoke shell in a dotfiles repo.
Both configurations evaluate, the repo's own gate passes, and the VS Code move is
clean and provable. That is a real improvement over `darwinConfigurations.${identity.host}`.

The **content** is one item deep. `mini.nix` is imports-only, so today `mini` is a
full desktop configuration minus VS Code — wezterm, the Automic Vault cask, macOS
dock/finder/trackpad defaults, nerd fonts, the no-mistakes daemon, the firstmate
links. The plan says Phase 2 is open, and that is honest. The risk is sequencing:
if the mini is provisioned before Phase 2 lands, it becomes a headless machine
carrying a desktop's configuration, and the "shared base" becomes the thing that
has to be untangled later.

The **extraction** traded a local data surface for a pinned one. Code moved out
correctly; **policy data moved out too, and nothing replaced it.** `crew-sandbox.nix`
sets neither `proxy.allowFile` nor `broker.reposAllow`, so the deployed proxy and
broker fall back to the allowlists compiled into the binary. The operator can no
longer widen egress or add a repository from this repo. That is the one finding I
would fix before anything else, because it is a security control that silently
became read-only.

| Severity | Count | Theme                                                                                                                                       |
| -------- | ----- | ------------------------------------------------------------------------------------------------------------------------------------------- |
| Critical | 0     | —                                                                                                                                           |
| High     | 4     | gate/service collision, lost policy surface, doc/code port drift, a documented command that cannot pass                                     |
| Medium   | 7     | duplicated host list, dead `identity.host`, `mini` claims a capability it cannot deliver, stale layout map, ADR drift, provider split-brain |
| Low      | 6     | dead specialArg, hardcoded system, duplicate `primaryUser`, PATH replace-vs-append, doc overstatement                                       |

---

## 3. What the change gets right

Worth stating, because these are the decisions a later reader will want to keep.

- **`mkDarwin` is one builder, not two copies.** `flake.nix:63-79` takes a host
  module and supplies the shared `specialArgs` and the shared module list. Adding a
  third machine is one line. This is the right seam.
- **`home-manager.nix` exists because darwin `specialArgs` stop at darwin modules.**
  The comment says so, and it is true: `identity` and `piPackage` have to be
  re-passed to reach `home.nix`. Encoding that in a module instead of in the flake
  is what lets a host file override the user wiring without editing `flake.nix`.
- **`users.<name>.imports` became a list.** That single change is what makes
  `primary.nix` able to add `home-vscode.nix` without touching the shared base.
  Small, load-bearing, correct.
- **VS Code is the proof, not the claim.** The cask, the settings render, and the
  activation all moved together, and the result is verifiable per host (§1). The
  plan's "Done: VS Code" section matches what the code does.
- **The extraction deleted rather than stubbed.** `principle-subtract-before-you-add`
  and `principle-migrate-callers-then-delete-legacy-apis` both point the same way:
  no compatibility shim, no `nix/crew-sandbox/` left as a forwarding layer. The
  ruleset file is byte-identical to the one that was deleted, so nothing was lost
  in the move.
- **The gate now evaluates every host.** `.githooks/check:196` fails CI when a host
  file stops evaluating, instead of failing on the machine it names. Right instinct
  (see A5 for the execution).

---

## 4. Findings

### A1 — The policy data surface was deleted and not replaced (High)

`crew-sandbox.nix:11-17` enables the services and sets `proxy.upstream`,
`proxy.keySecret`, and `broker.appID`. It sets **neither** `proxy.allowFile` **nor**
`broker.reposAllow`. Verified:

```console
$ nix eval --impure --json .#darwinConfigurations.primary.config.services.crew-sandbox.proxy.allowFile
null
$ nix eval --impure --json .#darwinConfigurations.primary.config.services.crew-sandbox.broker.reposAllow
null
```

The module's own option docs say what `null` means: _"Null uses the example compiled
into the binary, so a module that names nothing still enforces a boundary rather
than removing one."_ So the boundary holds — but the **only** way to change it is to
edit the crew-sandbox input and re-pin, or to pass a flag the module does not expose.

Before this change, `nix/crew-sandbox/egress-allow` and `repos-allow` were tracked
files in this repo. Adding a project meant adding a line. Now it means forking a
flake. The docs paper over this by linking to the upstream `.example` files as if
they were the live policy (`docs/README.md:342`, `:371`) — they are examples, and the
effective policy is the embedded copy.

**Why it matters:** this is the control that decides which hosts the crew can reach
and which repositories the broker will mint for. Making it read-only from the repo
that owns the machine is a capability regression in the security-critical direction.

**Fix:** keep the data here. Either point the options at tracked files:

```nix
services.crew-sandbox = {
  proxy.allowFile = ./crew-sandbox/egress-allow;
  broker.reposAllow = ./crew-sandbox/repos-allow;
};
```

or render them from a tracked list with `pkgs.writeText`, so the policy is reviewable
in this repo's diffs. Either way, the docs should link to _this_ repo's file, not the
upstream example.

### A2 — `check model` is now mutually exclusive with the deployed proxy (High)

The proxy and broker became launchd **user agents** that bind `3128` and `3130` at
login. The model gate refuses to run when either port is held
(`verify/gates/check.sh:456-459` in the pinned input):

```sh
if lsof -nP -iTCP:3128 -sTCP:LISTEN >/dev/null 2>&1 ||
  lsof -nP -iTCP:"$model_port" -sTCP:LISTEN >/dev/null 2>&1; then
  echo "model: port 3128 or ${model_port} is already in use; stop that service so this gate controls the key." >&2
  return 1
fi
```

So on any machine where the agent is running — which is now every machine, by
design — `check model` fails before it tests anything. `check proxy` degrades more
quietly: `start_keyless_proxy` sees the listener and reuses it
(`check.sh:411-415`), so the phase documented as "through a keyless proxy" actually
tests the keyed deployed one.

`docs/README.md:400-404` says _"the gates start temporary services only where
required and stop the services they started"_ — true of the gate, false of the
system it now runs against. The doc does not mention that you must
`launchctl bootout` the agent first.

**Why it matters:** the gate that proves the model key stays on the host is the one
gate you cannot run on the machine that holds the key. That is a design collision
between "services always run" and "gates control the key", not a bug in either half.

**Fix:** give the gate its own ports. `--port` and `--model-port` are already flags
on `crew-sandbox proxy`; the gate hardcodes `3128` and `$model_port`. Passing
`--port 3129x --model-port 3130x` (or a `CREW_PROXY_PORT` env the gate already
half-supports) lets the gate run beside the agent. Failing that, document the
`launchctl bootout` step in the same block that lists the commands.

### A3 — The model gateway moved to its own port; the docs did not (High)

The pinned proxy listens for the gateway on `--model-listen`, default **3130**, and
the pinned guest `models.json` points at `http://host.lima.internal:3130/model`.
Verified from the evaluated guest config. The old in-repo proxy served `/model` on
`3128`, and three doc sites still say so:

- `docs/README.md:361` — "points at `http://host.lima.internal:3128/model`"
- `GLOSSARY.md:266` — diagram: `egress proxy + model gateway 192.168.5.2:3128`
- `GLOSSARY.md:296` — "The same listener also carries the model gateway"
- `GLOSSARY.md:300` — "points its `deepseek` provider at `…:3128/model` through `guest/models.json`"

The last one is doubly wrong: `guest/models.json` no longer exists in this repo, and
the port is 3130. The split is deliberate upstream — the comment in `proxy.mjs` says
sharing the CONNECT socket "made the gateway a second egress door" — so the docs are
describing a design that was intentionally abandoned.

**Why it matters:** a reader debugging "the guest cannot reach the model" will check
the wrong port, and the glossary is the shared vocabulary the rest of the docs lean on.

**Fix:** 3130 in all four places, and say "a second listener, kept off the egress
socket" instead of "the same listener".

### A4 — A documented command cannot pass (High)

`docs/README.md:312` tells the operator to run:

```sh
nix run .#crew-sandbox -- check all --expected-tools "pi gh" …
```

The toolchain gate asserts each named tool resolves under `/nix/store`
(`verify/gates/toolchain.sh:50-60`). The guest fleet is `pi` plus the eight
`nix/crew-tools` artifacts — `gh-axi`, `chrome-devtools-axi`, `chrome-devtools-mcp`,
`lavish-axi`, `no-mistakes`, `quota-axi`, `tasks-axi`, `treehouse`. **`gh` is not
among them**, and `lima.yaml` installs only `nftables curl dnsutils` via apt.
Verified:

```console
$ nix eval --impure --json '.#homeConfigurations."agent@aarch64-linux".config.home.packages' \
    --apply 'ps: builtins.filter (p: builtins.match ".*gh-[0-9].*" (baseNameOf p) != null) ps'
[]
```

So `check all` fails on the toolchain phase, on a command the docs present as the
one-liner. The upstream README uses `"pi gh"` because its example consumer ships
`gh`; this repo does not.

**Why it matters:** the first command a new operator runs fails, and the failure
looks like a broken sandbox rather than a wrong flag.

**Fix:** `--expected-tools "pi gh-axi"` (or the full eight), and decide separately
whether the guest should have `gh` at all — the broker exists precisely so it does
not need one.

### A5 — The host list is duplicated in three places (Medium)

`flake.nix:129-131` owns the list. `.githooks/check:196` hardcodes it:

```sh
for host in primary mini; do
```

and `rebuild.sh:11-12` hardcodes it again in the `case`. Adding a third machine
means three edits, and the failure mode is silent: a new host file that does not
evaluate passes CI because the loop never names it.

**Fix:** derive it. This works today:

```console
$ nix eval --impure --json .#darwinConfigurations --apply builtins.attrNames
["mini","primary"]
```

Use that in the hook, and validate `rebuild.sh`'s `$HOST` against the same list
instead of a literal `case`.

### A6 — `identity.host` is vestigial (Medium)

`identity.nix:15-19` still computes `host` from `AGENTIC_DEV_ENV_HOST` (falling back
to the login name) and exports it at `:29`. Nothing consumes it: `grep -rn
'identity\.host' --include='*.nix'` returns nothing, and `flake.nix` no longer keys
`darwinConfigurations` on it. `rebuild.sh` owns host selection now.

Two docs still describe the old meaning:

- `docs/host-split-plan.md:13` — "`identity.host` comes from `AGENTIC_DEV_ENV_HOST`"
  (true of the file, false of the system)
- `GLOSSARY.md:93` — "The `darwinConfigurations` attribute the flake builds, taken
  from `AGENTIC_DEV_ENV_HOST`" — the flake builds a fixed `{primary, mini}`;
  the variable only _selects_ which one `rebuild.sh` builds.

**Why it matters:** a dead field that looks live is worse than no field. The next
reader will assume `AGENTIC_DEV_ENV_HOST` still steers evaluation, and it does not.

**Fix:** delete `host` from `identity.nix` and the `AGENTIC_DEV_ENV_HOST` export in
`rebuild.sh` (keep the variable as `rebuild.sh`'s own input), then correct the two
doc lines. `principle-subtract-before-you-add`: remove before the next host lands.

### A7 — `mini` enables launchd user agents it cannot start (Medium)

`crew-sandbox.nix` is imported by both host files, so `mini` gets
`services.crew-sandbox.enable = true` (verified). The module's own header explains
why that cannot work on a headless host: the services are **user agents**, they start
with a GUI login, and the vault answers an unattended read with "human approval
required". On a mini with FileVault on, nobody logs in after a reboot, so neither
service starts.

The plan says this (`docs/host-split-plan.md:107-111`, Phase 3) and the module
comment points at the plan. The **code** does not express it: `mini.nix` looks like a
working configuration and is not one.

**Why it matters:** a configuration that claims a capability it cannot deliver is
discovered at 3am, not at review time.

**Fix:** until Phase 3 lands, either gate the enable on a per-host flag
(`services.crew-sandbox.enable = lib.mkDefault false;` in `mini.nix` with a comment),
or add an `assertions` entry that fails evaluation when `mini` enables the services
without a headless strategy. `principle-encode-lessons-in-structure`: the plan text
is the symptom; the assertion is the fix.

### A8 — The layout map no longer describes the tree (Medium)

`docs/README.md:462-473` is the file map, and it is the primary navigation aid. It
now:

- says `home.nix` owns "rendered VS Code settings" (`:472`) — that moved to
  `home-vscode.nix`
- omits `primary.nix`, `mini.nix`, `home-manager.nix`, `home-vscode.nix`,
  `crew-sandbox.nix`, and `docs/host-split-plan.md`

The `crew-sandbox` input entry was added correctly (`:462-463`), so the extraction
half of the map is right and the host-split half is missing.

**Fix:** add the six files with one-line ownership notes, and move the VS Code phrase
to `home-vscode.nix`.

### A9 — ADR-0010 now states two things that are false (Medium)

The diff edits `docs/adr/0010-crew-runs-in-one-vm.md:31` to point at the pinned Lima
definition, and leaves the two claims beside it:

- `:32` — "`mounts: []`, `portForwards: []`". The pinned `lima.yaml` has a one-entry
  `ignore` rule, not `[]`. (The old file had the same rule, so this was already
  wrong — but the line was edited in this diff and the claim was not corrected.)
- `:38` — "one host port out, reserved for the egress proxy". It is now **two**
  ports: `3128` (egress) and `3130` (model gateway), both opened in the guest's
  nftables output chain.

**Why it matters:** an ADR is the security record. A reader auditing "what can the
guest reach" gets the wrong answer from the document that is supposed to be
authoritative.

**Fix:** correct both lines in the same commit that changes the definition they
describe.

### A10 — Provider split-brain between host and guest (Medium)

The host fleet moved to OpenRouter (`home/.pi/agent/settings.json`:
`defaultProvider: "openrouter"`; `mate` and `home/.local/bin/pi` inject
`OPENROUTER_API_KEY`). The guest fleet is still DeepSeek: `crew-sandbox.nix:14-15`
sets `proxy.upstream = "https://api.deepseek.com"` and
`proxy.keySecret = "DEEPSEEK_API_KEY"`, and the pinned guest `models.json` hardcodes
a provider named `deepseek`.

So the mate on the host and the crew in the VM run on different providers, different
keys, and different failure modes. That may be deliberate — the guest on a cheaper
provider is a reasonable choice — but nothing in the plan or the code says so.

**Why it matters:** if it is deliberate, it needs one sentence in
`docs/host-split-plan.md` so the next reader does not "fix" it. If it is not, the
guest is on the provider the host abandoned, and the pinned guest module hardcodes
the provider name, so switching needs an upstream change or a local override of
`~/.pi/agent/models.json`.

**Fix:** decide, then write it down. If the guest should follow the host, the guest
module needs the provider name as an option rather than a hardcoded `deepseek`.

### A11 — Low-severity shape notes

- **`piPackage` is a dead specialArg in `mkDarwin`** (`flake.nix:69`). Only
  `home.nix` uses it, and it arrives through `home-manager.nix`'s
  `extraSpecialArgs`. No darwin module reads it. Drop it from `mkDarwin`.
- **`crew-sandbox.packages.aarch64-darwin.default` is hardcoded**
  (`crew-sandbox.nix:13`) while `flake.nix:102` uses `packages.${system}.default`.
  The module's own `defaultText` says `${system}`. On an Intel host this breaks; the
  plan already lists `builtins.currentSystem` as an open question, so this is the
  same limitation expressed twice.
- **`system.primaryUser` is set twice** — `configuration.nix:36` and
  `crew-sandbox.nix:9`, both to `identity.username`. Harmless, but two owners for one
  value is how they drift.
- **The PATH override replaces rather than appends** (`crew-sandbox.nix:24-25`).
  It is the right fix — `av` lives at `/usr/local/bin/av` and launchd's default PATH
  omits it — but it discards whatever else launchd would have provided. The module's
  wrapper already prepends its own packages, so this only needs to _add_
  `/usr/local/bin`.
- **`check all` excludes `headless`** (verified in the pinned `check.sh:603-611`),
  but `docs/README.md:406` says it "runs every phase". Say "every guest phase".

---

## 5. Sequencing

The plan's own phase order is right. What I would change is what lands _before_ the
mini exists.

1. **A1 first.** Restore the allowlist data surface. It is the only finding that
   weakens a security control, and it is a five-line change.
2. **A2 and A4 next.** Both are "the documented workflow does not work". They cost
   an operator an afternoon each and they are cheap to fix.
3. **A3, A8, A9, A6.** Doc and dead-code corrections. One commit, no behaviour change.
4. **A5.** Derive the host list before a third host makes the duplication expensive.
5. **A7 before the mini is provisioned.** An assertion, not a comment.
6. **Phase 2 of the plan** (move primary-only items out of the shared base) before
   the mini is provisioned, or the mini inherits a desktop.
7. **A10** whenever the provider question is settled.

---

## 6. Principle ledger

Each principle below was read this session from
`~/.agents/skills/software-engineering-principles/`, and each changed a decision in
this review.

| Principle                                           | What it changed                                                                                                                                                                                                         |
| --------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `principle-subtract-before-you-add`                 | Made A6 (`identity.host`) and A11 (`piPackage`) findings rather than nits: dead fields and dead args are removed _before_ the next host lands, not after. Also endorsed the extraction's delete-don't-stub shape in §3. |
| `principle-migrate-callers-then-delete-legacy-apis` | Same wave, no shim: I checked that `nix/crew-sandbox/` was deleted rather than left forwarding, and that the ruleset file survived byte-identical. That check is why §3 credits the extraction.                         |
| `principle-boundary-discipline`                     | Framed A1 as a boundary question: the allowlist is data crossing from operator policy into a service, so it belongs at the boundary this repo owns, not compiled into a binary.                                         |
| `principle-type-system-discipline`                  | Framed A5 and A6 the same way: the host name is an external input (env var) that should be parsed once into a closed set, not re-encoded as a literal `case` and a literal `for` loop.                                  |
| `principle-encode-lessons-in-structure`             | Turned A5 and A7 from "add a comment" into "derive the list" and "add an assertion". The plan text describing Phase 3 is the symptom; the assertion is the fix.                                                         |
| `principle-prove-it-works`                          | §1 exists because of this: every claim is a command and its output, not a reading of the diff. It is also why A4 is High — I ran the filter and got `[]`.                                                               |
| `principle-attack-the-premise`                      | A2 is the premise test: the change assumes "services run always" and "gates control the key" can coexist. They cannot on one port, and the gate's own error message says so.                                            |
| `principle-minimize-reader-load`                    | A8 and A9: the layout map and the ADR are the two places a reader goes to answer "where does X live" and "what can the guest reach". Both now cost more than 30 seconds.                                                |

**Where two principles pulled against each other:** `principle-subtract-before-you-add`
argues for deleting `nix/crew-sandbox/` outright, which the change did;
`principle-boundary-discipline` argues the _policy data_ in that tree was a boundary
this repo owns. I resolved it by keeping the deletion (code) and flagging the data
loss (A1) — subtraction was right for the code and wrong for the allowlists.
