# Agentic stack: phased implementation plan

- **Status:** Proposed (Level 5 review before any sprint starts)
- **Date:** 2026-10-31
- **Repos:** auto-mate, henka-council (plugin id `henkaten-council`), trine-eval, cloud-catcher (this repo)
- **Companions:** `decisions/ADR-0001..0005`, `plan/sprints.json` (machine-readable decomposition), `manifest.json`, `index/work-record.schema.json`, `archivist/briefing-task.md`

The plan builds on what the four repos already contain and on the August 2026 stack review
in auto-mate (`docs/agent-stack-review-2026-08.md`). It adds no new vocabulary: every
mechanism below already has a name in one of the repos.

---

## 1. What "complete" means

The stack is complete for v1 when this scenario runs on two projects in parallel, from the
cloud, and every step leaves a trace in the project's ledgers.

1. **Capture.** A note (voice transcript or text) lands in the project's Drive inbox. The
   archivist files it into `inbox/<project>/` here and lists it in the next briefing.
2. **Scope.** The Discovery Gate turns captures into a planning package: spec, constraint
   catalog, acceptance criteria. A zero-context Goldfish review passes. The human ratifies
   through the nemawashi walkthrough. An approval entry recording the package's sha256 is
   written.
3. **Execute.** In a cloud environment, `automate run` refuses a task that lacks a ratified
   scope reference. With one, it provisions a worktree, runs the crew, records the effective
   autonomy floor on each gate verdict, and no-mistakes ships a PR.
4. **Evaluate.** The sprint is graded against a rubric that fits its type: code, research
   report, or quantitative model. The trial count follows the risk-tier policy.
5. **Brief.** The archivist rebuilds the cross-project work record, writes a Drive briefing
   with decisions pending first, and notifies when a Level 5 decision is waiting.

Exit gates, all of which must hold:

| Gate | Measure | Where measured |
|---|---|---|
| Sensor fixed | 0 audit entries with `file_path=unknown` over one full sprint | `.council/audit-log.jsonl` |
| Confirm seam closed | 0 `shipped` runs without a scope reference in any governed repo | run records |
| Ledger join works | every gate verdict in a run record ingested as a henka record exactly once | `henka-register.jsonl` against `runs/*.json` |
| Non-code work gradable | five-task research and quant set: at least 4 reach PASS within `max_retries`; first-round pass and pass^k reported | `harness-summary` |
| Cross-project record | two projects in one briefing; a pending decision reaches Drive and a notification | `index/work-record.json`, Drive |
| Headless parity | one real task shipped from a cloud session end to end with ingested verdicts | run record, PR |

## 2. Ground truth (checked 2026-10-31)

Exists and works:

- trine-eval: contracts with behavioral/structural/llm-judge criteria and buckets, Should-NOT
  gates, trials with pass@k and pass^k, regression graduation, Workflow-based trial dispatch,
  six rubrics, the `trine_eval` library (runner, judge calibration, Batch API, OTel).
- henkaten-council: 4M henkaten detection, three append-only ledgers with hook enforcement,
  autonomy Levels 0 to 5 with the dynamic floor, andon protocol, nemawashi walkthrough,
  retrospectives with yokoten, Cynefin prebriefs, stop-condition taxonomy, from-plan bridge
  with sha256 envelopes, thirteen JSON schemas.
- auto-mate: typed lifecycle with Protocol ports, dry-run by default, `RunRecord`,
  treehouse and no-mistakes adapters validated live on Linux, PR review lifecycle with the
  native `/code-review` engine, cloud-runnable review backends.

Designed, not built: the Discovery Gate (ratified design, no agents or skill); loop shapes
(schema only); rag-source and qa-regression agents (proposed, off by default).

Broken or missing:

| Item | Evidence |
|---|---|
| Tool-call audit logger | plugin hook reads `.tool_args.*`; the native payload field is `tool_input`; the rewritten logger sits unapplied in `auto-mate/docs/handoff/council-native-hooks/` |
| Human-approval log | schema exists; no writer, no file |
| Run-record persistence | `automate run` prints the record to stdout only |
| Rubrics for non-code work | project types are web-app, rag-system, cli-tool, api-service, eval-harness, harness-build |
| Governance on the headless path | the governance gate is a prompt; reads no `.council/` state, writes no record |
| Cloud validation of the run lifecycle | `dry_run` is global; treehouse and no-mistakes not installed in cloud environments |
| Cross-project record, archivist | nothing exists |

August review carry-overs: done are the `budget_tokens` removal, the langfuse pin, the
Workflow trial loop, and `/code-review` as review engine. Not done are the native-hook
logger, the no-mistakes pin, and re-validation of undocumented agent frontmatter.

## 3. Principles

1. Use the stack's existing names and mechanisms.
2. Enforcement lives in consumers, not in labels. Scope authority is checked where execution
   starts, in auto-mate.
3. Fix sensors before adding instruments. The audit logger is repaired first.
4. Git is the system of record; Drive is the reading and capture plane (ADR-0004).
5. Measure before building memory. No vector or graph store until retrieval misses are logged.
6. Ceremony is re-audited every PDCA cycle (August review §6.2).
7. The meta-repo holds no component source (ADR-0005).

## 4. Phases

Sprint ids below match `plan/sprints.json`. Each sprint runs in the repo named, through that
repo's own harness; contract seeds give the criteria the Generator and Evaluator start from.

### Phase 0: Baseline

**P0-CC-0, cloud-catcher.** This bootstrap. Exit: ADRs ratified.

**P0-HC-1, henka-council: native-hook audit logger.** Apply the handoff in
`auto-mate/docs/handoff/council-native-hooks/`: the hook reads `tool_input` and `cwd` from the
payload, resolves the repo root from the payload's cwd, writes only when `.council/` exists,
and drops the in-hook andon counter (andon becomes a policy over the log in council-autorun
Step 1E). PowerShell parity or a recorded deferral. Contract seeds:

- behavioral, bucket 2: feed fixture payloads for Read, Edit, Bash, Grep; every entry has a
  real `tool_input_summary`; 0 contain `unknown`.
- behavioral, bucket 2: a payload whose cwd is a worktree without `.council/` creates no
  directory.
- Should-NOT: no entry carries a non-null `andon_pull_count`.

**P0-OPS-1, operator.** Billing surface check (one headless run with the API key; Console
usage line; addendum to ADR-0001). Re-validate `context: fork` and `thinking:` frontmatter.
Review trine-eval's default model and pricing table against the current price list. Pin
no-mistakes at v1.48.0 in docs and setup script.

### Phase 1: Definition of done for research, writing and quantitative work

This is the fix for the stated weakness. Contracts are the source of truth for done, and the
weak task types have no contract vocabulary and no rubric, so the Generator and Evaluator
have nothing to converge on.

**P1-TE-1, trine-eval: rubrics and contract guidance.** Two rubrics in
`skills/eval-rubric/rubrics/`:

- `research-report`: claim traceability (every load-bearing claim cites a source with a
  re-runnable check), reasoning quality, scope fidelity to the contract, prose quality.
  Hard threshold: an untraceable load-bearing claim fails the sprint. The council's proposed
  rag-source agent is the natural reviewer for traceability when the council is active.
- `quant-model`: correctness against closed-form or reference cases, reproducibility (seed
  determinism, pinned inputs), statistical validity (convergence, confidence intervals,
  calibration or backtest where applicable), code quality. Hard thresholds: no reference-case
  parity test, or non-deterministic results under a fixed seed.

Plus the decision-guide rows, a "document deliverable" subsection in the contract skill
(behavioral criteria for documents: commands that check sources, figures regenerated from
code, section budgets), and bootstrap-failures templates seeded from known failure modes
(fabricated citations, unlabeled assumptions, silent unit errors, overfit backtests).
Example criterion the quant rubric expects to see in contracts:

```
3. Monte Carlo parity: `uv run python -m spike.mc --seed 7 --n 200000 --case lognormal-call`
   prints an estimate whose 95% CI contains the Black-Scholes value printed by
   `uv run python -m spike.closed_form --case lognormal-call` [weight: 20%, bucket: 2]
```

**P1-TE-2, trine-eval: kickoff, evaluator tooling, summary.** Project types
`research-report` and `quant-model` with rubric mapping and detection hints; python for
numeric checks, playwright never; summary N/A handling; one worked example contract per type.

**P1-VAL-1, a scratch project.** Five real tasks (three research memos, two risk-model
spikes) through `harness-sprint`, `trials = 2` on the quant sprints, then `harness-summary`.
Gate: at least 4 of 5 PASS within `max_retries`; untestable criteria under 20%. Level 5:
which five tasks, and the rubric weights.

Research outputs ship like code: committed under the project's `docs/` or `reports/`, PR
through no-mistakes, mirrored to Drive by the archivist after merge (ADR-0004). No second
pipeline.

### Phase 2: Confirm seam and governance join

**P2-HC-2, henka-council: approval log writer.** `scripts/append-approval.py` writing
`.council/human-approvals.jsonl` per the existing schema, extended additively with
`artifact_path`, `artifact_sha256`, `grants`, `scope`. Writers: nemawashi Stage 4, the minor
path, `council-review --restore-autonomy`, from-plan confirmation. The append-only hook covers
the new file.

**P2-AM-1, auto-mate: scope reference.** `ScopeRef` on `Task`; a council adapter that reads
effective autonomy and approvals from the task repo; validation before provisioning
(approval approved, `artifact_sha256` equals the digest of `git show <base_ref>:<path>`,
grants cover push and draft PR); `--scope` and `--approval` on the CLI; governed repos
require it, ungoverned ones do not. Verification cases are listed in ADR-0003. Batch
ratification of a sprint plan mirrors the yokoten ratify-once shortcut, so the human step is
one per plan, not one per task.

**P2-AM-2, auto-mate: persisted run records and autonomy-aware shipping.** Records to
`<workspace_root>/runs/<repo-slug>/<task-id>-<utc>.json`; `Verdict.evidence` and
`Verdict.autonomy_at_gate`; ship skipped with status `gated` when the floor is at or below
Level 2. In cloud environments the workspace root points at a cloud-catcher checkout's
`runs/`, pushed to the `work-record` branch after the run.

**P2-HC-3, henka-council: ingest.** `scripts/ingest-run-record.py` maps verdicts to henka
records (Method, `gate-verdict`, passive, impact by verdict and ship outcome, evidence citing
the run path) and appends through `append-henka.py`, idempotent on run path. council-autorun
Step 1A runs it before the pre-sprint check.

Exit: in a governed fixture at Level 1, `automate run --execute` ends `gated` with no push;
at Level 4 with a ratified scope it ships, the record exists, ingest appends one henka record
per verdict and a second ingest appends nothing.

### Phase 3: Archivist and cross-project work record

**P3-CC-1, cloud-catcher: work-record builder.** `scripts/build-index.py`, stdlib only,
reading the sources in `index/README.md` and writing `index/work-record.json` (schema-valid)
and `index/briefing.md`. Signals derived exactly as the README states, each with a
`file:field=value` reason. Tests with two fixture projects. This repo gets its own harness
for this sprint (`cli-tool` rubric).

**P3-CC-2, cloud-catcher and cloud environment: the archivist.** An environment whose setup
script runs `workspace/sync.sh` and installs `automate`; a scheduled task from
`archivist/briefing-task.md` with the Drive connector, daily at an off-peak time; the Drive
layout from ADR-0004; captures filed into `inbox/<project>/`; a push notification when
decisions are pending or a project is halted; writes only to the `work-record` branch and to
Drive. Level 5: approve the layout, the schedule, and the connector grant.

Exit: two projects in one briefing; a seeded pending decision reaches Drive and a
notification; a seeded capture is filed.

### Phase 4: Discovery Gate

The scope layer, built from the ratified design in
`henka-council/docs/design/discovery_gate.md`. This is where scope becomes a living object:
the gate re-reviews the package when planning changes mid-flight.

**P4-HC-4, henka-council: reviewers and schemas.** `spec-specialist` (steelman),
`constraint-extractor` (adversary), `criteria-architect` (adjudicator); gate-mode flags for
henkaten-detector and architect; a thin `gate-orchestrator` shim; schemas for the constraint
catalog, the acceptance-criteria set and the gate decision; the GATE position-paper template.

**P4-HC-5, henka-council: `council-gate` skill.** Two-wave dispatch within the fan-out cap;
four decision states with outputs under `.council/proposed/GATE-NNNN.md`; the Goldfish wave
runs `/egm-review` on the spec draft in a zero-context session (Google's Elephant-Goldfish
plugin, pinned to a commit, with a forked-evaluator fallback); inputs are captures from
`inbox/<project>/` and persisted plans from from-plan; early-warning re-entry triggers; a
passing package feeds `harness-kickoff` or a new `sprints.json` phase; Stage 4 ratification
writes the approval entry with the package sha256, which is what auto-mate then requires.

Exit: a capture becomes a ratified package consumable by `harness-kickoff` without manual
edits; a mid-flight `spec.md` edit triggers re-review.

### Phase 5: Headless parity in the cloud, containment, runtime gate

**P5-AM-3, auto-mate and environment: live lifecycle from a cloud session.** Per-stage
dry-run; the plain-git worktree backend usable for runs; a documented ship fallback when
no-mistakes' daemon cannot run in the container (push branch, open draft PR through the
session's GitHub access, recorded as such); setup script installs what works. Exit: one real
task shipped from a cloud session with a persisted record and ingested verdicts.

**P5-AM-4, auto-mate: containment.** Per-task wall-clock, max-turns and token caps; crew tool
deny-list and read-only gate agents (`--bare` where API-key auth is available); a
`resource-cap` verdict when a cap fires, ingested with `response_type: resource-cap`; secrets
only through environment configuration.

**Runtime gate (ADR-0001).** With the five-task set and the containment work measured, decide
whether the headless path stays on `claude -p` or moves behind a Managed Agents adapter.
Level 5.

### Phase 6: Standing measurement and ceremony re-audit

Through the council's own retrospective to nemawashi to standard-work pipeline: trial count
risk-tiered by policy; council fan-out at cycle boundaries with passive per-sprint detection;
cross-project `harness-summary` from the work record; the memory decision from
`index/retrieval-misses.jsonl`; the standing PDCA question, which component has the current
model made unnecessary.

## 5. Order and dependencies

```
P0-CC-0 ─┐
P0-HC-1 ─┼─► P2-HC-2 ─► P2-AM-1 ─► P2-AM-2 ─► P2-HC-3 ─► P3-CC-1 ─► P3-CC-2 ─► P6
P0-OPS-1 ┘                                       │                      │
P1-TE-1 ─► P1-TE-2 ─► P1-VAL-1                   └─► P5-AM-3 ─► P5-AM-4  └─► P4-HC-4 ─► P4-HC-5
```

Phase 1 is independent of Phase 2 and can run in parallel with it. Phase 4 waits for the
approval writer (its ratification step) and the inbox (its input). Phase 5 waits for persisted
run records. Phase 6 starts once the work record exists.

## 6. Level 5 decisions this plan needs

| When | Decision |
|---|---|
| Now | Ratify ADR-0001 to ADR-0005; confirm the phase order |
| Phase 0 | Which surface should spend the API credits |
| Phase 1 | The five validation tasks; rubric weights and hard thresholds |
| Phase 3 | Drive layout, archivist schedule, connector grant |
| Phase 4 | The first real gate package |
| Phase 5 | Stay on `claude -p` or migrate the headless path |
| Phase 6 | Each standard-work proposal |

## 7. Risks and watch items

- **Elephant-Goldfish plugin is ten days old.** Pin a commit; keep the forked-evaluator
  fallback for the Goldfish wave.
- **no-mistakes' daemon inside cloud containers is unvalidated.** The ship fallback in
  P5-AM-3 exists for this; it is recorded in the run record so the weaker path is visible.
- **Undocumented agent frontmatter** (`context: fork`, `thinking:`) may stop working across
  Claude Code releases. Re-validate in P0-OPS-1 and at each plugin bump.
- **Cost.** Trials, council fan-out and two gates per task multiply spend. Adopt the
  risk-tier trial policy early (Phase 6 item, can be proposed after P1-VAL-1).
- **Windows parity** of hooks is a standing requirement (v2.1 amendment A7); every hook
  change carries it or a recorded deferral.
- **Scheduled tasks and connectors.** The Drive grant applies to every firing; grant only
  Drive, and only to the archivist task.
- **API drift.** Opus 5.5 is the current default model with effort default `medium`; set
  effort explicitly wherever the library or gates call the API.

## 8. Running this plan with the stack itself

- **henka-council and trine-eval** already have harnesses. Add the entries from
  `plan/sprints.json` as a new phase in each repo's `.harness/sprints.json` (a sacred file:
  Level 5 edit, then `/henkaten-council:council-autorun` per sprint).
- **auto-mate** has no harness. Kick one off with the `cli-tool` rubric:

  ```
  /trine-eval:harness-kickoff Add a ratified scope reference as the execution precondition,
  persist run records with verdict evidence and the autonomy floor, skip shipping when the
  floor is at or below Level 2, and make the lifecycle runnable from a Claude Code cloud
  session with per-stage dry-run, containment caps and a documented ship fallback.
  ```

  Then `/henkaten-council:council-kickoff`, then paste P2-AM-1, P2-AM-2, P5-AM-3, P5-AM-4
  as the sprint plan.
- **cloud-catcher** gets a harness at P3-CC-1 (`cli-tool` rubric) with the product prompt
  "a stdlib-only work-record builder over sibling repos, schema-valid, with derived signals".
- **The scratch project** for P1-VAL-1 is kicked off with `research-report` or `quant-model`
  once P1-TE-2 lands.

## 9. Calendar estimate

Assumes the harness's historical pace (several sprints a week when the loop is clean) and one
maintainer. These are estimates, not commitments.

| Weeks | Phases |
|---|---|
| 1 | Phase 0, Phase 1 start |
| 2 | Phase 1 finish, Phase 2 start |
| 3 | Phase 2 finish, Phase 3 start |
| 4 | Phase 3 finish |
| 5 to 6 | Phase 4 |
| 6 to 7 | Phase 5 and the runtime gate |
| after | Phase 6, standing |
