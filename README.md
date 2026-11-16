# agentic-dev-env

macOS dev environment as code: [nix-darwin](https://github.com/nix-darwin/nix-darwin) + [home-manager](https://github.com/nix-community/home-manager) for everything
declarative, Homebrew for GUI apps. Config files live in this repo and are symlinked
into place, so edits are in-place: change the file here, no rebuild needed.

## What you get

- **Packages** (nix): ripgrep, fd, fzf, jq, lazygit, neovim, Hack Nerd Font
- **Apps** (homebrew): wezterm, Visual Studio Code, claude-code, herdr
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

### Day to day

```sh
./rebuild.sh    # apply config changes (same as bootstrap.sh once nix-darwin exists)
```

## Manual step: Claude settings

`home/.claude/settings.json` is git-ignored because it holds an API key. Create it yourself
before/after the first build; the nix link into `~/.claude/settings.json` dangles until the
file exists. For example:

```sh
mkdir -p ~/github/dotfiles/home/.claude
$EDITOR ~/github/dotfiles/home/.claude/settings.json   # model, theme, statusLine, env.ANTHROPIC_API_KEY
```

## Layout

```
flake.nix           inputs, pinned by flake.lock
configuration.nix   system: macOS defaults, fonts, homebrew brews/casks
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
