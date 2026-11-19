---
name: engineering-principles
description: The engineering principles this machine works by. Load before designing, debugging, refactoring, reviewing, testing, or declaring work done, then read the leaf skill for every principle whose trigger matches. Use for architecture and type decisions, bug fixes, migrations, multi-step delivery, verification, and agent delegation.
user-invocable: true
---

<!-- maintainers: this index is local and hand-written. The leaf skills in
../software-engineering-principles are vendored byte-for-byte from pstack (MIT, Lauren Tan);
do not edit them, re-copy them instead. -->

# Engineering principles

These principles govern engineering work here. They bind every agent, every harness, and every
task, including harnesses that do not surface skills. This file is the index, not the rules.

## Apply it

1. Match the work against the triggers below.
2. Read every matching leaf skill in full at `~/.agents/skills/software-engineering-principles/<name>/SKILL.md` before acting on that principle.
3. Name each principle that changed a decision, and say what it changed. Cite only principles you read this session.
4. When two principles pull against each other, say which one you chose and why.

The bundle is authoritative. If a `principle-*` directory exists that this index does not
list, read its `description` and follow it too.

## Core

- **Laziness protocol** (`principle-laziness-protocol`). Refactoring, sizing a diff, or tempted to add an abstraction, a layer, or signal threading. Bias to deletion and the smallest change that solves the problem.
- **Foundational thinking** (`principle-foundational-thinking`). Before writing logic, when choosing core types and data structures, sequencing scaffold against feature work, or asking what concurrent actors share.
- **Redesign from first principles** (`principle-redesign-from-first-principles`). Integrating a new requirement into an existing design. Redesign as if it had been foundational from day one.
- **Attack the premise** (`principle-attack-the-premise`). Two or more fixes that share one premise have failed the same gate. Write the premise down and test it directly before writing another fix that assumes it.
- **Subtract before you add** (`principle-subtract-before-you-add`). Sequencing an addition, refactor, or rewrite. Remove dead code, redundant validators, and stub references first, then build on the simpler base.
- **Minimize reader load** (`principle-minimize-reader-load`). Reviewing or shaping code that is hard to trace. Count the layers between question and answer, collapse one-caller wrappers, shrink mutable scope.
- **Outcome-oriented execution** (`principle-outcome-oriented-execution`). Planned rewrites and migrations with phase boundaries. Converge on the target architecture and do not preserve throwaway compatibility states.
- **Experience first** (`principle-experience-first`). Product, UX, or feature-scope tradeoffs. Prefer user delight over implementation convenience, and fewer polished features over more rough ones.
- **Exhaust the design space** (`principle-exhaust-the-design-space`). A novel interaction or architectural decision with no precedent in the codebase. Build two or three competing prototypes and compare them before committing.
- **Build the lever** (`principle-build-the-lever`). Any non-trivial work, not just bulk work. Build the codemod, script, generator, or skill that does or proves it instead of working by hand.

## Architecture

- **Model the domain** (`principle-model-the-domain`). Writing stateful logic, or code that branches a lot or repeats a shape assumption across files. Encode the domain in a structure instead of scattered conditionals.
- **Boundary discipline** (`principle-boundary-discipline`). Wiring validation, error handling, or framework adapters. Concentrate guards at system boundaries, trust internal types, and keep business logic in pure functions.
- **Type system discipline** (`principle-type-system-discipline`). Designing types, reviewing a signature, or writing any statically typed language. Make illegal states unrepresentable, brand semantic primitives, parse external data at boundaries.
- **Make operations idempotent** (`principle-make-operations-idempotent`). Designing commands, lifecycle steps, or processing loops that run amid crashes, restarts, and retries. Converge to the same end state regardless of partial prior runs.
- **Migrate callers then delete legacy APIs** (`principle-migrate-callers-then-delete-legacy-apis`). Introducing a new internal API while old callers still exist. Migrate the callers and delete the old API in the same wave.
- **Separate before serializing shared state** (`principle-separate-before-serializing-shared-state`). Concurrent actors might write the same file, branch, key, or state object. Eliminate the sharing first, and serialize structurally only when one shared writer is a real invariant.

## Verification

- **Prove it works** (`principle-prove-it-works`). After a task, before declaring it done. Verify against the real artifact, not a proxy, a self-report, or "it compiles".
- **Fix root causes** (`principle-fix-root-causes`). Debugging. Trace each symptom back to the first place the system went wrong and fix it there.
- **Sequence verifiable units** (`principle-sequence-verifiable-units`). Multi-step work, sweeps, migrations, and how commits and PRs stack. Each unit ends in a verifiable state, checked before the next.
- **Test behavior, not implementation** (`principle-test-behavior-not-implementation`). Writing, changing, or keeping a test. Assert what the code's users can observe against a literal expected value, so the test fails when the behavior breaks and survives an internal change.
- **Explain the number** (`principle-explain-the-number`). Before measuring, and before trusting, reporting, or acting on a measured speedup, regression, throughput, latency, or eval result. Find what limits it and rule out that it measured a proxy.

## Delegation

- **Guard the context window** (`principle-guard-the-context-window`). Context is filling up from large outputs, long files, repeated reads, or fan-out planning. Route bulk to subagents and keep summaries in the main thread.
- **Never block on the human** (`principle-never-block-on-the-human`). Tempted to ask "should I do X?" on reversible work. Proceed, present the result, and let the human course-correct. Irreversible actions still need confirmation.

## Meta

- **Encode lessons in structure** (`principle-encode-lessons-in-structure`). Writing the same instruction a second time, or noticing a recurring correction. Encode the rule as a lint, a metadata flag, a runtime check, or a script instead of more text.
