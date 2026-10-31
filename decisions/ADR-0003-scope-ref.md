# ADR 0003: A ratified approval entry is the precondition for execution

- **Status:** Proposed
- **Date:** 2026-10-31
- **Author:** cloud-catcher bootstrap (planning session)
- **Scope:** The Confirm seam between scoping (drafts, plans, conversation) and execution (auto-mate)

---

## Context

The user works by voice and stream of consciousness. The requirement is that nothing said,
drafted or planned can trigger execution until the user has confirmed it, and that the user
never has to tag their own speech. A design brief proposed a `[game: confirm] [authority: ...]`
header on artifacts, with the model classifying the user's utterances into games. That puts
the decision "did the user confirm" inside the same model that wants to proceed: a prompt, not
an enforcement.

What already exists (checked 2026-10-31):

- The nemawashi walkthrough ends in Stage 4 Ratify; the minor path ends in a yes/no prompt.
- `/henkaten-council:from-plan` persists an approved plan with a frontmatter envelope carrying
  `plan_sha256` and the governance state at capture.
- `schemas/human-approval-log-entry.schema.json` defines `APPR-NNNN` entries with
  `approval_type`, `status`, `linked_decision_id`, `position_paper_path`. No script writes
  them; no `.council/human-approvals.jsonl` exists.
- auto-mate's `Task` is a bare prompt plus repo and base ref.

## Decision

1. **henka-council gains an approval writer**, `scripts/append-approval.py`, writing
   `.council/human-approvals.jsonl` per the existing schema, extended additively with
   `artifact_path`, `artifact_sha256`, `grants` (values: `push-branch`, `open-draft-pr`) and
   `scope` (free object, e.g. `{"sprints": [9, 10]}`). Writers: nemawashi Stage 4, the minor
   single-prompt path, `council-review --restore-autonomy`, and from-plan when the user confirms
   the persisted plan. The hook that enforces append-only on the other three logs covers this one.
2. **auto-mate's `Task` gains a scope reference** and refuses to execute without a valid one in a
   governed repo:

   ```python
   class ScopeRef(BaseModel):
       path: str          # the ratified scope object, relative to the repo
       sha256: str        # digest of `git show <base_ref>:<path>` at dispatch
       approval_id: str   # APPR-NNNN whose artifact_sha256 matches

   class Task(BaseModel):
       ...
       scope: ScopeRef | None = None
   ```

   Validation, before any worktree is provisioned: the approval entry exists, its `status` is
   `approved`, its `artifact_sha256` equals the digest of the file at `base_ref`, and its
   `grants` include what the run needs. Failure ends the run `gated` with the reason. A repo
   without `.council/` makes `scope` optional; `AUTOMATE_REQUIRE_SCOPE=true` forces it anywhere.
   CLI: `automate run "<prompt>" --scope .harness/contracts/sprint-09.md --approval APPR-0012`.
3. **Scope objects are existing artifacts.** For one task: a sprint contract
   (`.harness/contracts/sprint-NN.md`), the stack's source of truth for done. For a batch: the
   sprint plan (`.harness/sprints.json`) with `scope.sprints`, ratified once, mirroring the
   yokoten ratify-once shortcut (v2.1 amendment A9). After Phase 4: a Discovery Gate package.
4. **Speech is never an authority event.** The user's utterances are classified for routing
   only. The only thing that changes execution authority is an approval entry written by a
   human-facing step.

## Alternatives considered

- **Header fields on artifacts** (`authority: none`). Rejected: the field is written by the
  model that produced the artifact; the check must live in the consumer, and the council
  already has the authority ladder (Levels 0 to 5) and the ratify step.
- **Evaluator contract approval as the grant.** Rejected: the Evaluator is an agent; the
  grant must be human.

## Consequences

- One human step per ratified scope; batch ratification keeps the friction to one step per
  sprint plan.
- Drafts, plans, position papers and transcripts can never start a run.
- The change to auto-mate is one model field, one validation helper, one CLI option, and
  tests against a fixture repo. The schema change is additive.

## Verification

- Governed fixture, no `--scope`: run ends `gated`, reason "no ratified scope reference".
- Governed fixture, scope with stale digest: `gated`, reason names the digest mismatch.
- Governed fixture, valid scope: run proceeds to the crew.
- Ungoverned fixture, no scope: run proceeds (unchanged behavior).
