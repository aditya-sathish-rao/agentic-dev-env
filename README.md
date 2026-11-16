# agentic-dev-env

macOS dev environment as code: [nix-darwin](https://github.com/nix-darwin/nix-darwin) + [home-manager](https://github.com/nix-community/home-manager) for everything
declarative, Homebrew for GUI apps. Config files live in this repo and are symlinked
into place, so edits are in-place: change the file here, no rebuild needed.

## What you get

- **Packages** (nix): ripgrep, fd, fzf, jq, lazygit, neovim, Hack Nerd Font
- **Apps** (homebrew): wezterm, Visual Studio Code, claude-code, herdr, Node, Automic Vault
  (`av`, which holds every secret this machine needs), and the `automic-vault/isotopes/gh-cli`
  isotope that `gh` hardening installs
- **Shell**: zsh with autosuggestions + syntax highlighting, starship prompt, git aliases
- **Configs**: wezterm, neovim, herdr, VS Code (font + terminal font), Claude global
  instructions and user-level skills (`stow`, `lavish`), `~/.config/git/config` (resets
  Apple's ambient credential helper) and `~/.ssh/config` (Keychain-backed key)

## Setup from scratch

Needs a fresh macOS machine (Apple Silicon) and an admin user named `m2-pro` - host and
user names are hardcoded in `flake.nix` / `configuration.nix`, see [Adapting](#adapting).

```sh
git clone https://github.com/aditya-sathish-rao/agentic-dev-env.git ~/github/dotfiles
cd ~/github/dotfiles
./bootstrap.sh
```

`bootstrap.sh` is idempotent and does, in order:

1. Links the clone to `~/.dotfiles` (all config paths resolve through it, so the repo can
   live anywhere).
2. Installs the Xcode command line tools if missing and stops so you can re-run after.
3. Installs [Determinate Nix](https://determinate.systems/nix) if `nix` isn't present.
4. Runs the first `darwin-rebuild switch`, using the pinned `nix-darwin` from `flake.lock`.
   Expect a `sudo` password prompt. Homebrew itself, then all brews/casks, are installed by
   this activation.

After it finishes, open a new terminal (zsh is now the login shell config) and you're done.
`home/.claude/settings.json` is tracked, so a fresh clone plus `./bootstrap.sh` leaves a
working `~/.claude/settings.json` - no file to create by hand. The one-time Automic Vault
steps below are what cannot be automated.

### Day to day

```sh
./rebuild.sh    # apply config changes (same as bootstrap.sh once nix-darwin exists)
```

## Manual steps

Everything else is declarative. These are the steps Automic Vault only lets a human do,
once per Mac, after `bootstrap.sh`:

1. **Start the app.** Homebrew installs the bundle but nothing launches it, and every
   `av` command that needs Approval fails with `approval service is not running` until
   the menu bar app is up:

   ```sh
   open -a "Automic Vault"
   ```

   Grant the macOS permission prompts it shows (notifications; Keychain access for the
   Data Protection Keychain that stores the secrets). Leave it running.

2. **Install the `av` CLI.** The cask ships `av` inside the bundle; the copy on `PATH` is
   installed by the app: **Install av CLI** (it authenticates as admin and writes a
   root-owned `/usr/local/bin/av`). It refuses to install into a directory the user owns,
   so if `/usr/local/bin` is user-owned, fix that first and click Install again:

   ```sh
   sudo chown root:wheel /usr/local/bin
   ```

3. **Store the OpenRouter key.**

   ```sh
   av save ANTHROPIC_AUTH_TOKEN   # hidden input, then approve the prompt
   ```

   This is the key that used to sit in `home/.claude/settings.json`. It now lives only in
   Automic Vault and reaches `claude` through `av inject`.

4. **Let the terminal inject it.** Until the terminal is granted access, `av inject` asks
   for Approval on every launch. In the app: select `ANTHROPIC_AUTH_TOKEN` →
   **Allow Launcher** → WezTerm. After that `cc` starts with no prompt.

5. **Encrypt the SSH key.** `av scan` reports `~/.ssh/id_ed25519` as a HIGH finding while
   it has no passphrase, and only you can type the new one:

   ```sh
   ssh-keygen -p -f ~/.ssh/id_ed25519
   ssh-add --apple-use-keychain ~/.ssh/id_ed25519
   ```

   `~/.ssh/config` is managed with `AddKeysToAgent`/`UseKeychain`, so the passphrase is
   stored in the macOS Keychain once and push/pull keep working without retyping it.

6. **Rotate if it ever leaked.** `home/.claude/settings.json` is tracked and holds no
   secrets. If a secret does reach git history (or a file outside the vault), rotate it at
   the provider and `av save` the new value; rewriting history is not a fix.

## Secrets

Policy: every secret lives in Automic Vault. Nothing in this repo, no `env` block in
`~/.claude/settings.json`, no exported token in `.zshrc`. Code that needs a secret gets it
per launch (`av inject <name> -- command`), so it is never ambient in the environment.

Claude Code is **not** a supported `av harden` target (`av hardeners --json`: aws, brew,
gh, codex, ... but no claude), and `av scan` has no Claude detector, so it will not flag
`settings.json`. The supported path for it is Secret Custody plus a launch wrapper, which
is what the `cc` alias does:

```sh
cc   # av inject +ANTHROPIC_AUTH_TOKEN -- claude --dangerously-skip-permissions
```

Findings from `av scan` on 2026-11-16 and what each one became:

| Finding                                                   | Severity     | Status                                                                                                                                                                                   |
| --------------------------------------------------------- | ------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `gh-cli-keychain-access`: gh token readable by `security` | HIGH         | Fixed: the tap isotope is declared in `configuration.nix` and `av harden gh` migrated the tokens, deleted both legacy Keychain items, and now gates `gh`. `av doctor gh` reports healthy |
| `git-credential-fill`: ambient helper for github.com      | HIGH         | Fixed: `~/.config/git/config` resets Apple's inherited `osxkeychain` helper, the cached `github.com` Internet password is deleted, and remotes are SSH                                   |
| `emudhra`: CA bundled in `/usr/local/bin/node`            | HIGH         | Fixed: the stale standalone Node 22 was removed and `node` (26) comes from Homebrew                                                                                                      |
| `openssh`: `~/.ssh/id_ed25519` has no passphrase          | HIGH         | Manual: see step 5 above                                                                                                                                                                 |
| `sudo` without Touch ID                                   | medium       | Fixed: `security.pam.services.sudo_local.touchIdAuth` writes `/etc/pam.d/sudo_local`                                                                                                     |
| OpenRouter key in `~/.claude/settings.json`               | not detected | Fixed: Automic Vault, injected by `cc` (steps above)                                                                                                                                     |

The remaining findings are seven medium items, all environmental. Six are `PATH` ordering
(`/opt/homebrew/bin`, `/opt/homebrew/sbin`, `~/.nix-profile/bin`, each reported once by the
shell detector and once by the macOS process detector) and one is the `homebrew` detector
flagging `/opt/homebrew` as writable by the current user.

They cannot be cleared without abandoning the declarative setup:

- **`PATH` ordering** is what nix-darwin and `brew shellenv` are supposed to produce.
  `~/.nix-profile/bin` and `/opt/homebrew/bin` are user-writable by design, and the
  detector is explicit that this is expected for version managers.
- **`av harden brew` refuses on this machine.** It only supports formulae and CLI-only
  casks, and `/opt/homebrew/Caskroom` holds application casks (`automic-vault`,
  `visual-studio-code`, `wezterm`):

  ```
  av harden: incompatible Homebrew Casks
  ```

- **Hardening would also break `darwin-rebuild`.** It re-owns `/opt/homebrew` as
  `automic:vault` and replaces `/usr/local/bin/brew` with a setuid launcher that asks the
  menu bar app for approval on every invocation. nix-homebrew links managed taps into
  `/opt/homebrew/Library/Taps`, and nix-darwin applies `homebrew.*` through
  `brew bundle` during activation, which hardened Homebrew does not support.

So the `homebrew` item is an accepted risk. The app marks that detector Experimental. It is
a same-user integrity boundary, not a secret boundary: `av inject` keeps the token out of
that environment, which is the part that matters here. `av scan` has no way to acknowledge
or suppress a finding, so the item stays visible in the app.

`av doctor` is clean now. The two things it used to flag were pre-existing state, not
config: `/usr/local/bin/{npm,pnpm}` went away with the stale Node install, and
`/usr/local/bin/aws` was the AWS CLI v2 launcher from Oct 2024, which Automic Vault read as
a stale hardened launcher. That symlink was removed; the payload is still at
`/usr/local/aws-cli/aws`, so restoring it is either `ln -s` or, the way to keep Automic
Vault happy, `av harden aws` (it installs a verified release under `/opt/av/aws`).

npm/pnpm token detectors are present in Automic Vault but report nothing today; if a
registry token is ever needed, `av save` it and inject it the same way rather than writing
`~/.npmrc`.

## Layout

```
flake.nix           inputs, pinned by flake.lock (nixpkgs, nix-darwin, home-manager,
                    nix-homebrew, and the automic-vault/isotopes Homebrew tap)
configuration.nix   system: macOS defaults, fonts, homebrew taps/brews/casks
home.nix            user: packages, zsh, starship, symlinks from home/ into ~
home/               the dotfiles themselves (wezterm, nvim, herdr, vscode, claude, AGENTS.md)
.stylua.toml        Lua formatting style shared by the StyLua extension
.githooks/          pre-commit formatter/linter runner
selene.toml         Lua lint rules (.selene/vim.yml defines Neovim globals)
.prettierignore     generated and vendored files Prettier should skip
bootstrap.sh        fresh machine -> fully provisioned
rebuild.sh          re-apply after config changes
```

`home/AGENTS.md` is the single copy of the global agent instructions; it is linked to both
`~/.claude/CLAUDE.md` and `~/.claude/AGENTS.md`.

Skills under `home/.agents/skills/lavish` (MIT, from
[kunchenguid/lavish-axi](https://github.com/kunchenguid/lavish-axi)) and
`home/.claude/skills/stow` are vendored copies of installed skills, pointed at by
`~/.agents/skills` and `~/.claude/skills`. Re-copy their `SKILL.md` here to update.

## Formatting and linting

`bootstrap.sh` sets `core.hooksPath` to `.githooks`, so every clone uses the tracked
pre-commit hook. For an existing clone, enable it once with:

```sh
git config core.hooksPath .githooks
```

The hook formats staged files with nixfmt, shfmt, StyLua, Prettier, and Taplo, re-stages
the fixes so they are included in the commit, and blocks the commit on statix, deadnix,
ShellCheck, Selene, or Taplo findings. To run the same checks over every tracked file:

```sh
./.githooks/pre-commit --all
```

Prettier skips generated lock files and the vendored skills; see `.prettierignore`.

## Adapting

- Different user/host: update `system.primaryUser`, `users.users.<name>`, `home.username`,
  `home.homeDirectory` and the `darwinConfigurations."m2-pro"` attribute name.
- `bootstrap.sh` takes the flake attribute from `DOTFILES_HOST` (default `m2-pro`).
- `homebrew.onActivation.cleanup = "zap"` removes anything not listed in `brews`/`casks`, so
  add anything you install before running `rebuild.sh`.
- The Automic Vault cask is not in homebrew-cask, so its tap is a flake input
  (`automic-vault-tap`, `flake = false`) and is installed by `nix-homebrew.taps`. Bump it
  with `nix flake update automic-vault-tap`. `mutableTaps = true` is deliberate: `zap`
  un-taps whatever is missing from `homebrew.taps`, which an immutable store symlink cannot
  do. Homebrew also refuses to load the cask unless it is trusted, so the cask entry is
  fully qualified and marked `trusted`; the tap itself is not trusted.
- Any new tool that needs a secret should be started through `av inject`, not from an
  exported variable; see [Secrets](#secrets).
