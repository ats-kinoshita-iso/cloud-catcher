# ADR 0002: Governance join: auto-mate reads council state and persists run records; the council ingests them

- **Status:** Proposed
- **Date:** 2026-10-31
- **Author:** cloud-catcher bootstrap (planning session)
- **Scope:** How the headless execution path (auto-mate) and the governance layer (henkaten-council) share state

---

## Context

The stack has two execution paths with different governance strength (checked 2026-10-31):

- The **interactive path**: `/henkaten-council:council-autorun` wraps
  `/trine-eval:harness-sprint`, with ledgers, contracts, trials and the nemawashi gate.
- The **headless path**: `automate run` provisions a worktree, runs a `claude -p` crew, runs
  two prompt gates, and ships through no-mistakes. The governance gate is a prompt that opens
  "You are the henkaten-council governance gate". It reads no `.council/` state and writes no
  henka record. Crews run with `--setting-sources project,local` precisely to keep the
  council's hooks out of the worktree.

So the path a cloud deployment would use is the ungoverned one. Two further facts:

- The council's reversibility table (council-autorun Step 1D.1) classifies `git push` as
  irreversible, which auto-escalates to Level 5. auto-mate's ship stage pushes a branch and
  opens a PR autonomously. The two components disagree about who may push.
- auto-mate's `RunRecord` is printed to stdout and never persisted, so nothing downstream can
  ingest it.

## Decision

1. **auto-mate reads council state; it never writes it.** A small adapter reads
   `.council/state/effective-autonomy.json` and `.council/human-approvals.jsonl` from the
   task repo. A repo without `.council/` is ungoverned and behaves exactly as today.
2. **Ship authority comes from a ratified scope approval** (ADR-0003). The approval entry is
   the Level 5 "explicit prior human approval per action" for two actions under that scope:
   push the task branch and open a draft PR. Merge is never pre-granted. When the effective
   autonomy level is 2 or lower, prior grants are suspended: the crew and the gates still run
   (a branch is a proposal), the ship stage is skipped, the run ends `gated` with the reason
   recorded.
3. **Every run record is persisted** to `<workspace_root>/runs/<repo-slug>/<task-id>-<utc>.json`.
   `Verdict` gains `evidence` (the gate's verdict line and findings) and `autonomy_at_gate`.
   In a cloud environment `AUTOMATE_WORKSPACE_ROOT` points at a cloud-catcher checkout's
   `runs/` directory, and the orchestrating session pushes it to the `work-record` branch at
   the end of the run, so records outlive the container.
4. **The council ingests run records.** A new `scripts/ingest-run-record.py` in henka-council
   maps each record to henka records and appends them through `append-henka.py`:
   `fourM_axis: Method`, `category: gate-verdict`, `change_origin: passive`, `impact_level`
   informational on PASS, actionable on FAIL, blocking when the ship was skipped by the floor,
   `response_type` `log-only` or `propose-to-user`, `detected_by: auto-mate/<gate>`,
   `evidence` citing the run file path and the verdict line. Idempotent on run file path.
   It is invoked by council-autorun Step 1A (pre-sprint henkaten check) and by the archivist.
5. **Gate scripts keep their contract.** They remain stateless prompt reviewers invoked as
   `<gate> <task-id> <branch> <intent> [<base-ref>]`. Their verdicts become ledger-bound
   through the run record, not through writes of their own.

## Alternatives considered

- **Gate scripts append to the ledger directly.** Rejected: two writers to append-only logs,
  and in a cloud clone the append is lost with the container.
- **auto-mate dispatches the council Orchestrator.** Rejected: the Orchestrator is an
  interactive, `context: inherit` agent with human gates; it is not headless-safe.
- **Retire the headless path.** Rejected: it is the cloud path and the only one with a typed,
  dry-runnable lifecycle.

## Consequences

- The split mirrors the council's own rule: Level 1 and 2 agents propose, the Orchestrator
  persists. auto-mate becomes a proposer of ledger entries.
- The push disagreement is resolved by making the scope approval the per-action grant.
- Run records become the durable trace of headless work and a source for the work record.

## Verification

- Fixture repo with `.council/` at Level 1: `automate run --execute` ends `gated`, no push,
  reason names the floor.
- Fixture at Level 4 with a ratified scope: run ships; run record exists; ingest appends one
  henka record per verdict; a second ingest appends nothing.
