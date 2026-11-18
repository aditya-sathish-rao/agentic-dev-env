# agentic-dev-env

macOS dev environment as code: [nix-darwin](https://github.com/nix-darwin/nix-darwin) and
[home-manager](https://github.com/nix-community/home-manager) for everything declarative,
Homebrew for GUI apps. Config files stay in this repo and are linked into place, so most
edits need no rebuild.

## What you get

- **Packages** (nix): ripgrep, fd, fzf, jq, lazygit, neovim, Hack Nerd Font, the agent
  harness `pi` (from its own flake input), and the formatters and linters the hook runs:
  nixfmt, shfmt, stylua, prettier, taplo, statix, deadnix, shellcheck, selene.
- **Apps** (homebrew): wezterm, Visual Studio Code, herdr, Node, Automic
  Vault (`av`, which holds every secret this machine needs), and the
  `automic-vault/isotopes/gh-cli` isotope that `av harden gh` installs.
- **Shell**: zsh with autosuggestions and syntax highlighting, starship prompt, git
  aliases, `mate` for the crew, and `~/.local/bin` on `PATH` (exported
  from `.zshrc`, because macOS `path_helper` rewrites `PATH` after `.zshenv`).
- **Configs**: wezterm, neovim, herdr, VS Code (font, terminal font, formatters), pi's
  agent directory (`~/.pi/agent/settings.json` owns the default model, `AGENTS.md` the
  global instructions), user-level skills (`stow`, `lavish`) under `~/.agents/skills`,
  `~/.config/git/config` (resets Apple's ambient credential helper) and `~/.ssh/config`
  (Keychain-backed key).

Config files under `home/` are edited in place in the repo and linked into `$HOME`, so an
edit needs no rebuild. Two files are generated instead, because their content depends on
the machine: the VS Code user settings (three formatter paths come from
`config.home.profileDirectory`, so a change to `home/.config/vscode/settings.json` needs
`./rebuild.sh`) and `~/.config/git/config` (one empty credential helper, written from
`home.nix`).

Terms used below are defined in [GLOSSARY.md](GLOSSARY.md).

## Setup from scratch

Needs a macOS machine (Apple Silicon or Intel) and an admin user. Nothing in the tree
hardcodes that user: `identity.nix` reads the identity from the environment when the flake
is evaluated, and the host platform comes from the machine. See [Adapting](#adapting) if
the defaults do not fit.

```sh
git clone https://github.com/aditya-sathish-rao/agentic-dev-env.git ~/github/dotfiles
cd ~/github/dotfiles
./rebuild.sh
```

`rebuild.sh` is the only entry point, and it is idempotent. On a fresh machine and on an
existing one it does, in order:

1. Checks the Xcode command line tools. If they are missing it starts the installer and
   stops, so run it again when that finishes.
2. Links the clone to `~/.dotfiles`, so every config path resolves through one place and
   the clone can live anywhere. It refuses to nest when `~/.dotfiles` is already a real
   directory.
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
cannot be automated, and the crew adds its own manual steps in
[Crew](#crew): clone firstmate before the first rebuild, install its companion CLIs, store
its key.

## Day to day

```sh
./rebuild.sh    # apply config changes
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

3. **Store the DeepSeek key.**

   ```sh
   av save DEEPSEEK_API_KEY   # hidden input, then approve the prompt
   ```

   This key now lives only in Automic Vault and reaches every agent through `av inject`.

4. **Let the terminal inject it.** Until the terminal is granted access, `av inject` asks
   for Approval on every launch. In the app: select `DEEPSEEK_API_KEY` →
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

Talk to one agent, ship with a crew. `mate` starts the first mate: pi inside a manual clone
of [firstmate](https://github.com/kunchenguid/firstmate) at `~/firstmate`. It splits a
request into parallel tasks and spawns one crewmate per task into its own herdr tab and git
worktree. Everything runs the same harness, pi, on DeepSeek V4.1 Flash.

```sh
git clone https://github.com/kunchenguid/firstmate ~/firstmate   # once, before ./rebuild.sh
mate
```

What is declared here, and where:

- `pi` is a flake input ([flake.nix](flake.nix), pinned by `flake.lock`) and the only agent
  harness here. Its package ships its own Node runtime and model catalog, so no global npm
  install is involved and the harness version moves only when the lock does.
- `home/.pi/agent/settings.json` is linked to `~/.pi/agent/settings.json` and owns the model
  every agent starts on: `defaultProvider: deepseek`, `defaultModel: deepseek-flash` (the
  catalog entry named DeepSeek V4.1 Flash), `defaultThinkingLevel: high`. To try a different
  model for the first mate, change those values and start `mate` again. The file is a link
  into this repo, so it needs no rebuild.
- `home/firstmate/crew-dispatch.json` is linked to `~/firstmate/config/crew-dispatch.json`.
  It declares one profile, `{ "harness": "pi", "provider": "deepseek" }`, and deliberately
  omits the model, so crewmates inherit the same `settings.json` default. With
  `shared_quota: true` the `quota-array-dispatch` skill resolves the declared profile in
  order and makes no quota call: there is one provider and one budget.
- `mate` selects the herdr backend for the launch and injects `DEEPSEEK_API_KEY` into the
  first mate only. Crewmate panes come from a herdr server that never saw the key, so the
  wrapper below injects it per crewmate.
- `home/.local/bin/pi` shadows the harness with a thin wrapper. A crewmate pane starts with
  no `DEEPSEEK_API_KEY`, so the wrapper first re-runs itself under `av inject` and each
  worker holds the key only for its own lifetime; if av fails, the launch stops instead of
  running signed out. Probes that cannot use a key (`--help`, `--version`, `--list-models`,
  `auth`, `update`) pass straight through, so firstmate's version detection never waits on
  a vault approval.

### What a rebuild automates, and what stays manual

`./rebuild.sh` automates the harness and the wiring: `pi` comes from the flake input (pinned
by `flake.lock`), herdr from Homebrew, the config files are linked
(`~/.pi/agent/settings.json`, `~/.pi/agent/AGENTS.md` and
`~/firstmate/config/crew-dispatch.json`), `~/.local/bin` joins `PATH`, and the generated
`.zshrc` gains the `mate` alias.

It never installs, clones or updates firstmate itself. That clone at `~/firstmate` is manual
because firstmate updates itself (`/updatefirstmate`), and it cannot install the companion
CLIs below or store secrets. So a new machine needs these steps, in this order:

1. **Clone firstmate before the first rebuild.** Activation creates `~/firstmate/config/` to
   hold the linked dispatch file, and `git clone` then refuses the non-empty directory. If the
   rebuild ran first, `rm -rf ~/firstmate` (nothing is in it yet) and clone again.
2. **`./rebuild.sh`** - pi, herdr, the links, `~/.local/bin` on `PATH`, `mate`.
3. **Install the companion CLIs** (below). They are not in nixpkgs and nothing links them.
4. **Store the key and allow the launcher** (below). `mate` injects it into the first mate,
   and the pi wrapper into each crewmate.
5. **Check `gh`.** Dispatching clones projects and opens PRs, so `av doctor gh` must report
   healthy on this machine's hardened `gh-cli` isotope before `mate` can do anything.
6. **Run `mate`.** The first launch reports anything still missing as `MISSING:` and asks
   before installing or upgrading it.

Its companion CLIs are not in nixpkgs, so they are installed once by their own installers. This
machine runs gh-axi 0.1.51, chrome-devtools-axi 0.1.46, tasks-axi 0.2.6, quota-axi 0.1.69,
lavish-axi 0.1.97, treehouse 3.1.8 and no-mistakes v1.106.1:

```sh
npm install -g gh-axi chrome-devtools-axi tasks-axi quota-axi lavish-axi
gh-axi setup hooks && chrome-devtools-axi setup hooks && lavish-axi setup hooks
curl -fsSL https://kunchenguid.github.io/treehouse/install.sh | sh
curl -fsSL https://raw.githubusercontent.com/kunchenguid/no-mistakes/main/docs/install.sh | sh
```

`home.nix` puts `~/.local/bin` on `PATH`, so the treehouse and no-mistakes installers write
there instead of asking to sudo into `/usr/local/bin`. `~/firstmate/bin/fm-bootstrap.sh`
lists anything still missing as `MISSING:` on the next `mate`.

The three `setup hooks` lines install SessionStart hooks for Claude Code, Codex, OpenCode and
Copilot CLI. Pi is not one of those targets, so they do not reach the first mate: it gets the
same guidance from the `lavish` skill under `~/.agents/skills`, which pi discovers, and by
calling the `-axi` CLIs directly. Keep the lines only if you also run one of those harnesses.

Save the key once, as in [Manual steps](#manual-steps) step 3:

```sh
av save DEEPSEEK_API_KEY
```

Then allow the launcher for it, as in step 4.

## Secrets

Policy: every secret lives in Automic Vault. No secret in this repo, no key in
`~/.pi/agent/settings.json`, no exported secret in `.zshrc`.

Code that needs a secret gets it per launch, so it is never ambient in the environment:

```sh
av inject <name> -- command
```

Pi reads its DeepSeek key from `DEEPSEEK_API_KEY`, and `av inject` supplies it for the life
of one process. There is no pi hardener either, so the launch is where the key enters; the
reasoning is in [ADR-0005](docs/adr/0005-pi-only-harness.md):

```sh
mate   # av inject +DEEPSEEK_API_KEY -- env FM_BACKEND=herdr pi
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
| `emudhra`: CA bundled in `/usr/local/bin/node`            | HIGH         | Fixed: the stale standalone Node 22 was removed and `node` comes from Homebrew                                       |
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
flake.nix           inputs pinned by flake.lock (nixpkgs, nix-darwin, home-manager,
                    nix-homebrew, automic-vault/isotopes tap, pi); evaluated impurely
configuration.nix   system: macOS defaults, fonts, homebrew taps/brews/casks
tailscale.nix       system: the Tailscale daemon
home.nix            user: packages, zsh, starship, link table, rendered VS Code settings
home/               the dotfiles (wezterm, nvim, herdr, vscode, .pi, .agents/skills, AGENTS.md)
docs/adr/           one record per decision that is not obvious from the code
GLOSSARY.md         shared terms
rebuild.sh          the only entry point: fresh machine, or re-apply changes
.githooks/check     formatter and lint module (--staged, --all)
.githooks/pre-commit  git hook, calls check --staged
.github/workflows/  CI that runs check --all on macOS
.stylua.toml        Lua formatting style shared with the StyLua extension
selene.toml         Lua lint rules (.selene/vim.yml defines Neovim globals)
.prettierignore     generated and vendored files Prettier should skip
```

`home/AGENTS.md` is the single copy of the global agent instructions. Pi reads it as
`~/.pi/agent/AGENTS.md`; the `~/.claude/CLAUDE.md` and `~/.claude/AGENTS.md` links are kept
for any agent that still looks there. Skills live under `home/.agents/skills` and are linked
to `~/.agents/skills`, which pi discovers: `lavish` (MIT, from
[kunchenguid/lavish-axi](https://github.com/kunchenguid/lavish-axi)) and `stow`. Re-copy
their `SKILL.md` here to update.

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

## Adapting

Most of this is no longer needed, because the identity is dynamic.

- **Another user, home or host.** `DOTFILES_USER`, `DOTFILES_HOME` and `DOTFILES_HOST`
  override the identity. `DOTFILES_HOST` names the `darwinConfigurations` attribute, not
  the machine hostname.
- **Another config.** Add the `$HOME`-relative target and the repo path to the table in
  `home.nix`, mapped through `config.lib.file.mkOutOfStoreSymlink`, then run
  `./rebuild.sh`. A file that needs generated content is rendered instead of linked.
- **Homebrew cleanup.** `homebrew.onActivation.cleanup = "zap"` removes anything not
  listed in `brews` or `casks`, so add what you install before running `./rebuild.sh`.
- **The tap.** The Automic Vault cask is not in homebrew-cask, so its tap is a flake input
  (`automic-vault-tap`, `flake = false`) installed by `nix-homebrew.taps`. Bump it with
  `nix flake update automic-vault-tap`. Taps stay mutable on purpose, and the cask entry
  must stay fully qualified and `trusted`; see
  [ADR-0001](docs/adr/0001-homebrew-taps-stay-mutable.md).
- **A new tool that needs a secret.** Start it through `av inject`, not from an exported
  variable; see [Secrets](#secrets).
