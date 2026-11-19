# 0007. Engineering principles are skills, indexed by a local router

- Status: Accepted
- Date: 2026-11-19

## Context

The pstack engineering principles (MIT, Lauren Tan) are vendored under
`home/.agents/skills/software-engineering-principles/`, one leaf skill per principle. Two
things stop them from applying in ordinary work:

- They are nested one level below a skill root. Pi discovers directories recursively, but a
  harness that scans a skill root one level deep never sees them, and a harness without skills
  never sees them at all.
- They carry `disable-model-invocation: true`, so even pi loads one only when a human types
  `/skill:principle-*`.

The goal is the opposite of both. Every agent and every harness should work by these
principles without the human invoking each one.

## Decision

- The vendored leaves stay unedited. Editing them would fork them from upstream and be lost on
  the next copy, so the fix lives outside them.
- A local, first-party skill, `engineering-principles`, sits beside the bundle. It is
  model-invocable and carries the trigger index: when work matches a principle, read that leaf
  skill, then name the principles that changed a decision. It routes instead of restating the
  rules, and says the bundle is authoritative so a newly added principle is not blocked by a
  stale index.
- `home.nix` links every directory under `home/.agents/skills` one level deep into both
  `~/.agents/skills` (pi and Copilot) and `~/.claude/skills` (Claude Code). Adding a skill is
  adding a directory. The nested bundle comes along as one link.
- `home/AGENTS.md`, the file every harness reads, names the bundle and the index as mandatory.
  This is the layer that reaches a harness with no skill support.

## Consequences

- The principles apply in three ways: the index skill auto-loads in a skill-aware harness,
  AGENTS.md points any other agent at the bundle, and `/skill:principle-*` still works for a
  human who wants one principle on demand.
- The index is hand-written and can lag the bundle. It says so, and tells the agent to read any
  `principle-*` directory it omits.
- Skill-aware harnesses carry one more skill description in their system prompt, and pi also
  advertises the leaves as explicit commands. That is the cost of automatic application.
- A harness that ignores both AGENTS.md and `~/.agents/skills` gets nothing, and no file here
  can reach it.
