# 0001. Homebrew taps stay mutable

- Status: Accepted
- Date: 2026-11-16

## Context

The Automic Vault cask is not in homebrew-cask, so `configuration.nix` declares
`automic-vault/isotopes` as a tap. `nix-homebrew` can manage taps as store symlinks,
which makes them immutable.

`homebrew.onActivation.cleanup = "zap"` removes anything not listed in `homebrew.taps`,
including a tap that is no longer declared. An immutable store symlink cannot be
un-tapped, so `zap` cannot do its job on it.

Homebrew also refuses to load a third-party cask unless that cask is trusted, and trust
is declared per cask, not per tap.

## Decision

Set `nix-homebrew.mutableTaps = true`, so the tap directory stays writable and `zap` can
un-tap what is no longer declared.

Declare the cask as `automic-vault/isotopes/automic-vault` with `trusted = true`. The tap
itself stays untrusted.

## Consequences

- The tap can be cleaned up and linked on every activation without failing.
- The tap directory is writable by the user, which is part of why the Homebrew
  writable-prefix finding is accepted; see
  [ADR-0003](0003-accepted-homebrew-writable-risk.md).
- The cask entry must stay fully qualified, otherwise the trust flag does not apply.
- Tap content is still pinned as a flake input, so a tap bump is
  `nix flake update automic-vault-tap`, not `brew update`.
