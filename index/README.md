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

Rollup rules (ADR-0006 items 7 and 8): join on `session_id`; when a session
appears both as a `session` event and inside a run record, cost and usage come
from the run record and tool counts and compactions from the session event,
never both. Queries are DuckDB SQL over the monthly files.
