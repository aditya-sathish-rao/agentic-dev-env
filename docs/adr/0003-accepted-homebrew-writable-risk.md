# 0003. The Homebrew writable-prefix finding is accepted

- Status: Accepted
- Date: 2026-11-16

## Context

`av scan` reports one `homebrew` detector finding: `/opt/homebrew` is writable by the
current user. It also reports six medium `PATH` ordering findings, added twice each by
the shell detector and the macOS process detector.

The Homebrew item cannot be cleared by hardening:

- `av harden brew` refuses on this machine. It supports formulae and CLI-only casks, and
  `/opt/homebrew/Caskroom` holds application casks (`automic-vault`, `visual-studio-code`,
  `wezterm`), so it prints `av harden: incompatible Homebrew Casks`.
- Hardening would re-own `/opt/homebrew` as `automic:vault` and replace `brew` with a
  setuid launcher that asks the menu bar app on every call. `nix-homebrew` links managed
  taps into `/opt/homebrew/Library/Taps`, and nix-darwin applies `homebrew.*` through
  `brew bundle` during activation. A hardened, approval-gated `brew` breaks both.

The `PATH` findings are the ordering nix-darwin and `brew shellenv` exist to produce.
`/opt/homebrew/bin` and `~/.nix-profile/bin` are user-writable by design, and the detector
itself calls that expected for version managers.

## Decision

Accept the Homebrew writable-prefix finding as known risk and leave it visible in the
app. `av scan` has no way to acknowledge or suppress a finding, so no code change can
record this decision; this ADR does.

Treat the six `PATH` ordering findings as expected output of the setup, not as defects.

## Consequences

- `av scan` keeps showing one medium item and six medium `PATH` items on every run.
- The boundary accepted here is integrity of the Homebrew prefix for a same-user process,
  not custody of a secret. Secrets stay behind `av inject`; see
  [ADR-0005](0005-pi-only-harness.md).
- Anything installed through `brew` runs as the user, as it already did.
