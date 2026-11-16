# Glossary

The words this repo uses in its own, narrow sense.

## check

The tracked `.githooks/check` module that formats and lints this repo. `--staged` is the
default and what git runs through `.githooks/pre-commit`; `--all` checks every tracked
file and also evaluates the flake.

## crewmate

An agent a first mate spawns for one task, in its own herdr tab and git worktree. Here it is
opencode on DeepSeek V4.1 Flash, chosen by `home/firstmate/crew-dispatch.json`.

## dotfiles link

The symlink `~/.dotfiles` that points at the clone. Every config path in this repo
resolves through it, so `home.nix` can name files without knowing where the clone lives.

## first mate

The Claude Code session started by `mate` inside `~/firstmate`. It is the only agent you talk
to: it turns a request into parallel tasks and hands them to crewmates.

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

## tap

A Homebrew repository of formulae and casks outside homebrew-cask, declared here as
`automic-vault/isotopes`. Its content is pinned as a flake input and stays mutable on
disk; see [ADR-0001](docs/adr/0001-homebrew-taps-stay-mutable.md).
