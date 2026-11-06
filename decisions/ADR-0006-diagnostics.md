# ADR 0006: Diagnostics: one event schema, two capture paths, one place to study

- **Status:** Accepted (ratified by the human 2026-10-31)
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
   compactions per session, subagent count per session. The study tool is DuckDB over those
   files: it reads JSONL directly, runs locally or inside a cloud session, and needs no
   service. `docs/queries.md` holds one DuckDB query per question listed below, and the same
   queries run over the council ledgers and harness transcripts, which are JSONL too. For
   horizons longer than git comfortably holds, the same monthly files load into BigQuery with
   `bq load`; that is an option, not a dependency.
4. **Second tier, optional: OpenTelemetry export, one endpoint for everything.** Claude Code
   emits metrics (`claude_code.token.usage`, `claude_code.cost.usage`) and events
   (`api_request`, `tool_result`, `tool_decision`, `api_error`), so the backend must ingest
   OTLP **metrics and logs**, not only traces. The recommended default is Grafana Cloud: one
   OTLP endpoint for both signals, time-series dashboards for cost and tokens, nothing to host.
   Honeycomb is the alternative when exploring event patterns matters more than time series.
   Free-tier quotas of both were not verifiable from the planning session (their sites are
   outside its allowed network domains); verify before choosing. The file tier stays
   authoritative; the backend is for the queries files make slow.

   Configuration is set once per cloud environment and once in the local shell profile,
   never in repository settings, which Claude Code ignores for these variables. `claude -p`
   inherits it, so crews and gates export without code changes; auto-mate overrides `layer`
   per invocation.

   ```bash
   CLAUDE_CODE_ENABLE_TELEMETRY=1
   OTEL_METRICS_EXPORTER=otlp
   OTEL_LOGS_EXPORTER=otlp
   OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf
   OTEL_EXPORTER_OTLP_ENDPOINT=https://<backend>
   OTEL_EXPORTER_OTLP_HEADERS="Authorization=Bearer <token>"
   OTEL_RESOURCE_ATTRIBUTES=project=<repo>,layer=<interactive|crew|gate|archivist>
   OTEL_METRICS_INCLUDE_REPOSITORY=true    # per-repo cost attribution; off by default
   OTEL_METRICS_INCLUDE_ENTRYPOINT=true    # separates headless from interactive
   # never set: OTEL_LOG_USER_PROMPTS, OTEL_LOG_ASSISTANT_RESPONSES,
   #            OTEL_LOG_TOOL_DETAILS, OTEL_LOG_RAW_API_BODIES
   ```

   The backend's host must be added to every cloud environment's network allowlist, or
   cloud sessions export nothing and report nothing. Langfuse stays what it is today: the
   trace sink for `trine_eval`'s per-sample eval runs and judge calibration. It is not the
   sink for session and run metrics; as far as is known its OpenTelemetry endpoint ingests
   traces, and Claude Code's trace export is behind a beta flag. Verify when its docs are
   reachable.
5. **Privacy and retention.** No prompt or response bodies in any event; summaries are
   capped at 160 characters as the audit log already does; `OTEL_LOG_USER_PROMPTS` stays
   unset. `.council/diagnostics.jsonl` is append-only under the same hook as the other
   ledgers and rotates with the same script. Retention of raw events follows
   `config.transcripts.retain_days` in the repo; rollups are kept indefinitely.
6. **How the record drives improvement.** Through the channels that already exist, with the
   data added as an input: the retrospective agent in `pdca` mode reads the project's rollup
   and the last cycle's events; `harness-summary`'s ACI section cites cost and consistency
   together; standard-work proposals that come out of either go through nemawashi as today.
   Pattern studies are jishuken artifacts: on a cadence, run the queries in `docs/queries.md`
   and write the findings under `.council/jishuken/` in the project they concern, or in this
   repo when they span projects. The questions the data must be able to answer are listed
   below and are the acceptance test for the schema.
7. **One session, one cost.** A crew session that auto-mate invokes also fires the council's
   `SessionEnd` hook whenever the council is project-scoped in that repo, so the same
   `session_id` can appear as a `session` event and inside a run record. Rollups join on
   `session_id` and never sum the two: cost and usage come from the run record
   (`cost_source: claude-code-estimate`), tool counts and compactions come from the session
   event, and `parent_session_id` links the crew to the session that ran `automate`.
8. **Cardinality rule.** Metrics carry project, layer, model and effort only. Task ids,
   sprint numbers, henka ids and approval ids live in events and files, never in metric
   attributes.

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

The first three studies to run once data exists: effort level against gate verdicts and
cost, since the gates embed whole diffs; cache share of input on gate prompts, expected near
zero and fixable with a stable prefix; and sessions with sidechains but no verdict, the
subagent-stall family (HK-0035) from bay-o-net.

## Alternatives considered

- **OpenTelemetry only.** Rejected as the first tier: it needs a reachable backend from every
  environment, cannot be configured from repo settings, and leaves nothing in git for the
  archivist or the retrospective to read.
- **Parsing the console exporter.** Rejected: its format is not a stable contract.
- **A metrics database now.** Rejected: measure first; the rollups decide what a database
  would need to hold.
- **Langfuse as the sink for Claude Code's metrics and events.** Rejected: wrong signal
  types; it keeps its role for eval traces.
- **A self-hosted collector.** Rejected for now: one more service for one maintainer, and
  cloud sessions would still need a reachable endpoint.

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
- The eleven questions above each have a documented DuckDB query over `index/diagnostics/`.
- Dedupe: a fixture crew session present both as a session event and inside a run record
  contributes one cost line and one tool-count line to the rollup, joined on `session_id`.
- Cardinality: no metric attribute carries a task id, sprint number, henka id or approval id.
- Before the OpenTelemetry tier is switched on: the backend's free tier confirmed, its host in
  every cloud environment's allowlist, and one test session visible in the backend with
  `project` and `layer` attributes.

## Amendments

### A1 (2026-11-06): a session event is one settled process lifetime; OpenTelemetry is the backstop for cloud sessions

- **Status:** Accepted 2026-11-06: D1 to D4 decided by the human; text drafted by the planning
  session
- **Date:** 2026-11-06
- **Author:** cloud-catcher planning session, from the session-event design study
  (2026-11-04) that followed the review of henka-council #28; decisions D1 to D4 taken by the
  human
- **Amends:** decision 1 (schema 1.1), decision 2 (interactive capture, and how
  `harness-summary` reads session events), decision 3 (how the archivist dedupes and sums),
  decision 4 (the OpenTelemetry tier for cloud sessions), decision 7 (crews), and the
  Verification list. Decisions 5, 6 and 8 and the eleven questions stand; Consequences note
  the attributes Claude Code itself puts on metrics.

#### Context

Checked on 2026-11-04 with scripted probes on Claude Code 2.1.318, and on the transcript of
one real cloud session (one session id, 2026-10-31 to 2026-11-04). The probes ran on Linux,
most of them in `claude -p` or stream-json mode. Interactive probes covered startup, `/clear`,
resume and `/exit`, plus one fork that ran without hooks.

- `SessionEnd` is per process, not per session: it fired once per process at every probed
  graceful ending, so a resumed session gets one per process. It fired at `claude -p` exit,
  at the end of stream-json input, at interactive `/exit` and at `/clear`. In `-p` and
  stream-json mode SIGTERM fired it too, and SIGKILL fired none. `SessionStart` fired when a
  process started or resumed a session and, inside a running process, for `/clear`; in `-p`
  mode it also fired for a fork and for `/compact`.
- `--resume` and `--continue` keep the session id and append to the same transcript file.
  Nothing in the transcript marks a process start. Every probed ending except SIGKILL writes
  a `cost-state` entry; interactive `/exit` writes two with equal totals.
- `cost-state` is cumulative across processes. `totalCostUSD`, `modelUsage` and
  `totalDuration` carry over, and `startTime` stays the same through resume, continue and
  fork. `claude -p`'s `total_cost_usd` is cumulative too.
- `/clear` starts a new session id in the same process, with a new `startTime`. The old
  session's closing `cost-state` is written after its `SessionEnd` hook has returned.
- `--fork-session` starts a new session id. Its transcript copies the parent's chain of
  entries with the same uuids and requestIds, and its `cost-state` starts from the parent's
  totals. No transcript field names the parent, and in `-p` mode no hook payload or hook
  environment variable does either.
- In `-p` mode, after SIGKILL the killed process's requests stay in the transcript with their
  usage, but no `cost-state` is written. The next resume restores the last one, so that spend
  never enters `cost-state` or `total_cost_usd`.
- Two `-p` processes that resume one session at the same time append to the same file, and
  each final `cost-state` leaves out the other's spend.
- Compaction and title-generation calls appear only in `cost-state`. Subagents write their
  turns to agent files under `<session_id>/subagents/`.
- In the real session as of 2026-11-04 (cut after its fifth closing point), eight
  `cost-state` entries give five closing points. The five lifetimes' deltas are 7.1773923,
  27.49865245, 0.9899525, 152.047308 and 62.2513088 USD, and they sum to 249.96461405, the
  last `cost-state` then. henka-council #28 writes one cumulative event per exit; one
  cumulative event at each of the five closing points would sum to 515.197354 USD. By date
  the spend is 35.67 USD on 2026-10-31 and 214.30 USD on 2026-11-04. The session has since
  gained a sixth lifetime, which crosses UTC midnight (2026-11-04 22:21 to 2026-11-05 00:00).
- No `SessionEnd` hook has been observed in a cloud session: every probe ran as a child
  `claude` process with a scratch config directory, not as a cloud session, and the cloud
  launcher settings register only `SessionStart` and `Stop` hooks (checked 2026-11-06). When
  `SessionEnd` fires there is therefore inferred, not observed. What was observed is that a
  lifetime's closing `cost-state` can be written long after the main transcript's last turn.
  The fifth lifetime's was written at the 22:20 UTC VM restart on 2026-11-04 (worked out from
  its `totalDuration`; a `cost-state` carries no timestamp). A background workflow's subagents
  were still writing then (last subagent entry 22:20:42), and the restart cut that work off.
  The main transcript's last entry was 41 minutes earlier, at 21:39:41.
- When the session's cwd is in a git repo with a remote, the cloud Stop hook asks once, at
  the end of a turn, for uncommitted, untracked or unpushed changes to be committed and
  pushed. It is not registered for `SessionEnd`.
- auto-mate's crew adapter runs `git add -A` after the agent exits, commits whatever is
  dirty, and reports the crew as changed. auto-mate never passes `--resume`, `--continue` or
  `--fork-session`, and it does not set `AUTOMATE_RUN`. It runs each crew and gate command
  under a timeout (3600 s and 1800 s by default). When one expires, `subprocess.run` kills
  (SIGKILL) the process auto-mate started, which for the default direct crew is the `claude`
  process itself, and the run fails with no usage recorded for that crew or gate (checked
  2026-11-06 at auto-mate a5d4962).
- No `.council/diagnostics.jsonl` exists in any repo under `/home/user` (checked
  2026-11-06), so no schema 1.0 session event needs migrating.

#### Decision

The human answered four questions on 2026-11-06. The answers are D1 to D4.

**D1. One `kind: session` event per settled process lifetime** (amends decisions 1 to 3).

1. A *lifetime* is one Claude Code process's tenure on one session id. It opens when a
   process starts, resumes or forks the session, or when `/clear` creates it; compaction
   opens nothing. It closes at the `cost-state` that process writes when it exits. One
   process can hold two lifetimes in a row (`/clear`); one session can hold two at once
   (concurrent resumes).
2. A lifetime is *settled* when its closing `cost-state` exists. The closing point is the
   first `cost-state` after the lifetime's last own entry, or a `cost-state` whose total
   differs from the one before it. Later `cost-state` entries with equal totals and only
   bookkeeping entries between them are re-writes. An open lifetime is never recorded. A
   settled lifetime with no requests, tool calls or compactions and no cost writes no event.
3. Every measure is a delta over the lifetime alone.
   - `usage`, `usage_by_model` and `sidechain_usage` count the lifetime's own requests, once
     per requestId, over its span of the main transcript and the session's subagent files in
     its time window. Entries a fork copied from its parent are left out.
   - `cost_usd` is the closing `cost-state`'s `totalCostUSD` minus the `cost-state` the
     process restored at start. That base is 0 after startup and `/clear`, the last
     `cost-state` before a resume, and the parent's cost at the fork point for a fork.
     `cost_usd` is null when the base is unknown, and the event then carries no other
     `cost-state` figure. `cost_source` is `claude-code-estimate`, or null when `cost_usd`
     is null.
   - `cost_state_usage_by_model` is the same delta of `modelUsage`: tokens and cost per
     model, including calls no transcript shows. It is never added to `usage`.
   - `duration_ms` and `api_duration_ms` are `cost-state` deltas.
   - `counts` cover the lifetime, main transcript plus subagent files. Compactions are
     `compact_boundary` entries. `subagents` is the larger of agent files and Agent or Task
     launches. `tool_failures_by_tool` is new. No `PreCompact` or `SubagentStart` markers are
     written.
4. Three anchors are never summed: `lifetime.cost_lineage` (the `cost-state` `startTime`),
   `lifetime.cum_cost_start_usd` and `lifetime.cum_cost_end_usd`. They let anyone check a
   session's sum against Claude Code's own cumulative figure, and price a missing lifetime
   from its neighbours.
5. `event_id` is UUIDv5 in namespace `5f0c2b8e-2a7d-4d38-9a51-1c2f1d6e2006` over
   `session-lifetime|<session_id>|<anchor>`. The anchor is `cs:<startTime>:<totalDuration>`
   of the closing `cost-state`, as decimal integers, or `open:<first uuid among the
   lifetime's own entries>` for an interrupted lifetime. `lifetime.spec` versions the
   derivation rules and is not part of the id. `ts` is the latest timestamp among the
   lifetime's own entries, main or subagent, never the hook's clock. So every observer of a
   lifetime mints the same id, and a producer skips a line whose `event_id` the ledger, or
   its newest rotated archive, already holds. The namespace value was not put to the human:
   it is the one the lifetime-delta prototype and the real-session re-derivation used, and
   no id was computed with the `612876f2-...` namespace in the design study's draft.
6. A lifetime that ended without a `cost-state` (SIGKILL, power loss) is *interrupted*. It
   is recorded only after the next lifetime of the same session has started, with exact
   tokens, `cost_usd: null` and `outcome: interrupted` (D3).
7. One pure function of the files on disk derives every event. The hooks and a backfill
   command only decide when to call it. At `SessionEnd` it reads only the spans of the
   lifetimes it settles; work that would overrun the hook's time budget is left to a later
   call.
8. Each event carries `lifetime.coverage`: subagent files read, launches with no agent file,
   copied entries left out, whether a fork's parent was found, where the sprint context came
   from, and any shortfall where the transcript holds more tokens than the `cost-state`
   delta.
9. Crew guard: council hooks write nothing when `AUTOMATE_RUN` is set, because auto-mate
   commits a crew's leftovers with `git add -A` and counts them as changes. auto-mate sets
   the variable for every crew and gate it starts; that auto-mate change is not made yet
   (P2-AM-2).
10. Readers sum. A session's total is the `SUM` of its events, `GROUP BY session_id`. A day,
    month or window is the sum of the events whose `ts` falls in it, except that a lifetime
    with `lifetime.days` adds each day's share to that day (item 11). A session's latest
    event is never its total. Per-session figures divide by the number of distinct session
    ids. The archivist keeps one copy per `event_id`: the higher `lifetime.spec`, then the
    live copy over a recovered one, then the more complete coverage. Every rollup reports
    coverage next to its sums, including the sessions with audit-log activity after their
    last settled lifetime.
11. A lifetime counts whole toward the sprint of its `ts` and sits in the monthly file of its
    `ts`. `lifetime.days`, present only for a lifetime that crosses UTC midnight, splits its
    tokens and cost by UTC day; a day, month or window sum uses those bins in place of `ts`,
    never both. `harness-summary` sums session events per sprint, and
    `lifetime.sprint_at_start` flags a lifetime that began in an earlier sprint.

**Decision 7, as amended.** auto-mate gives each crew and gate session one lifetime (inferred:
it never passes `--resume`, `--continue` or `--fork-session`); a human may resume it later.
With the crew guard, crews and gates write no session event. Their cost and usage still come
from the run record. The tool counts and compactions that decision 7 took from the session
event have no source until auto-mate carries the crew's lifetime event inside the run record;
until then they are missing, not zero. A crew or gate that auto-mate kills at its timeout has
no usage in its run record and, with the crew guard, no session event, and no later lifetime
of its session records it unless someone resumes that session. No event or run record holds
its spend until auto-mate captures it, for example from the crew's transcript or by carrying
the crew's lifetime event. A run record covers its session's first lifetime; a later lifetime
of that session, such as a human resume, is an ordinary session event. A run flagged
`session_id_inherited` joins on `task_id`, not `session_id` (PLAN.md section 7).
`parent_session_id` keeps its meaning. Fork and `/clear` links live in
`lifetime.forked_from_session_id` and `lifetime.cleared_from_session_id`.

**D2. The OpenTelemetry tier is the backstop for cloud sessions** (amends decision 4).

- Inferred, since no `SessionEnd` hook has been observed in a cloud session: in a cloud
  container, what `SessionEnd` appends after the last turn is committed only by a later
  lifetime, and is lost if the container is discarded first. The OpenTelemetry tier is
  therefore to be switched on for cloud sessions (P0-OPS-1) once decision 4's preconditions
  hold, as the backstop for lifetimes the file tier cannot hold. Coverage counts are still
  reported (D1).
- The backend is decision 4's default, Grafana Cloud, subject to decision 4's existing
  precondition that its free tier is confirmed. Checked 2026-11-06 from a search excerpt of
  grafana.com/pricing, to be confirmed on the account: 10,000 active metric series and 50 GB
  of logs a month, kept 14 days, with no card. With 14 days' retention, the archivist must
  take backstop figures into git within 14 days of a session. The account and endpoint are
  still to come from the human. Configuration, redaction and the allowlist follow
  decision 4.
- The file tier stays authoritative for every lifetime it holds. The archivist turns to the
  backend only for spend the file tier lacks: a session with audit-log activity after its
  last settled lifetime. It takes the spend after that lifetime's end from the backend's
  `api_request` events, matched by `session.id` and time, and labels it
  `cost_source: backend`. If the lifetime's own event reaches the file tier later, that
  event replaces the backend figure.
- Outside cloud sessions decision 4 stands: the tier stays optional.

**D3. Interrupted lifetimes keep exact tokens and no cost.**

- An interrupted lifetime's event has exact tokens and `cost_usd: null`. No price table is
  kept for session events.
- A later estimate will be derived from historic data on the timeline, for example the cost
  per token by model seen in settled lifetimes near the same date. It is future work. It is
  computed at read time, labelled as an estimate, never written into the event, and never
  summed with Claude Code's own estimate. Schema 1.1 adds no `cost_source` value for it.

**D4. The rework ships as a follow-up PR to henka-council #28, in two stages.**

- Stage 1: `SessionEnd`-only settled lifetime deltas.
- Stage 2, after Stage 1: the `SessionStart` hook, for the `/clear` hand-off, the fork base
  and recovery.

#### Schema 1.1

`index/diagnostic-event.schema.json` moves to 1.1; henka-council's copy is to follow byte for
byte (the P0-HC-2 diff test). `schema_version` is `1.0` or `1.1`; a `kind: session` event must
be `1.1`, with a UUIDv5 `event_id`, and carry `session_id`, `usage`, `cost_usd`, `outcome`
(`ended` or `interrupted`) and a `lifetime` object with the anchors, the id anchor, `spec`,
`start_source`, `end_reason`, `started_at`, `ended_at`, the fork and `/clear` links,
`sprint_at_start`, `recovered` and `coverage`. A settled event's `cost_usd` is null exactly
when its base is unknown. `cost_source` is `claude-code-estimate` when `cost_usd` is a number
and null when it is null; a null-cost event has no `cost_state_usage_by_model`, and its
durations and day costs are null. Also new: `cost_state_usage_by_model` and
`counts.tool_failures_by_tool`. A `1.0` event carries neither, nor `lifetime`; other kinds may
stay `1.0`.

#### Alternatives considered

- **One event per API request.** It places every request exactly in time and sprint, and
  joins one-to-one with OpenTelemetry `api_request`. Rejected for the git ledger: 2,228 lines
  for the one real session, and a price table to maintain.
- **One event per whole session, the latest standing for the session.** Any sum counts
  earlier spend again at every exit, and the latest event files all spend under the last
  exit's date: all 249.96 USD of the real session in November.
- **Coverage counts alone for the cloud gap.** Rejected for cloud sessions (D2); the counts
  stay.
- **A price-table estimate for interrupted lifetimes.** Rejected (D3): someone has to keep
  the table current.
- **Reworking henka-council #28 all at once.** Rejected for a follow-up PR in stages (D4).

#### Consequences

- Every total is a sum. For the real session the five events read 7.18, 27.50, 0.99, 152.05
  and 62.25 USD: 249.96 in all, Claude Code's own cumulative figure, with 35.67 on
  2026-10-31 and 214.30 on 2026-11-04.
- A lost line costs attribution (tokens, counts, sprint) but not dollars, as long as a later
  lifetime of the same lineage exists: the anchors show the gap and its exact cost.
- Gaps are labelled. Interrupted lifetimes and forks whose parent was not found show tokens
  without cost. Chain gaps show cost without tokens. A cloud lifetime whose event never
  reached git shows as a coverage count and, once D2 is live, as backend spend.
- Until Stage 2, a `/clear` predecessor is settled only at its successor's `SessionEnd` in
  the same process, a fork's base comes only from cost lineage, an interrupted lifetime's
  tokens fall into the next lifetime's event and show as shortfall, and a lost line comes
  back only through a backfill.
- A lifetime that spans a sprint change is booked to its end sprint. Finer splits are an
  open item.
- Decision 7 loses data for a while: crew tool counts and compactions are missing until
  auto-mate carries the crew's lifetime event, and crew tool calls no longer reach the
  governed repo's audit log. The guard itself takes effect only once auto-mate sets
  `AUTOMATE_RUN`. A crew or gate that auto-mate kills at its timeout has its spend in no
  event or run record until auto-mate captures it.
- The producer grows: one deriver, a backfill command and recorded fixtures, then a
  `SessionStart` hook in Stage 2. Consumers dedupe and sum.
- The 1.0 session events that henka-council #28 writes fail validation against schema 1.1,
  and so do henka-council's 1.0 session fixtures; P0-HC-2 rewrites them.
- Schema 1.1 has no record shape for backend spend, because a session event carries
  file-tier anchors. The archivist build that first reads the backend adds one, labelled
  `cost_source: backend`.
- With the tier on, cloud metrics carry attributes beyond decision 8's four. Claude Code
  2.1.318 always adds `user.id`, and one setting that is on by default,
  `OTEL_METRICS_INCLUDE_SESSION_ID`, puts `session.id` on its events and metrics alike (read
  from the binary, not observed in a backend). Decision 4's own settings add repository and
  entrypoint attributes. D2 needs `session.id` on the events, so that setting stays on.
  Decision 8's rule that no metric attribute carries a task id, sprint number, henka id or
  approval id is unaffected.
- The work record's diagnostics block has no fields for coverage figures yet; P3-CC-1 adds
  them.

#### Verification

Replaces two bullets above: "A governed fixture session ends with exactly one `session`
event ..." and the dedupe bullet. The others stand; the OpenTelemetry precondition now gates
D2.

- Schema: 1.1 loads as draft-07. A settled and an interrupted 1.1 session event validate,
  and so do 1.0 events of other kinds. A `kind: session` event with `schema_version` 1.0 is
  rejected, and so is a session event that breaks the cost rules under Schema 1.1.
- Recorded fixtures cover resume, continue, `/compact`, `/clear` (`-p` and interactive), a
  `-p` fork, an interactive fork, a fork of a compacted session, SIGKILL, SIGTERM, concurrent
  resumes and a resume from another directory. They yield one event per non-empty lifetime.
  Per cost lineage, the events' `cost_usd` add up to the last `cost-state` plus each fork's
  own spend, or to more where concurrent resumes left a delta out of the last `cost-state`.
  Each event's tokens equal the requestId-deduplicated sum over its span, main transcript
  plus subagent files. Stage 1, which has no `SessionStart` hook, yields this with three
  differences: a SIGKILLed lifetime gets no event of its own, and its tokens land in the next
  event as shortfall; a `/clear` predecessor's event is written at its successor's
  `SessionEnd` in the same process; a fork's base comes from cost lineage, and a fork whose
  parent is not found has `cost_usd: null` and `coverage.fork_parent: not-found`.
- Real-session reconciliation: a redacted fixture of the real cloud session, cut after its
  fifth closing point, yields five events of 7.1773923, 27.49865245, 0.9899525, 152.047308
  and 62.2513088 USD. They sum to 249.96461405, its last `cost-state`. By `ts`, 35.67 USD
  falls on 2026-10-31 and 214.30 USD on 2026-11-04. The fifth event's `ts` is
  2026-11-04T22:20:42.265Z, its last subagent entry, not the main transcript's 21:39:41.305Z.
- Idempotence: a second firing on the same state appends nothing. Events derived from
  hook-time snapshots match, id for id and number for number, the events derived from the
  final files. After Stage 2, deleting the ledger and starting the session again re-appends
  the same `event_id`s.
- Settled only: a backfill over a transcript whose last lifetime is still open emits nothing
  for that lifetime.
- Crew guard: with `AUTOMATE_RUN` set, a fixture session leaves `.council/` and the worktree
  unchanged. In the rollup a crew contributes one cost line, from its run record.
- Budget canary: a test fails when the `SessionEnd` hook budget of the pinned Claude Code
  version changes, and the deriver's `SessionEnd` work on the heaviest recorded fixture fits
  in it.
- Backstop: before the archivist relies on the backend, one cloud test session that is
  later resumed is compared lifetime by lifetime with its file-tier events, and the
  difference is recorded in a later amendment.

#### Open items

Not decided on 2026-11-06:

- Raising the `SessionEnd` budget with `CLAUDE_CODE_SESSIONEND_HOOKS_TIMEOUT_MS` in governed
  repos' settings.
- `.council/*.jsonl merge=union` in governed repos' `.gitattributes`.
- Hashing MCP tool names in events.
- Sprint splits finer than one lifetime. The `sprint_at_start` flag stays either way.
- Passing `--session-id` to auto-mate's child sessions.

#### Unknowns

Not probed, or probed too little to rely on:

- Whether Ctrl-C (SIGINT), closing a terminal (SIGHUP) or closing a Windows console fires
  `SessionEnd`. The probes covered `claude -p` exit, the end of stream-json input, `/exit`,
  `/clear`, SIGTERM and SIGKILL.
- Interactive mode beyond startup, `/clear`, resume and `/exit`: SIGTERM, SIGKILL,
  concurrent resumes, and `SessionStart` for a fork or a compaction were probed only in `-p`
  or stream-json mode. Auto-compaction was not probed; only a manual `/compact` was.
- Windows and macOS. No probe ran there: hook latency, Python startup, file locking, and
  finding a fork's parent from the command line are untested.
- Cloud containers: whether and when `SessionEnd` fires there, since no hook has logged it;
  whether a fresh container gets the transcript back with its `cost-state` entries and
  subagent files; whether a container is ever stopped with SIGKILL; how often a cloud session
  ends without a resume, which sets the size of the gap D2 covers.
- Why cloud lifetimes end with runs of equal-total `cost-state` entries: two each in the
  first three lifetimes and five in the sixth, most of them about 5 minutes apart by
  `totalDuration`. Under the closing-point rule this affects duration (up to about 20
  minutes), not cost.
- Whether `CLAUDE_CODE_SESSIONEND_HOOKS_TIMEOUT_MS` in project settings raises the budget
  for interactive exits; the design study tried `-p` mode only.
- Whether teleported sessions, `--bg` copies and SDK forks behave like `--fork-session`.
- Whether tokens streamed before a SIGTERM are billed. They appear in neither the transcript
  nor `cost-state`.
- How often one lifetime spans a sprint change, and how often two processes resume one
  session at the same time.
- How soon after `SessionEnd(clear)` the old session's closing `cost-state` appears, and
  whether it can fail to appear. It was timed once interactively.
- Whether the backend's data can be matched to one session and span closely enough to price
  a lifetime. No backend is connected yet.
- Format drift: `cost-state`, the `/clear` write order and the subagent file layout are
  transcript internals that can change between Claude Code versions.
