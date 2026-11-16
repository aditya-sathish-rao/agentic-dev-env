# agentic-dev-env

macOS dev environment as code: [nix-darwin](https://github.com/nix-darwin/nix-darwin) + [home-manager](https://github.com/nix-community/home-manager) for everything
declarative, Homebrew for GUI apps. Config files live in this repo and are symlinked
into place, so edits are in-place: change the file here, no rebuild needed.

## What you get

- **Packages** (nix): ripgrep, fd, fzf, jq, lazygit, neovim, Hack Nerd Font
- **Apps** (homebrew): wezterm, Visual Studio Code, claude-code, herdr, Automic Vault
  (`av`, which holds every secret this machine needs)
- **Shell**: zsh with autosuggestions + syntax highlighting, starship prompt, git aliases
- **Configs**: wezterm, neovim, herdr, VS Code (font + terminal font), Claude global
  instructions and user-level skills (`stow`, `lavish`)

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

5. **Rotate if it ever leaked.** `home/.claude/settings.json` is tracked and holds no
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

Findings from `av scan` on 2026-11-16, and what each one should become:

| Finding | Severity | Decision |
| --- | --- | --- |
| `gh-cli-keychain-access`: gh token readable by `security` | HIGH | Replace the `gh` formula with the `automic-vault/isotopes/gh-cli` isotope (declare it in `configuration.nix` first), then `av harden gh` |
| `git-credential-fill`: ambient helper for github.com | HIGH | Move GitHub remotes to SSH, drop the helper from the CommandLineTools `gitconfig` |
| `openssh`: `~/.ssh/id_ed25519` has no passphrase | HIGH | `ssh-keygen -p -f ~/.ssh/id_ed25519`, keep the passphrase in the macOS Keychain |
| `emudhra`: CA bundled in `/usr/local/bin/node` | HIGH | Update the Node runtime, or `av harden emudhra` if it must stay |
| OpenRouter key in `~/.claude/settings.json` | not detected | Moved to Automic Vault as `ANTHROPIC_AUTH_TOKEN` (steps above) |

npm/pnpm token detectors are present in Automic Vault but report nothing today; if a
registry token is ever needed, `av save` it and inject it the same way rather than writing
`~/.npmrc`.

The remaining findings are medium and environmental: user-writable directories ahead of
system ones in `PATH` (`/opt/homebrew/bin`, `~/.nix-profile/bin`, `~/crystallize`,
`node_modules/.bin`), a Homebrew prefix the user can write to, and `sudo` without Touch ID
(`/etc/pam.d/sudo_local`). Accepted as-is; `av inject` keeps secrets out of that
environment, which is the part that matters here.

`av doctor` complains about `/usr/local/bin/{aws,npm,pnpm}` being symlinks left by an
earlier hardening attempt. Each is pre-existing: run `av harden <tool>` for one you use, or
remove the symlink.

## Layout

```
flake.nix           inputs, pinned by flake.lock (nixpkgs, nix-darwin, home-manager,
                    nix-homebrew, and the automic-vault/isotopes Homebrew tap)
configuration.nix   system: macOS defaults, fonts, homebrew taps/brews/casks
home.nix            user: packages, zsh, starship, symlinks from home/ into ~
home/               the dotfiles themselves (wezterm, nvim, herdr, vscode, claude, AGENTS.md)
bootstrap.sh        fresh machine -> fully provisioned
rebuild.sh          re-apply after config changes
```

`home/AGENTS.md` is the single copy of the global agent instructions; it is linked to both
`~/.claude/CLAUDE.md` and `~/.claude/AGENTS.md`.

Skills under `home/.agents/skills/lavish` (MIT, from
[kunchenguid/lavish-axi](https://github.com/kunchenguid/lavish-axi)) and
`home/.claude/skills/stow` are vendored copies of installed skills, pointed at by
`~/.agents/skills` and `~/.claude/skills`. Re-copy their `SKILL.md` here to update.

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
