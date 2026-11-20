# 0009. The crew tooling is Nix-owned, and firstmate is the one mutable tree

- Status: Accepted
- Date: 2026-11-20

## Context

The crew needs eight command-line tools: five `*-axi` CLIs, `chrome-devtools-mcp`,
`treehouse` and `no-mistakes`. None of them was owned by this repo. Five came from
`npm install -g` into `/opt/homebrew/lib/node_modules`, two from `curl | sh` installers that
wrote into `~/.local/bin`, and the MCP server floated on `npx -y ...@latest` every time
`chrome-devtools-axi` shelled out to it. `node` came from Homebrew while every other
dependency came from Nix.

Nothing on the machine recorded which bytes it ran. The README listed versions as prose, and
running the same install commands on a second machine resolved different versions with no
check. `no-mistakes` additionally runs a daemon whose LaunchAgent embedded
`~/.no-mistakes/bin/no-mistakes`, a path a Nix bump cannot move.

firstmate is different: it is a git clone at `~/firstmate` that updates itself with
`/updatefirstmate`, and home-manager links files into its `config/`. That created a
clone-before-rebuild ordering trap: run `./rebuild.sh` first and activation creates
`~/firstmate/config/`, after which `git clone` refuses the non-empty directory and the
documented recovery is `rm -rf ~/firstmate`.

## Decision

**Every tool binary is a Nix derivation; firstmate stays a clone.**

- `nix/crew-tools/` holds the whole seam. `pins.nix` is the one data surface (version and
  hash per artifact, per-system hashes for the two release binaries). `builders.nix` has two
  shapes — `npmCli` and `releaseBinary` — and no per-tool copies. `locks/<tool>/package-lock.json`
  records the resolved npm tree. `update.sh` is the only writer of any of it.
- npm CLIs are built from the **published tarball** by sha256, with dependencies installed
  from the committed lock, no registry access at build or run time, and no install scripts.
  The tarballs already ship `dist/`, so nothing is compiled.
- `treehouse` and `no-mistakes` are fetched as release assets by per-system hash, taken from
  each release's published `checksums.txt`. The npm CLIs are platform independent; the
  release table carries `aarch64-darwin`, `x86_64-darwin`, `aarch64-linux` and `x86_64-linux`
  so the same set can feed a Linux image later.
- `crew-tools.nix` is the seam `home.nix` imports, separate from `tools.nix`, so `nix develop`
  does not carry a second Node runtime and stays darwin-independent.
- `nodejs_24` replaces the Homebrew `node` formula, so the CLIs and their runtime are pinned
  together. 24 satisfies every engine floor and is supported until 2028-04-30; move to 26
  before then.
- `no-mistakes`' LaunchAgent is declared in `home.nix` with `launchd.agents` and points at the
  store binary. The attribute name has to equal `Label`, because home-manager boots an agent
  out by its plist filename. Home-manager re-bootstraps an agent whose plist changed, so a
  bump restarts the daemon on the new binary.
- `rebuild.sh` establishes the firstmate clone before it builds, over HTTPS (a fresh machine
  has no SSH key or vault yet). An existing checkout is left alone and its HEAD is compared to
  `home/firstmate/expected-commit`; drift is **reported, not enforced**. The pin is applied at
  clone time only, after checking it is an ancestor of the fork's default branch, so
  `/updatefirstmate` can still fast-forward.
- The clone source is the fork `aditya-sathish-rao/firstmate`, with upstream added as a second
  remote. A bump means reading the upstream diff, merging it into the fork, then updating the
  pin. This is the one place the repo does not take upstream's word for it.

## Consequences

- `command -v` still depends on `PATH` order, so the switch and the deletion are separate
  steps. Activation installs the pinned tools first; the legacy npm globals,
  `~/.local/bin/{treehouse,no-mistakes}` and `~/.no-mistakes/bin` are deleted only after a
  one-week soak, because `~/.local/bin` is first on `PATH` and would otherwise keep shadowing
  the profile. A failed switch is cheap to reverse; a premature delete is not.
- `treehouse update`, `no-mistakes update` and the `update` subcommands of the axi CLIs try to
  replace their own binary in a read-only store and fail. The bump path is
  `nix/crew-tools/update.sh`, and that is what the README says.
- The daemon keeps its own state in `~/.no-mistakes`, independent of the binary's path, so the
  store binary is a drop-in once the installer's managed service is uninstalled.
- `update.sh` runs by hand, outside any agent sandbox. A sandbox that can mount this repo could
  otherwise edit its own pins, which is the failure mode the pinning exists to remove.
- `chrome-devtools-mcp` is pinned but Chrome itself is not: packaging the server does not
  package the browser, which stays a manual dependency.
