# agentic-dev-env

macOS dev environment as code: [nix-darwin](https://github.com/nix-darwin/nix-darwin) and
[home-manager](https://github.com/nix-community/home-manager) for everything declarative,
Homebrew for GUI apps. Config files stay in this repo and are linked into place, so most
edits need no rebuild.

## What you get

- **Packages** (nix): ripgrep, fd, fzf, jq, lazygit, neovim, Hack Nerd Font, the agent
  harness `pi` (from its own flake input), the Swift linters `swiftlint` and
  `swift-format` (both run with `--strict`), and the formatters and linters the hook runs:
  nixfmt, shfmt, stylua, prettier, taplo, statix, deadnix, shellcheck, selene.
- **Apps** (homebrew): wezterm, Visual Studio Code, herdr, Node, Automic
  Vault (`av`, which holds every secret this machine needs), and the
  `automic-vault/isotopes/gh-cli` isotope that `av harden gh` installs.
- **Shell**: zsh with autosuggestions and syntax highlighting, starship prompt, git
  aliases, `mate` for the crew, and `~/.local/bin` on `PATH` (exported
  from `.zshrc`, because macOS `path_helper` rewrites `PATH` after `.zshenv`).
- **Configs**: wezterm, neovim, herdr, VS Code (font, terminal font, formatters), pi's
  agent directory (`~/.pi/agent/settings.json` is generated from `personal.nix` and owns the
  default model, `AGENTS.md` the global instructions), the user-level skills under
  `~/.agents/skills` and `~/.claude/skills` (the engineering principles and the pstack set
  among them), `~/.config/git/config` (resets Apple's ambient credential helper) and
  `~/.ssh/config` (Keychain-backed key).

Config files under `home/` are edited in place in the repo and linked into `$HOME`, so an
edit needs no rebuild. `~/.config/git/config` is generated instead, because its content is
written from `home.nix`. The model files (`~/.pi/agent/settings.json`,
`~/firstmate/config/crew-dispatch.json` and the two supervision pins) are generated from
`personal.nix` for the same reason: the model is declared once. VS Code's `settings.json`
goes the other way: it is seeded once from `home/.config/vscode/settings.json` as a real file
and then owned by VS Code, because its atomic saves cannot write through a link into the
read-only store. Delete the file and run `./rebuild.sh` to restore the defaults. See
[ADR-0008](docs/adr/0008-vscode-owns-its-settings.md).

### Your personal values: `personal.nix`

Everything personal about this machine lives in one gitignored file at the repo root:
`personal.nix`. Copy `personal.nix.example` and edit it. It holds the model and provider every
agent starts on, the thinking levels, the supervision pin, the _name_ of the vault secret
holding the model key, the upstream the host proxy forwards to, the GitHub App id, and the
firstmate fork. A secret's name goes there; its value goes in Automic Vault.

`nix/personal.nix` is the tracked loader. It merges your file over generic defaults, so a
clone without `personal.nix` still evaluates, and it hands the result to every module as
`personal`. Because the file is untracked, a flake in a git repo cannot see it as a tracked
file; `rebuild.sh` and `.githooks/check` export its absolute path as
`AGENTIC_DEV_ENV_PERSONAL`, and the loader imports it from there.

Terms used below are defined in [GLOSSARY.md](GLOSSARY.md).

## Setup from scratch

Needs a macOS machine (Apple Silicon or Intel) and an admin user. Nothing in the tree
hardcodes that user: `identity.nix` reads the identity from the environment when the flake
is evaluated, and the host platform comes from the machine. See [Adapting](#adapting) if
the defaults do not fit.

```sh
git clone https://github.com/aditya-sathish-rao/agentic-dev-env.git ~/github/agentic-dev-env
cd ~/github/agentic-dev-env
./rebuild.sh             # primary by default; --mini on the headless Mac mini
```

`rebuild.sh` is the only entry point, and it is idempotent. With no flag it builds `primary`,
so a bare `./rebuild.sh` is right on the Mac you sit at; the mini passes `--mini`. On a fresh machine and on an
existing one it does, in order:

1. Checks the Xcode command line tools. If they are missing it starts the installer and
   stops, so run it again when that finishes.
2. Links the clone to `~/.agentic-dev-env`, so every config path resolves through one
   place and the clone can live anywhere. It refuses to nest when `~/.agentic-dev-env` is
   already a real directory.
3. Sets `core.hooksPath` to `.githooks`.
4. Installs [Determinate Nix](https://determinate.systems/nix) if `nix` is missing.
5. Builds as the user who ran it: `nix build --impure`.
6. Activates as root: `sudo nix-env --set`, then `sudo $SYSTEM/activate`. Expect one
   `sudo` prompt. See [ADR-0004](docs/adr/0004-build-as-user-activate-as-root.md).

The flake is evaluated impurely, so the darwin configuration belongs to whoever runs the
script. Homebrew itself, then every brew and cask, is installed by this activation.

Home-manager runs last, so a failure before it leaves the system switched but the user links
untouched. `home-manager.backupFileExtension = "hm-bak"` in `flake.nix` keeps the common case
from stopping it: a plain file at a managed path (an old generated `~/.config/git/config`, say)
is moved to `<path>.hm-bak` instead of aborting every link.

After it finishes, open a new terminal. The Automic Vault steps below are the part that
cannot be automated, and the crew adds one more in [Crew](#crew): store its key. Everything
else the crew needs, firstmate's checkout included, is installed by `./rebuild.sh` itself.

## Day to day

```sh
./rebuild.sh             # apply config changes (--mini on the mini)
```

Most edits need no rebuild at all, because config files are linked into the repo. Generated
files are the exception: a VS Code settings change needs `./rebuild.sh`, and
`~/.config/git/config` is edited in `home.nix`.

The agent harness moves with the flake, so a pi release is `nix flake update pi` and then
`./rebuild.sh`. Do not run `pi update pi`: the installed copy lives in the store and cannot
update itself.

## Manual steps

These are the steps Automic Vault only lets a human do, once per Mac, after `./rebuild.sh`.
They are not automated.

1. **Start the app.** Homebrew installs the bundle but nothing launches it, and every `av`
   command that needs Approval fails with `approval service is not running` until the
   menu bar app is up:

   ```sh
   open -a "Automic Vault"
   ```

   Grant the permission prompts it shows (notifications; Keychain access for the Data
   Protection Keychain that stores the secrets). Leave it running.

2. **Install the `av` CLI.** The cask ships `av` inside the bundle; the copy on `PATH` is
   installed by the app: **Install av CLI** (it authenticates as admin and writes a
   root-owned `/usr/local/bin/av`). It refuses to install into a directory the user owns,
   so if `/usr/local/bin` is user-owned, fix that first and click Install again:

   ```sh
   sudo chown root:wheel /usr/local/bin
   ```

3. **Store the model key.** The name is `model.keySecret` in `personal.nix`; the example
   uses `MODEL_API_KEY`.

   ```sh
   av save MODEL_API_KEY   # hidden input, then approve the prompt
   ```

   This key now lives only in Automic Vault and reaches every agent through `av inject`.

4. **Let the terminal inject it.** Until the terminal is granted access, `av inject` asks
   for Approval on every launch. In the app: select `MODEL_API_KEY` →
   **Allow Launcher** → WezTerm. After that `mate` starts with no prompt.

5. **Harden `gh`.** The isotope is declared in `configuration.nix`, but the isotope alone
   does not migrate or gate anything, so run the hardener:

   ```sh
   av harden gh
   av doctor gh   # should report healthy
   ```

   Then delete the legacy `github.com` Internet password item in Keychain Access, so
   nothing can read that token directly.

6. **Encrypt the SSH key.** `av scan` reports `~/.ssh/id_ed25519` as a HIGH finding while
   it has no passphrase, and only you can type the new one:

   ```sh
   ssh-keygen -p -f ~/.ssh/id_ed25519
   ssh-add --apple-use-keychain ~/.ssh/id_ed25519
   ```

   `~/.ssh/config` is managed with `AddKeysToAgent`/`UseKeychain`, so the passphrase is
   stored in the macOS Keychain once and push/pull keep working without retyping it.

## Crew

Talk to one agent, ship with a crew. `mate` starts the first mate: pi inside a checkout of
your [firstmate](https://github.com/kunchenguid/firstmate) fork at `~/firstmate`. It splits a
request into parallel tasks and spawns one crewmate per task into its own herdr tab and git
worktree. Everything runs the same harness, pi, on one configured model.

```sh
./rebuild.sh   # clones firstmate at the recorded commit, installs the crew's tools
mate
```

What is declared here, and where:

- `pi` is a flake input ([flake.nix](flake.nix), pinned by `flake.lock`) and the only agent
  harness here. Its package ships its own Node runtime and model catalog, so no global npm
  install is involved and the harness version moves only when the lock does.
- `personal.nix` is the single source for the model, provider, key secret, proxy upstream,
  GitHub App id and firstmate fork. `nix/personal.nix` merges it over generic defaults.
- `~/.pi/agent/settings.json` is generated from `personal.nix` and owns the model every agent
  starts on: `defaultProvider`, `defaultModel`, `defaultThinkingLevel`. To try a different
  model, edit `personal.nix` and run `./rebuild.sh`. It is generated rather than linked
  because pi writes `lastChangelogVersion` into it.
- `~/firstmate/config/crew-dispatch.json` is generated too. It declares one profile,
  `{ "harness": "pi", "provider": "<provider>" }`, and deliberately omits the model, so
  crewmates inherit the same `settings.json` default. With `shared_quota: true` the
  `quota-array-dispatch` skill resolves the declared profile in order and makes no quota
  call: there is one provider and one budget.
- `supervision-branch-model` and `-effort` are generated into the same `config/`. They pin
  the supervision branch, the second conversation that triages fleet wakes beside the
  captain's chat, to the `model.supervision` values at `low` effort while the captain keeps
  `settings.json`'s `high`. Routine triage is cheap, and anything captain-worthy still
  reaches main, which keeps the full effort. Fleet polling never reaches a model at all: the
  bash watcher blocks on herdr's event stream, absorbs benign wakes itself, and wakes the
  branch only for a real transition or decision. A pin applies when the next `mate` session
  opens; `/supervision-model` rewrites these files in place, so run `./rebuild.sh` after
  using it to put the declarative pins back.
- `mate` selects the herdr backend for the launch and injects the `model.keySecret` secret
  into the first mate only. Crewmate panes come from a herdr server that never saw the key,
  so the wrapper below injects it per crewmate.
- `home/.local/bin/pi` shadows the harness with a thin wrapper. A crewmate pane starts with
  no model key, so the wrapper reads the secret's name from
  `~/.config/agentic-dev-env/model-key-secret` (generated from `personal.nix`) and re-runs
  itself under `av inject`; each worker holds the key only for its own lifetime, and if av
  fails the launch stops instead of running signed out. Probes that cannot use a key
  (`--help`, `--version`, `--list-models`, `auth`, `update`) pass straight through, so
  firstmate's version detection never waits on a vault approval.

### What a rebuild automates, and what stays manual

`./rebuild.sh` automates the harness, the crew's tools and the wiring:

- **firstmate**, cloned over HTTPS at the commit recorded in
  [home/firstmate/expected-commit](home/firstmate/expected-commit) _before_ anything links
  into it. The clone-before-rebuild step is gone: activation always finds a repository.
- **the crew's CLIs** from [nix/crew-tools](nix/crew-tools): the five `-axi` CLIs,
  `chrome-devtools-mcp`, `treehouse` and `no-mistakes`, each built from its published artifact
  and pinned by hash, plus `nodejs_24` - the one runtime they all run on.
- **the no-mistakes daemon**, declared as a `launchd.agents` entry that points at the store
  binary, so bumping the tool moves the daemon with it.
- the generated model files (`~/.pi/agent/settings.json`,
  `~/firstmate/config/crew-dispatch.json` and the two supervision pins) and the
  `~/.pi/agent/AGENTS.md` link, `~/.local/bin` on `PATH`, and the `mate` alias in the
  generated `.zshrc`.

Homebrew no longer prunes, so the `claude-code` cask from the old harness survives a
rebuild: `brew uninstall --cask claude-code` once. The `opencode` package needs nothing,
because it came from nix and activation replaces the profile.

Nothing installs a crew tool with `npm install -g` or `curl | sh` any more. The versions live
in one data file, [nix/crew-tools/pins.nix](nix/crew-tools/pins.nix), and the binaries come
from the Nix store. `~/firstmate/bin/fm-bootstrap.sh` still lists missing tools as `MISSING:`,
but that is upstream text: if it ever fires, the fix is `./rebuild.sh`, not the npm or curl
command it suggests.

firstmate itself is the one tree this repo does not own outright. It updates itself with
`/updatefirstmate`, so a rebuild reports an existing checkout's HEAD against the recorded
commit and never moves it. It clones from the fork `aditya-sathish-rao/firstmate`, with
upstream as a second remote. A firstmate bump is a review, not a fetch: read the upstream
diff, merge it into the fork, then update `home/firstmate/expected-commit`.

A new machine needs these steps, in this order:

1. **`./rebuild.sh`** - pi, herdr, firstmate, the crew's pinned tools, Node, the daemon, the
   links, `~/.local/bin` on `PATH`, `mate`.
2. **Store the key and allow the launcher** (below). `mate` injects it into the first mate,
   and the pi wrapper into each crewmate.
3. **Check `gh`.** Dispatching clones projects and opens PRs, so `av doctor gh` must report
   healthy on this machine's hardened `gh-cli` isotope before `mate` can do anything.
4. **Run `mate`.** The first launch reports anything still missing as `MISSING:` and asks
   before installing or upgrading it.

#### Bumping a crew tool

Do not edit `pins.nix` by hand. Run the one writer:

```sh
./nix/crew-tools/update.sh gh-axi 0.1.52   # or with no version, the latest that passes
```

It refuses a version published less than 14 days ago, cross-checks the release assets against
the publisher's own `checksums.txt`, audits the npm signatures for the lock it generates,
prints the lock diff, and refetches both hashes. Review the diff, then
`./.githooks/check --all` and `./rebuild.sh`.

The pins this machine runs: gh-axi 0.1.51, chrome-devtools-axi 0.1.46, tasks-axi 0.2.6,
quota-axi 0.1.69, lavish-axi 0.1.97, chrome-devtools-mcp 1.13.0, treehouse 3.1.8,
no-mistakes 1.106.1, node 24.22.1.

`treehouse update`, `no-mistakes update` and the `-axi` update subcommands try to replace
their own read-only store binary and fail. The bump path is the command above.

The three `-axi setup hooks` lines are not part of setup any more: they install SessionStart
hooks for Claude Code, Codex, OpenCode and Copilot CLI, and pi reads skills instead, getting
the same guidance from the `lavish` skill under `~/.agents/skills`. Run them by hand only if
you also drive one of those harnesses.

#### Removing the old copies, after a soak

`~/.local/bin` comes first on `PATH` and still holds the treehouse and no-mistakes installers,
while the five axi CLIs sit in `/opt/homebrew/bin`. Until those are deleted they shadow the
pinned ones, so deletion is deliberately separate from the switch. Once `command -v` has been
returning profile paths for a week:

```sh
npm uninstall -g gh-axi chrome-devtools-axi tasks-axi quota-axi lavish-axi
rm -f ~/.local/bin/treehouse ~/.local/bin/no-mistakes
rm -rf ~/.no-mistakes/bin
```

Then confirm every tool resolves into the profile, not the old locations:

```sh
for t in gh-axi chrome-devtools-axi tasks-axi quota-axi lavish-axi treehouse no-mistakes; do
  printf '%s\t%s\n' "$t" "$(command -v "$t")"
done
```

Every path should sit under `/etc/profiles/per-user/<user>/bin`. The daemon's own state in
`~/.no-mistakes` is untouched by all three commands.

Save the key once, as in [Manual steps](#manual-steps) step 3. The name is
`model.keySecret` in `personal.nix`:

```sh
av save MODEL_API_KEY
```

Then allow the launcher for it, as in step 4.

## Sandbox

Worktrees isolate git state, not authority. A crewmate runs as you: your files, your `gh`
token, your network. The boundary is one Linux VM around the fleet, declared here like
everything else.

[`crew-sandbox` v0.1.0](https://github.com/aditya-sathish-rao/crew-sandbox) defines that VM:
Lima on Apple's `vz` driver, Ubuntu 26.04 LTS pinned by image digest. This flake consumes
its CLI and guest/host modules; the guest fleet is passed from this repository.

```sh
nix run .#crew-sandbox -- up               # create it on first use, then start it
nix run .#crew-sandbox -- run -- <command> # run a command as agent in the guest
nix run .#crew-sandbox -- check guest      # verify the guest boundary
nix run .#crew-sandbox -- check proxy      # phase 3a: the egress proxy
nix run .#crew-sandbox -- check model      # phase 3a-2: the model key stays on the host
nix run .#crew-sandbox -- check toolchain  # phase 2: the guest's tools
nix run .#crew-sandbox -- check broker     # phase 3b: one repo, one token, revocable
nix run .#crew-sandbox -- check all --expected-tools "pi gh" \
  --model-upstream https://api.example.com --model-key-env MODEL_API_KEY \
  --app-id 5853565 --other-repo aditya-sathish-rao/agentic-dev-env
nix run .#crew-sandbox -- down              # stop the VM and revoke broker tokens
nix run .#crew-sandbox -- destroy           # delete the guest and its disk
```

The proxy and broker run as launchd user agents after the Darwin configuration is
activated. The CLI has no `shell`, `apply`, `kill`, or `ruleset` subcommands: use
`run -- <command>` for guest commands, follow the upstream README's guest-configuration
steps, and apply the GitHub ruleset manually from the
[pinned ruleset file](https://github.com/aditya-sathish-rao/crew-sandbox/blob/v0.1.0/verify/gates/broker-ruleset.json).

What the definition and the two host services guarantee, and what each gate re-proves:

- **Nothing from `$HOME` is mounted, and nothing the guest listens on reaches the host.**
  `mounts: []`, no agent forwarding, and an `ignore` port-forward rule over the whole range.
  That rule is not decoration: `portForwards: []` does **not** disable Lima's forwarding. The
  host agent always appends a fallback that publishes every listener inside the guest on the
  host's own `127.0.0.1`, on the same port, for TCP and UDP alike, and it dials the guest
  through the guest agent rather than the network, so the guest's input chain never sees the
  connection — any crewmate could have put a service on the operator's loopback with one
  command. `check box` starts a listener as `agent`, bound both to `0.0.0.0` and to
  `127.0.0.1`, and fails if the host loopback answers. The only host-to-guest channel left is
  SSH, which `limactl shell` uses.
- **Agents get no root.** `agent` is created without sudo and in no privileged group, so
  `sudo -n true`, `nft flush ruleset` and writing `/etc/nftables.conf` all fail.
- **Egress is default-deny, and one allowlist wide.** One root-owned nftables table drops
  everything except SSH from the host subnet and one port on the host. That port is
  `crew-sandbox proxy`: a CONNECT proxy holding no credentials, which refuses any destination
  [the pinned egress allowlist](https://github.com/aditya-sathish-rao/crew-sandbox/blob/v0.1.0/internal/allowlist/egress-allow.example) does not name, and allows
  exactly two shapes of traffic to a named host: a TLS tunnel on 443 and a plain request on 80. DNS is closed with the rest of the internet rather than left open as
  a covert channel. The proxy binds `127.0.0.1`, which the guest reaches at `192.168.5.2`
  because Lima forwards loopback to the guest's gateway, so nothing is exposed to the LAN.
- **The allowlist names hosts, and the proxy enforces the name.** An allowlisted destination
  is not enough on its own, because one CDN address can serve thousands of unrelated sites.
  So over plain HTTP the proxy discards the guest's `Host` and sets it from the destination,
  and over TLS it reads the server name out of the ClientHello and refuses a tunnel whose SNI
  is not the name that was allowed; `CONNECT` is refused on port 80, where that check cannot
  see anything. A wildcard entry therefore grants the subdomains it names and nothing else.
  `check proxy` proves both halves against a host that is off the allowlist and shares a CDN
  address with one that is on it, and `proxy.mjs --selftest` proves the parser without a
  network. The residual limit is honest: TLS content is opaque to a CONNECT proxy, so the
  guarantee is that a guest can only reach allowlisted _hostnames_, not that it can only send
  them ordinary traffic. A client that skips certificate validation can present an allowed
  SNI and a different inner `Host`; closing that would require terminating TLS inside the
  proxy, which the model gateway exists to avoid.
- **No agent holds the model key.** pi 1.5.2 can point a built-in provider at another
  endpoint through `models.json`, so the guest does not need a TLS-terminating proxy. Its
  configured provider points at `http://host.lima.internal:3128/model`, a gateway route on
  the same host proxy. The guest presents a random token created inside the VM
  (`/etc/crew-model-token`), and only the host proxy process ever holds the real
  `MODEL_API_KEY`, injected from the vault when the host proxy agent starts. The gateway
  strips the guest's `Authorization` header, adds the real one, forwards only `GET /models`
  and `POST /chat/completions` to the upstream set in `crew-sandbox.nix`, and refuses the
  route when either half is missing. `check model` proves a request without the token is
  refused, a request with it reaches the API, and no environment value in the guest is the
  real key.
- **No agent holds a GitHub credential.** `crew-sandbox broker` mints one App installation
  token per task, for one repository from the
  [pinned repository allowlist](https://github.com/aditya-sathish-rao/crew-sandbox/blob/v0.1.0/internal/allowlist/repos-allow.example),
  with `contents` and `pull_requests` only. GitHub refuses a token for anything outside the
  App's installation, so the scope survives a compromised caller. The App private key stays
  in the vault and is injected at start with `av inject`, never written to disk.
  `check broker` runs on the host without the VM. It asserts two opposite things, and both
  must hold: the token **can** create an `agent/gate-*` branch and write to it, and the
  **default branch refuses** the same token. The second half is the point. A
  `contents: write` token that could write the default branch could also merge its own pull
  request, so the human-merge backstop would not exist.
  [the pinned broker ruleset](https://github.com/aditya-sathish-rao/crew-sandbox/blob/v0.1.0/verify/gates/broker-ruleset.json)
  is that backstop: a repository ruleset requiring one approving review, a fresh approval
  after the last push, resolved threads, and no force-push or deletion, with an empty
  `bypass_actors` list so the App is not exempt. Apply it with
  by applying that file to the repository; the new CLI has no ruleset-application command.
  The gate fails, naming the ruleset, when it is missing. Binding a token to the task
  that asked is the one 3b item left: it needs the spawn path that moves in with phase 4,
  which is what knows each task's repository.
- **A kill switch stops, then revokes.** `crew-sandbox down` stops the VM first and only then
  asks a running broker to revoke every token it issued. The order is the point: while the
  broker is unauthenticated (C1), revoking first leaves a window where a crewmate mints a
  fresh token after the sweep and outlives it. With the guest down nothing can ask, so the
  revoke sweeps a set that can no longer grow. A failed stop does not skip the revoke: the
  failure is reported, the revoke still runs, and the command exits non-zero because either
  half alone leaves a credential alive. Tokens are kept in the broker's memory only, so a
  broker restart also strands them.
- **Bootstrap cannot reopen any of it.** Lima re-runs provision scripts on every boot, so the
  script touches `/etc/crew-provisioned` and exits early next time, when there is no network
  left to install from.

The VM is replaced, not patched: change its definition in the pinned `crew-sandbox` input,
then `destroy` and `up`, and run the gate against the new one. `crew-sandbox` is deliberately
not in `home.packages`, so it never lands on an agent's `PATH`. The host proxy and broker run
as launchd user agents; the gates start temporary services only where required and stop the
services they started.

`check all` runs every phase in one process, which is the only way to catch a boundary that
holds in isolation and fails in combination. It also runs the allowlist assertions against
the keyed proxy, so `check model` cannot report a key that stays home while the allowlist is
wrong. The gate stages its scripts in `/run/crew-gate`, a root-owned directory on tmpfs that
`agent` cannot write; a failed copy is reported as tampering rather than as an rsync error.

## Secrets

Policy: every secret lives in Automic Vault. No secret in this repo, no key in
`~/.pi/agent/settings.json`, no exported secret in `.zshrc`.

Code that needs a secret gets it per launch, so it is never ambient in the environment:

```sh
av inject <name> -- command
```

Pi reads its model key from `MODEL_API_KEY`, and `av inject` supplies it for the life of one
process. There is no pi hardener either, so the launch is where the key enters; the reasoning
is in [ADR-0005](docs/adr/0005-pi-only-harness.md):

```sh
mate   # av inject +MODEL_API_KEY -- env FM_BACKEND=herdr pi
```

If a secret ever reaches git history, a stale file or a log, rotate it at the provider and
`av save` the new value. Rewriting history is not a fix, because the old value stays
readable wherever it was copied.

## Scan findings

`av scan` on 2026-11-16, and what each finding became:

| Finding                                                   | Severity     | Status                                                                                                               |
| --------------------------------------------------------- | ------------ | -------------------------------------------------------------------------------------------------------------------- |
| `gh-cli-keychain-access`: gh token readable by `security` | HIGH         | Fixed: the isotope is declared and `av harden gh` gates the command, see manual step 5                               |
| `git-credential-fill`: ambient helper for github.com      | HIGH         | Fixed: `~/.config/git/config` resets Apple's `osxkeychain` helper, the cached `github.com` item is gone, remotes SSH |
| `emudhra`: CA bundled in `/usr/local/bin/node`            | HIGH         | Fixed: the stale standalone Node 22 was removed; `node` is now `nodejs_24` from this repo's profile                  |
| `openssh`: `~/.ssh/id_ed25519` has no passphrase          | HIGH         | Manual: see step 6 above                                                                                             |
| `sudo` without Touch ID                                   | medium       | Fixed: `security.pam.services.sudo_local.touchIdAuth` writes `/etc/pam.d/sudo_local`                                 |
| OpenRouter key in `~/.claude/settings.json`               | not detected | Fixed: Automic Vault, injected by `mate`; that file is no longer tracked                                             |

Seven medium items remain. Six are `PATH` ordering (`/opt/homebrew/bin`,
`/opt/homebrew/sbin`, `~/.nix-profile/bin`, each reported by the shell detector and again
by the macOS process detector), which is the ordering nix-darwin and `brew shellenv` exist
to produce. The seventh is the `homebrew` detector flagging `/opt/homebrew` as writable by
the current user; that one is an accepted risk, explained in
[ADR-0003](docs/adr/0003-accepted-homebrew-writable-risk.md).

npm and pnpm token detectors are present but report nothing today. If a registry token is
ever needed, `av save` it and inject it the same way rather than writing `~/.npmrc`.

## Layout

```
identity.nix        username, home directory and host, read from the environment
tools.nix           formatters and linters, shared by home.nix and the dev shell
crew-tools.nix      the crew's runtime CLIs, built from nix/crew-tools
nix/crew-tools/     pins.nix (versions + hashes), builders.nix (two shapes), locks/,
                    update.sh (the only writer of any of it)
crew-sandbox        flake input pinned to v0.1.0: CLI, Lima guest, proxy, broker,
                    guest Home Manager module, Darwin services and verification gates
flake.nix           inputs pinned by flake.lock (nixpkgs, nix-darwin, home-manager,
                    nix-homebrew, automic-vault/isotopes tap, pi); evaluated impurely
configuration.nix   system: macOS defaults, fonts, homebrew taps/brews/casks
tailscale.nix       system: the Tailscale daemon
home.nix            user: packages, zsh, starship, link table, rendered VS Code settings
home/               the config files (wezterm, nvim, herdr, vscode, .pi, .agents/skills, AGENTS.md)
docs/adr/           one record per decision that is not obvious from the code
.lavish/crew-sandbox-task.md    how the sandbox works, piece by piece, with the reasoning
.lavish/crew-sandbox-review.md  the review of the sandbox: findings, evidence, order of work
GLOSSARY.md         shared terms
rebuild.sh          the only entry point: fresh machine, or re-apply changes (primary by default)
.githooks/check     formatter and lint module (--staged, --all)
.githooks/pre-commit  git hook, calls check --staged
.github/workflows/  CI that runs check --all on macOS
.stylua.toml        Lua formatting style shared with the StyLua extension
selene.toml         Lua lint rules (.selene/vim.yml defines Neovim globals)
.prettierignore     generated and vendored files Prettier should skip
```

`home/AGENTS.md` is the single copy of the global agent instructions. Pi reads it as
`~/.pi/agent/AGENTS.md`; the `~/.claude/CLAUDE.md` and `~/.claude/AGENTS.md` links are kept
for any agent that still looks there. Skills live under `home/.agents/skills`, and every
directory there is linked one level deep into both `~/.agents/skills` (pi and Copilot) and
`~/.claude/skills` (Claude Code), so adding a skill needs no change to `home.nix`. A skill
that belongs to one machine only goes in `home/.agents/skills-primary` or
`home/.agents/skills-mini`, which are linked the same way but only on the host they name. The
host comes from the configuration name in `flake.nix`, not from the environment, so CI still
evaluates both directories. Skills
vendored from elsewhere are re-copied here to update: `lavish` (MIT, from
[kunchenguid/lavish-axi](https://github.com/kunchenguid/lavish-axi)), `stow`, the pstack
set (`bro`, `teach`, and the `principle-*` leaves in `software-engineering-principles/`), and
the 27 skills of [mattpocock/skills](https://github.com/mattpocock/skills) (MIT, pinned at
`49dd158d1076134a641b33efb035946536778336`, the commit the `mattpocock-skills` entry in
Anthropic's `claude-plugins-official` marketplace resolves to). Upstream's `teach` is vendored
as `matt-pocock-teach`, because the pstack `teach` already owns that name.

The engineering principles apply to every agent and every task. Their leaves stay exactly as
pstack ships them, including `disable-model-invocation: true`, so the local
`engineering-principles` skill is the model-invocable index that routes to them, and
`home/AGENTS.md` makes that index mandatory for a harness that does not surface skills. See
[ADR-0007](docs/adr/0007-engineering-principles-are-skills.md).

## Checks

`.githooks/check` is the module; git runs it through `.githooks/pre-commit`, which passes
`--staged`. That is also the default.

```sh
.githooks/check --staged   # changed files, what the hook runs
.githooks/check --all      # every tracked file, plus a flake evaluation
```

`--staged` formats staged files with nixfmt, shfmt, StyLua, Prettier and Taplo, then
blocks the commit on statix, deadnix, ShellCheck, Selene or Taplo findings. It re-stages
only the files the formatters actually changed, so unstaged hunks in a partially staged
file stay out of the commit.

`--all` covers every tracked file and additionally evaluates the flake, which catches Nix
errors that formatting and linting cannot (the evaluation is skipped when `nix` is not on
`PATH`). `.github/workflows/checks.yml` runs the same command on macOS for pushes and pull
requests, through the dev shell:

```sh
nix develop --impure --command ./.githooks/check --all
```

The dev shell takes its tools from the pinned `nixpkgs` input, so CI and this machine run
the same versions even before `./rebuild.sh` has installed anything for the user.

`rebuild.sh` sets `core.hooksPath`, so a clone it has run needs no setup. For anything
else:

```sh
git config core.hooksPath .githooks
```

The crew VM has a separate gate, because it asserts properties of a running guest rather than
of files: `nix run .#crew-sandbox -- check`. It stays out of `--all`, which must pass on a
machine that has never started the VM.

## Adapting

Most of this is no longer needed, because the identity is dynamic.

- **Another user, home or host.** `AGENTIC_DEV_ENV_USER`, `AGENTIC_DEV_ENV_HOME` and
  `AGENTIC_DEV_ENV_HOST` override the identity. `AGENTIC_DEV_ENV_HOST` names the
  `darwinConfigurations` attribute, not the machine hostname, and must agree with the
  `--primary`/`--mini` flag.
- **Another config.** Add the `$HOME`-relative target and the repo path to the table in
  `home.nix`, mapped through `config.lib.file.mkOutOfStoreSymlink`, then run
  `./rebuild.sh`. A file whose content Nix generates is rendered or seeded instead, depending
  on whether the application itself writes it.
- **Homebrew is additive.** `homebrew.onActivation.cleanup = "none"`: `brews` and `casks`
  are installed and upgraded, and everything else on the machine is left alone. The price is
  that deleting an entry here does not uninstall it - run `brew uninstall --cask <name>`
  (or `brew zap <name>`) when you want it gone. The reasoning is in
  [ADR-0006](docs/adr/0006-homebrew-is-additive.md).
- **The tap.** The Automic Vault cask is not in homebrew-cask, so its tap is a flake input
  (`automic-vault-tap`, `flake = false`) installed by `nix-homebrew.taps`. Bump it with
  `nix flake update automic-vault-tap`. Taps stay mutable on purpose, and the cask entry
  must stay fully qualified and `trusted`; see
  [ADR-0001](docs/adr/0001-homebrew-taps-stay-mutable.md).
- **A new tool that needs a secret.** Start it through `av inject`, not from an exported
  variable; see [Secrets](#secrets).
