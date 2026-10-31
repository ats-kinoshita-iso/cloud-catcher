# ADR 0001: Runtime stays on Claude Code through Phase 4; revisit for the headless path at the Phase 5 gate

- **Status:** Proposed
- **Date:** 2026-10-31
- **Author:** cloud-catcher bootstrap (planning session)
- **Scope:** Which runtime hosts each layer of the stack for v1, and the criteria for changing that

---

## Context

Three runtime families could host the stack:

1. **Claude Code**: plugins for the interactive path (trine-eval, henkaten-council, and
   Google's Elephant-Goldfish plugin), headless `claude -p` for execution (what auto-mate
   drives), and cloud sessions with scheduled tasks for anything that must run unattended.
2. **Managed Agents** (Anthropic-hosted): persisted agent configs, per-session sandboxes,
   memory stores, scheduled deployments, graded outcomes, credential vaults, and
   dollar-denominated session budgets. Several of these overlap what the plan would
   otherwise build by hand (containment, cross-project memory, scheduling).
3. **Self-hosted runtimes**: the Claude Agent SDK, DeepSeek Harness (`dsh`), Harness².

Facts that constrain the choice (checked 2026-10-31):

- Every existing component is a Claude Code plugin or drives `claude -p`. henkaten-council's
  enforcement is Claude Code hooks; trine-eval's trial loop uses the native Workflow runtime.
- The August 2026 stack review judged the Agent SDK worthwhile for auto-mate's crew backend
  "only when subprocess parsing becomes the limiting factor", and found no native equivalent
  for the contract format, regression graduation, ledgers, or safe-push.
- It is not yet confirmed which surface draws down the API credits. Headless `claude -p`
  authenticated with an API key bills the console organization; cloud sessions on claude.ai
  are believed to bill the plan. This is an inference until the Phase 0 check in `PLAN.md`
  records the answer below.

## Decision

1. **Claude Code is the runtime for all three layers through Phase 4.** Interactive scoping
   and governance run as plugins. Headless execution runs through auto-mate. The archivist
   runs as a cloud scheduled task with the Google Drive connector.
2. **The headless execution path is re-evaluated at the Phase 5 gate**, against Managed
   Agents only. Migrate that path if at least three of these hold:
   - credits: Managed Agents confirmed to draw the credits the user wants to spend, and the
     `claude -p` path confirmed not to under the chosen authentication;
   - containment: session budgets and vault credentials make the hand-built caps of
     sprint `P5-AM-4` unnecessary;
   - lifecycle: worktree, gates and safe-push (or equivalents) are reachable from the
     per-session sandbox, so auto-mate's lifecycle survives as an adapter behind
     `CrewRunner` and `ShipGate`;
   - cost: cost per completed task is at or below the `claude -p` path at equal pass rate on
     the Phase 1 five-task set;
   - memory: memory stores cover the retrieval misses the archivist has logged.
3. **DeepSeek Harness and Harness² are not adopted as runtimes.** Their ideas are adopted as
   disciplines: "model-visible means logged" is met by the Claude Code transcript plus the
   repaired audit hook (sprint `P0-HC-1`); Propose, Probe, Compose enters only through the
   council's retrospective to nemawashi to standard-work pipeline, human-ratified and logged
   as `change_origin: active` henkaten, never as an autonomous loop (a high-risk active henka
   drops the floor to Level 1 by the council's own third trigger).

## Alternatives considered

- **Migrate to Managed Agents first.** Rejected for v1: it re-platforms every component
  before measuring, and the components' enforcement surface (hooks) does not transfer.
- **Self-host on the Agent SDK or `dsh`.** Rejected: nothing in the measured failure modes
  (August review §2) is caused by the runtime; they were plumbing and sensor defects.

## Consequences

- Containment stays thin until Phase 5: timeouts, `--max-turns`, disallowed tools, and
  resource-cap henkaten on timeout. Dollar budgets per task arrive only with a Managed Agents
  or SDK path.
- Plugins remain the integration surface, so a later migration of the headless path is one
  adapter, not a rewrite.
- The composition manifest records the runtime decision and its revision date.

## Verification

- Phase 0 billing check: run one headless task with the API key set, confirm the usage line
  in the Console, and record the result here as an addendum with the date.
- Phase 5 gate: the five criteria above, each with its measurement cited.
