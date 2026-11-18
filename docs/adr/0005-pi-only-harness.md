# 0005. One harness, pi, with the model as the only variable

- Status: Accepted
- Date: 2026-11-18
- Supersedes: [ADR-0002](0002-no-claude-hardener.md)

## Context

The crew ran two harnesses: Claude Code as the first mate, and opencode as the crewmate
harness. Claude Code read and wrote far more tokens than the work justified, and paying that
as an always-on first mate made ordinary projects expensive. Two harnesses also meant two
provider configs, two launch paths, and two ways for a key to reach a process.

What the crew needs from a harness is a model, a tool loop, and an extension surface
firstmate can supervise. It does not need a particular vendor's CLI.

## Decision

Run pi everywhere, for the first mate and every crewmate, and keep the model a value:

- pi comes from its own flake input (`pi.url` in `flake.nix`), pinned by `flake.lock`. Its
  package ships the Node runtime and model catalog, so the harness is declarative and no
  global npm install exists. `homebrew.onActivation.cleanup = "zap"` then removes any cask
  or formula that used to provide one.
- The model lives in `~/.pi/agent/settings.json` (`defaultProvider`, `defaultModel`,
  `defaultThinkingLevel`), linked from this repo. Crewmates inherit it because
  `crew-dispatch.json` names the harness and provider but not the model. Trying another
  model is a one-file edit and needs no rebuild.
- `crew-dispatch.json` declares one profile, `{ "harness": "pi", "provider": "deepseek" }`,
  with `shared_quota: true`. There is no fallback profile: one provider, one budget.
- The DeepSeek key comes from Automic Vault. `mate` injects it into the first mate; a
  crewmate pane starts without it, so the `~/.local/bin/pi` wrapper re-runs itself under
  `av inject` and each worker holds the key only for its own lifetime.

## Consequences

- The first mate costs what DeepSeek costs, and it is one file edit away from a different
  model.
- One harness means one set of extensions, one launch shape, and one place a key enters.
- Pi reads global instructions from `~/.pi/agent/AGENTS.md`, not `~/.claude/CLAUDE.md`, so
  `home.nix` links `home/AGENTS.md` there. The `~/.claude` links are kept for an agent that
  still looks there.
- The `-axi` SessionStart hooks that target Claude Code, Codex, OpenCode and Copilot CLI do
  not reach pi. Pi discovers skills instead, which is why `lavish` lives in
  `~/.agents/skills` and is read from there.
- Pi has no hardener, exactly as Claude Code had none, so the rule from ADR-0002 still
  holds: the key is injected per launch and never written to a tracked settings file.
- Moving the harness or its bundled model catalog is `nix flake update pi`, then
  `./rebuild.sh`.
