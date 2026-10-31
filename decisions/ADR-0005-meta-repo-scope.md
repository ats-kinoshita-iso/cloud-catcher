# ADR 0005: What cloud-catcher is and is not

- **Status:** Proposed
- **Date:** 2026-10-31
- **Author:** cloud-catcher bootstrap (planning session)
- **Scope:** The boundary of this repository

---

## Context

A design brief proposed a seven-repository topology: an integration monorepo holding
contract schemas, four new component repos, a composition manifest with semver pins, Pact-style
consumer-driven contract tests, can-i-deploy checks and shadow runs. The stack has one
maintainer, its components are markdown skills and Python Protocols invoked by command path
with exit codes, and the schemas already have owners: henka-council's `schemas/`, trine-eval's
`tasks.json` schema, auto-mate's pydantic models.

## Decision

cloud-catcher **is**:

- the plan (`PLAN.md`, `plan/sprints.json`) and the cross-component decisions (`decisions/`);
- the composition manifest (`manifest.json`), a record of what is installed, not a release gate;
- the cross-project work record (`index/`), the archivist's task definition (`archivist/`),
  the capture inbox (`inbox/`), and the sink for headless run records (`runs/`, on the
  `work-record` branch);
- a workspace definition (`workspace/`) that clones the sibling repos for AI context.

cloud-catcher **is not**:

- a home for component source; the three components stay independently installable;
- a contracts repository; schemas stay with the component that owns them;
- a release pipeline; there are no version pins beyond recording observed versions.

Growth rule: something moves here only if it spans two or more projects and has no owner repo.

## Consequences

- The "virtual monorepo for AI context" is a script, not a structure.
- Contract tests, where wanted, are golden tests of the existing CLI contracts inside the
  component that owns them (for example a test of the gate invocation
  `<gate> <task-id> <branch> <intent> [<base-ref>]` in auto-mate).

## Verification

- `git ls-files` in this repo contains no `.py` outside `scripts/` and no plugin manifests.
