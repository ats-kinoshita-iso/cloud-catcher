# ADR 0006: Diagnostics: one event schema, two capture paths, one place to study

- **Status:** Proposed
- **Date:** 2026-10-31
- **Author:** cloud-catcher bootstrap (planning session), at the human's request after ratifying ADR-0001 to 0005
- **Scope:** What the stack records about its own behavior (tokens, cost, time, tool use, outcomes), where, with what privacy, and how the record drives improvement

---

## Context

The request: diagnostic logs so that token usage and common patterns can later be studied
and drive improvements. What exists today (checked 2026-10-31):

- **Claude Code transcripts** carry `message.usage` on every assistant entry (input,
  output, cache-read and cache-creation tokens), plus `sessionId`, `effort`, `requestId`,
  `isSidechain` (subagent marker), `gitBranch`, `cwd` and `thinkingDurationMs`. Hooks receive
  `session_id` and `transcript_path`. Verified on this session's own transcript.
- **`claude -p --output-format json`** returns `session_id`, `total_cost_usd` with a
  per-model breakdown, usage, duration and turn counts; `stream-json` adds `api_retry`
  events, `permission_denials`, and `parent_tool_use_id` for subagent attribution.
- **Claude Code OpenTelemetry export** is documented: metrics `claude_code.token.usage` and
  `claude_code.cost.usage` with attribution attributes, events `api_request`, `tool_result`,
  `tool_decision`, `api_error`. Prompt text is redacted by default. Exporter variables are
  honored from the environment or managed settings only, not from a repo's settings files.
- **henkaten-council** has `audit-log.jsonl` (one entry per tool call; no `session_id` field
  today), a Stop hook that only writes a progress marker, `measure-projection-cost.py`
  (token estimate of the always-projected file set), and a rotation script.
- **trine_eval** has `TokenUsage`, cost caps, a price table and token-efficiency metrics for
  its own eval runs; harness transcripts record evaluator tool calls but not token usage.
- **auto-mate** captures agent stdout but parses nothing from it; run records are not persisted
  (ADR-0002 fixes persistence).

Nothing joins these: a sprint's cost, a run's token split, a session's compaction count and a
henka record cannot be put on one row.

## Decision

1. **One event schema.** `index/diagnostic-event.schema.json` defines a flat JSON event with
   an envelope (`event_id`, `ts`, `source`, `kind`, `project`, `schema_version`), join keys
   (`session_id`, `task_id`, `run_path`, `sprint`, `agent_name`, `tool_use_id`, `henka_ids`,
   `approval_id`, `git_branch`), measures (`model`, `effort`, `usage`, `usage_by_model`,
   `cost_usd` with `cost_source`, `duration_ms`, `num_turns`, `counts`, `outcome`, `cap_hit`)
   and free-form string `labels`. Every producer writes this shape; nothing else is a
   diagnostic.
2. **Two capture paths, both file-based and git-tracked.**
   - *Interactive sessions* (council plugin): a `SessionEnd` hook sums the transcript's
     `message.usage` by model and effort, splits sidechain (subagent) usage, counts tool calls
     by tool from the session's audit entries, counts compactions (`PreCompact`) and subagents
     (`SubagentStart`), reads the current sprint from `.harness/sprint-state.json`, and
     appends one `session` event to `.council/diagnostics.jsonl`. The audit log gains
     `session_id` and `tool_use_id` so tool-call sequences can be joined to sessions.
     `measure-projection-cost.py` appends a `projection-cost` event when run.
   - *Headless runs* (auto-mate): crews and gates run with `--output-format json`; the
     adapter parses `session_id`, `total_cost_usd`, usage, duration and turns into
     `CrewResult.usage` and `Verdict.usage`, and the persisted run record carries them. The
     archivist derives `run`, `crew` and `gate` events from run records.
   - *Eval runs* (trine_eval library): the runner's `TokenUsage` and cost are already in
     `EvalLog`; `harness-summary` reads session events to report cost per sprint and per PASS.
3. **One place to study.** The archivist copies every new event into
   `index/diagnostics/events-<YYYY-MM>.jsonl` (deduplicated by `event_id`, append-only,
   committed on the `work-record` branch) and writes rollups into each project's
   `diagnostics` block of the work record: tokens and cost for the last 7 and 30 days by
   source, cost per shipped run, cost per PASS sprint, cache share of input, tool failure rate,
   compactions per session, subagent count per session.
4. **Second tier, optional: OpenTelemetry export.** When a backend is chosen (Level 5),
   cloud environments and local shells set `CLAUDE_CODE_ENABLE_TELEMETRY=1`, OTLP exporters,
   and `OTEL_RESOURCE_ATTRIBUTES=project=<repo>,layer=<crew|gate|council|archivist>`. The
   file-based tier stays authoritative; the backend is for queries the files make slow.
5. **Privacy and retention.** No prompt or response bodies in any event; summaries are
   capped at 160 characters as the audit log already does; `OTEL_LOG_USER_PROMPTS` stays
   unset. `.council/diagnostics.jsonl` is append-only under the same hook as the other
   ledgers and rotates with the same script. Retention of raw events follows
   `config.transcripts.retain_days` in the repo; rollups are kept indefinitely.
6. **How the record drives improvement.** Through the channels that already exist, with the
   data added as an input: the retrospective agent in `pdca` mode reads the project's rollup
   and the last cycle's events; `harness-summary`'s ACI section cites cost and consistency
   together; standard-work proposals that come out of either go through nemawashi as today.
   The questions the data must be able to answer are listed below and are the acceptance test
   for the schema.

## Questions the data must answer

1. Cost and tokens per shipped task and per PASS sprint, by project type and rubric.
2. Cache share of input tokens per source (how much of the prompt is being paid for twice).
3. Tool-call distribution and failure rate by tool, per session kind.
4. Compactions per session against sprint size (the HK-0051 truncation family).
5. Sessions with sidechains that produced no verdict (the HK-0035 stall family).
6. API retries and permission denials per run.
7. Gate verdict reasons, clustered, over time.
8. Henka categories and andon signals per sprint over time, next to cost.
9. Effort level against outcome and cost.
10. Approval latency: time from a plan or contract being persisted to its approval entry.
11. For research and quant sprints: traceability failures per report, parity-test failures per spike.

## Alternatives considered

- **OpenTelemetry only.** Rejected as the first tier: it needs a reachable backend from every
  environment, cannot be configured from repo settings, and leaves nothing in git for the
  archivist or the retrospective to read.
- **Parsing the console exporter.** Rejected: its format is not a stable contract.
- **A metrics database now.** Rejected: measure first; the rollups decide what a database
  would need to hold.

## Consequences

- Every producer gains one small writer; no producer gains a dependency on a service.
- `session_id` becomes the join key across audit entries, diagnostics, run records and the
  OTel tier.
- The retrospective and harness-summary get quantitative inputs they lack today.

## Verification

- Schema fixtures: one valid and one invalid event per `kind`.
- A governed fixture session ends with exactly one `session` event whose token totals equal
  the sum over the transcript's assistant entries.
- A headless fixture run yields a run record whose crew and gate usage are non-null, and the
  archivist derives `run`, `crew` and `gate` events from it with the same `task_id`.
- The eleven questions above each have a documented query over `index/diagnostics/`.
