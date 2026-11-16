# 0002. Claude Code gets no hardener

- Status: Accepted
- Date: 2026-11-16

## Context

Automic Vault offers two things for a tool that holds credentials: `av harden`, which
replaces the tool's credential handling with a launcher that asks the app for approval,
and `av scan` detectors that flag known leak patterns.

`av hardeners --json` lists aws, brew, gh, codex and others, but no claude. `av scan` has
no Claude detector, so it never flags `~/.claude/settings.json`.

Claude Code reads its credentials from an environment variable, and routing to OpenRouter
is also an environment variable (`ANTHROPIC_BASE_URL`). A tracked `env` block in
`~/.claude/settings.json` would make that routing ambient for every `claude` launch,
including launches that have no key.

## Decision

Do not treat Claude Code as a hardened target, and do not wait for a Claude detector.

Keep the token in Secret Custody and reach the process through `av inject` in the `cc`
alias:

```sh
cc   # av inject +ANTHROPIC_AUTH_TOKEN -- env ANTHROPIC_BASE_URL=https://openrouter.ai/api claude --dangerously-skip-permissions
```

Both the key and the routing URL are supplied by the alias, so the tracked
`home/.claude/settings.json` carries no `env` block and a bare `claude` cannot reach
OpenRouter without a key.

## Consequences

- No secret is written to a dotfile, and the token is not exported into the shell.
- Every `cc` launch asks the vault, so the token is injected per process. The terminal is
  allowed once, in manual step 4, so it does not prompt after that.
- Nothing gates Claude Code the way a hardened tool is gated. `av scan` will never flag
  this file, so the policy has to be upheld by review rather than by a finding.
- Routing lives in the alias, not in the tracked file, so the secrets rule holds without
  an exception: no `env` block at all.
