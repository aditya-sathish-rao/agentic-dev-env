# Glossary

The words this repo uses in its own, narrow sense.

## agent account

The `agent` Linux user inside the crew VM. Agents run as it, and it holds no privilege: no
sudo, no privileged group, no readable firewall configuration. It is not an account you log
in as; `crew-sandbox shell` gives you the administration account instead.

## check

The tracked `.githooks/check` module that formats and lints this repo. `--staged` is the
default and what git runs through `.githooks/pre-commit`; `--all` checks every tracked
file and also evaluates the flake.

## crew VM

The one Lima guest defined by [nix/crew-sandbox/lima.yaml](nix/crew-sandbox/lima.yaml), which
the fleet will run inside. It is replaced rather than patched: changing its definition means
destroying it and creating it again.

## crewmate

An agent a first mate spawns for one task, in its own herdr tab and git worktree. Here it is
pi on DeepSeek V4.1 Flash, chosen by `home/firstmate/crew-dispatch.json`.

## dotfiles link

The symlink `~/.dotfiles` that points at the clone. Every config path in this repo
resolves through it, so `home.nix` can name files without knowing where the clone lives.

## first mate

The pi session started by `mate` inside `~/firstmate`. It is the only agent you talk to: it
turns a request into parallel tasks and hands them to crewmates.

## guest

The Linux side of the crew VM, as opposed to the host, the macOS machine running it. A guest
property is one asserted from inside, over SSH, not read from the definition file.

## harness

The agent program that runs a model, such as pi. Here pi is the only one, for the first mate
and for crewmates alike, so the model can change without the harness changing.

## hardening

`av harden`: replacing a tool's own credential handling with a launcher that asks the
vault for approval. A hardened tool keeps no usable secret of its own.

## host

The name of the `darwinConfigurations` attribute the flake builds, taken from
`DOTFILES_HOST`. It is not necessarily the machine hostname: it only names the
configuration in this repo.

## identity

The triple of username, home directory and host the configuration is built for.
`identity.nix` reads it from the environment at evaluation time, so the same clone
configures whoever runs `./rebuild.sh`.

## inject

`av inject NAME -- command` runs a command with one vault secret in its environment for
the life of that process. It is how secrets reach tools here: nothing becomes ambient in
the shell.

## isotope

A signed Homebrew formula or cask shipped by a tap; the one used here is
`automic-vault/isotopes`. Homebrew loads it only because the cask entry is fully qualified
and `trusted`.

## principle skill

One leaf skill under `home/.agents/skills/software-engineering-principles`, vendored from
pstack (MIT, Lauren Tan) and linked into `~/.agents/skills`. It keeps
`disable-model-invocation: true`, so it loads only on request; the local
`engineering-principles` skill is the index that makes it apply, and `home/AGENTS.md` makes
that index mandatory.

## rendered file

A file whose content Nix generates, unlike a linked file that only points at the repo.
Rendered files need `./rebuild.sh` after an edit; linked files do not.

## scan finding

A result reported by `av scan`, with a severity such as HIGH or medium. A finding is
fixed, accepted with a reason, or left as a manual step.

## Secret Custody

The Automic Vault store that holds every secret this machine needs, behind its own
approval. Tools read from it through `av inject`; the secret itself is never written to a
dotfile.

## seeded file

A file Nix writes once into `$HOME` as a real, user-owned file and then leaves alone on later
rebuilds, because the application itself writes it. VS Code's `settings.json` is the only
one: its atomic saves cannot write through a link into the read-only store, so a rebuild
seeds it only when it is missing or still the old store link.

## supervision branch

Firstmate's second conversation, beside the captain's chat, that triages fleet wakes in a
model and escalates only what the captain should see. This repo pins it to
`deepseek/deepseek-flash` at `low` effort through `home/firstmate/supervision-branch-*`,
while the captain's own conversation keeps `settings.json`'s model and effort.

## tap

A Homebrew repository of formulae and casks outside homebrew-cask, declared here as
`automic-vault/isotopes`. Its content is pinned as a flake input and stays mutable on
disk; see [ADR-0001](docs/adr/0001-homebrew-taps-stay-mutable.md).
