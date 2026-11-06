# Cross-project work record

`index/work-record.json` is the one place that answers "where does every
project stand" without opening each repo. It is a **read-only aggregate**: the
sources of truth stay in each project's `.harness/` and `.council/` and in
auto-mate's run records. The archivist rebuilds it on every firing
(`archivist/briefing-task.md`) with `scripts/build-index.py` (Phase 3
deliverable; see `PLAN.md`).

## What it reads, per project

| Source file | Fields taken |
|---|---|
| `.harness/sprint-state.json` | `current_sprint`, `current_phase`, latest sprint `status`, `last_updated` |
| `.harness/config.json` | `project_type`, `rubric`, `governance.enabled` |
| `.harness/progress.md` | last session line (resumption note) |
| `.council/state/effective-autonomy.json` | `level`, `reason`, `restored_when` |
| `.council/henka-register.jsonl` | open records (latest entry per `henka_id` with `status != closed`), count of `impact_level: high-risk` |
| `.council/proposed/*.md` (not in `archive/`) | pending position papers and persisted plans |
| `.council/sprint-prebrief/sprint-NN.json` | latest `cynefin`, `confidence`, `expected_loop_shape` |
| `<auto-mate workspace>/runs/*.json` | run records for the repo; verdicts not yet ingested into the ledger |
| `inbox/<project>/` (this repo) | captures filed from Drive, newest first |
| `.council/diagnostics.jsonl` and `runs/*.json` | diagnostic events (ADR-0006); copied into `index/diagnostics/events-<YYYY-MM>.jsonl` and rolled up into the project's `diagnostics` block |

## Derived signal: `signals.state`

One label per project, derived in this order (first match wins):

1. `halted`: the latest henka record has `response_type` in `andon-stop`, `no-progress`, `resource-cap` and is not closed, or the effective autonomy level is 2 or lower.
2. `diverging`: either of the last two sprints is `FAIL`, or the latest prebrief is `chaotic` with confidence at or above 0.6, or two or more open high-risk henka records exist.
3. `converging`: the latest sprint is `PASS` and no open record is `blocking` or `high-risk`.
4. `idle`: no change to any source file in 14 days.
5. `unknown`: otherwise.

`signals.reasons` lists the evidence lines that fired, each as `file:field=value`,
so the briefing can cite them and a reviewer can re-run the check.

## `decisions_pending`

Everything that needs a human, ranked. Kinds map to the council's own approval
types where one exists (`human-approval-log-entry.schema.json`):
`nemawashi-major`, `minor-correction`, `autonomy-restore`, `yokoten-ratification`,
`standard-work-proposal`; plus `scope-ratification` (a plan or contract awaiting
the approval entry that auto-mate requires, see ADR-0003) and `gate-decision`
(a Discovery Gate package in `requires-revision` or `human-escalate`). Rank:
halts first, then autonomy restores, then anything blocking a sprint, then the rest
by age.

## `index/diagnostics/`

The cross-project diagnostic event store (ADR-0006): one JSONL file per month,
events validated against `diagnostic-event.schema.json`, deduplicated by
`event_id`, append-only, committed on the `work-record` branch. The archivist
copies session events from each repo's `.council/diagnostics.jsonl` and derives
run, crew and gate events from persisted run records. `docs/queries.md` (Phase 3)
documents one query per question listed in ADR-0006, so a pattern study starts
from a known-good query rather than from raw files.

Rollup rules (ADR-0006 items 3 and 7 as amended by A1, and item 8). Queries are
DuckDB SQL over the monthly files.

- **Sum, never "latest".** A `kind: session` event (schema 1.1) is one process
  lifetime of one session that has ended: settled (its closing `cost-state`
  exists; `outcome: ended`) or interrupted (none was written;
  `outcome: interrupted`). Its measures are deltas. A session's total is the
  sum of its events (`GROUP BY session_id`); a day, month or 7- or 30-day
  window is the sum of the events whose `ts` falls in it, except that a
  lifetime with `lifetime.days` is split by those bins (see "Time and sprint").
  A session's latest event is never its total. Per-session figures divide by
  the distinct `session_id`s.
- **Dedupe first.** Event ids are deterministic, so one lifetime can arrive from
  its `SessionEnd`, a later `SessionStart`, a backfill or another branch. Keep
  one copy per `event_id`: the higher `lifetime.spec`, then `recovered: none`
  over a recovered copy, then the more complete `lifetime.coverage`.
- **Anchors are never summed.** `lifetime.cost_lineage`, `cum_cost_start_usd`
  and `cum_cost_end_usd` are for the chain check: within a lineage, each event's
  `cum_cost_start_usd` is 0 or an earlier event's `cum_cost_end_usd`. A
  difference is the exact cost of lifetimes missing from the file tier; their
  tokens are unknown.
- **Null cost is not zero.** `cost_usd: null` (an interrupted lifetime, or a
  fork whose parent was not found) is reported as unpriced tokens. No price
  table fills it. A future estimate from historic data is computed at read
  time, labelled as an estimate, and never summed with `claude-code-estimate`.
- **Coverage next to every sum:** unpriced lifetimes and their tokens, chain
  gaps in dollars, lifetimes with a `lifetime.coverage.shortfall`, and sessions
  with audit-log activity after their last settled lifetime. Inferred: in the
  cloud that last count is the trace of a lifetime whose event never reached
  git.
- **OpenTelemetry backstop for cloud sessions.** Once the archivist reads the
  backend (P3-CC-1), for a session in that last count it takes the spend after
  its last settled lifetime from the backend's `api_request` events, matched by
  `session.id` and time (ADR-0006 item 4 as amended), labels it
  `cost_source: backend` and reports it apart. The file tier wins for every
  lifetime it holds: when the lifetime's own event arrives, the backend figure
  for it is dropped.
- **Crews (item 7 as amended).** With `AUTOMATE_RUN` set, council hooks write
  nothing, so crews and gates have no session event. Join on `session_id`: a
  run record covers its session's first lifetime, so cost and usage come from
  the run record; tool counts and compactions come from the lifetime event the
  run record is to carry, and are missing (not zero) until it does. Runs
  flagged `session_id_inherited` join on `task_id`, not `session_id` (PLAN.md
  section 7). A crew or gate that auto-mate kills at its timeout has no usage
  in its run record and no session event, so its spend is in no event or
  record. A later lifetime of the same session, such as a human resume, is an
  ordinary session event; the chain-check gap before it is the crew lifetime,
  already in the run record.
- **Time and sprint.** A lifetime sits in the monthly file of its `ts`, its
  latest own entry, and counts whole toward the sprint of its `ts`;
  `lifetime.sprint_at_start` flags a lifetime that began in an earlier sprint.
  `lifetime.days`, present only for a lifetime that crosses UTC midnight,
  splits its tokens and cost by UTC day; a day, month or window sum uses those
  bins in place of `ts`, never both.
