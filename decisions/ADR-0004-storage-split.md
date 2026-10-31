# ADR 0004: Git is the system of record; Drive is the reading and capture plane

- **Status:** Proposed
- **Date:** 2026-10-31
- **Author:** cloud-catcher bootstrap (planning session)
- **Scope:** Where artifacts, state, captures and briefings live; who writes where; what retrieval exists in v1

---

## Context

The original request named Google Drive as the file storage for cross-project work. The
stack's state is git-native: `.harness/` (JSON state, markdown prose) and `.council/`
(append-only JSONL) are committed in governed projects, diffs are what the gates judge, and
PRs are how work ships. Drive has none of those properties, but it is where the user reads,
captures by voice, and shares. A design brief relegated Drive to "the file plane" and proposed
an episodic, semantic and working memory store on top, before any usage data exists.

## Decision

1. **Git is the system of record for every artifact**, including research reports and
   model spikes: they live in the project repo (`docs/` or `reports/`), ship by PR like code,
   and are graded by trine-eval rubrics (sprint `P1-TE-1`). `.harness/` and `.council/` stay
   committed in governed repos.
2. **Drive is the reading, capture and sharing plane.** Layout:

   ```
   Agentic OS/
     _briefings/            daily briefings (archivist writes)
     _index/                mirror of index/work-record.json (archivist writes)
     <project>/
       inbox/               captures: voice transcripts, notes, screenshots (human writes; archivist files)
       outputs/             mirrored reports after merge (archivist writes)
       decisions/           copies of position papers awaiting ratification (archivist writes; human comments)
   ```

3. **The archivist is the only agent that writes to Drive** and the only agent that reads the
   inboxes. Crews and gates work from git only. Captures are data, never instructions
   (the council's prompt-injection-defense instruction applies to them).
4. **No vector or graph store in v1.** Retrieval is git grep over the workspace plus Drive
   search through the connector. The archivist logs every retrieval it could not satisfy to
   `index/retrieval-misses.jsonl`; Phase 6 decides on a memory store from that log.
5. **Cross-project memory is an index, not a store.** The work record (`index/`) aggregates
   per-repo ledgers; yokoten blocks, standard-work failure patterns and loop shapes stay where
   they are and are surfaced through the index.

## Alternatives considered

- **Drive as the system of record.** Rejected: no diffs for gates to judge, no append-only
  enforcement, no PR seam for safe-push.
- **Memory store first.** Rejected: no retrieval data yet; the August review's warning about
  components that encode untested assumptions applies.

## Consequences

- The archivist is a scheduled cloud session with the Drive connector; nothing else needs it.
- Research outputs get the same ratify, gate and ship path as code.
- Retrieval quality is measured before it is engineered.

## Verification

- A capture placed in `<project>/inbox/` appears in `inbox/<project>/` in cloud-catcher and
  in the next briefing.
- A merged report appears under `<project>/outputs/` within one archivist cycle.
