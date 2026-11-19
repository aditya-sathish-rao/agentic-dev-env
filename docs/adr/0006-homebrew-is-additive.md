# 0006. Homebrew is additive, and this repo owns only the dev environment

- Status: Accepted
- Date: 2026-11-18

## Context

Homebrew activation ran with `cleanup = "zap"`, so this repo owned every cask and formula
on the machine: anything not listed in `configuration.nix` was removed at rebuild, together
with its preferences and support files.

That fits an appliance, where the machine exists to run this configuration. This machine is
not one. It holds a long list of apps that have nothing to do with development, and pinning
them here buys nothing: consumer apps self-update, casks come and go, several are
App Store only (which needs `masApps` and a signed-in account), and one badly behaved cask
fails `brew bundle` before home-manager ever runs. Every casual install would also become a
commit and a rebuild.

Two questions decided this: what the repo is for, and what a rebuild is allowed to delete.
The answer to both is "the dev environment, and nothing else".

## Decision

Set `homebrew.onActivation.cleanup = "none"`.

The repo keeps declaring the tools the dev workflow depends on (`wezterm`,
`visual-studio-code`, `herdr`, `node`, `av`, the hardened `gh-cli` isotope), and Homebrew
installs and upgrades exactly those. Anything else on the machine is the user's, and no
rebuild touches it.

## Consequences

- A rebuild can add and upgrade, but it cannot uninstall. Removing an entry from
  `brews`/`casks` leaves the app on disk on purpose; removing it for real is
  `brew uninstall --cask <name>` or `brew zap <name>` by hand.
- The one-time switch costs the same: the `claude-code` cask from the old harness is not
  pruned by the next rebuild, so it needs an explicit `brew uninstall --cask claude-code`.
- The declared list stops being an inventory of the machine, so drift is expected and
  accepted. `brew bundle check` no longer answers "is this machine per spec", because
  there is no spec for apps this repo does not own.
- The Automic Vault tap keeps `nix-homebrew.mutableTaps = true`, now for `autoUpdate` and
  manual `brew` writes rather than for un-tapping; see
  [ADR-0001](0001-homebrew-taps-stay-mutable.md).
- The Homebrew writable-prefix finding stays accepted; see
  [ADR-0003](0003-accepted-homebrew-writable-risk.md).
