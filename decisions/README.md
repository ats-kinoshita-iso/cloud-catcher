# Decisions

Architecture decision records for the stack as a whole. Decisions that belong
to one component live in that component's repo (henka-council keeps its own
under `docs/design/adr-*`); only cross-component decisions live here. Format
follows henka-council's ADRs: Status, Date, Author, Scope, then Context,
Decision, Alternatives, Consequences, Verification.

| ADR | Title | Status |
|---|---|---|
| [0001](ADR-0001-runtime.md) | Runtime: stay on Claude Code through Phase 4; revisit for the headless path at the Phase 5 gate | Accepted 2026-10-31 |
| [0002](ADR-0002-governance-join.md) | Governance join: auto-mate reads council state, persists run records; the council ingests them | Accepted 2026-10-31 |
| [0003](ADR-0003-scope-ref.md) | Scope reference: a ratified approval entry is the precondition for execution | Accepted 2026-10-31 |
| [0004](ADR-0004-storage-split.md) | Storage: git is the system of record, Drive is the reading and capture plane | Accepted 2026-10-31 |
| [0005](ADR-0005-meta-repo-scope.md) | What cloud-catcher is and is not | Accepted 2026-10-31 |
| [0006](ADR-0006-diagnostics.md) | Diagnostics: one event schema, two capture paths, one place to study | Accepted 2026-10-31 |

`Proposed` means awaiting Level 5 ratification by the human. Ratification is
recorded by flipping the status and noting the date; accepted ADRs are the
sacred-file equivalents for this repo. ADR-0001 to ADR-0006 were ratified on
2026-10-31. Amendments to an accepted ADR are appended under an
`## Amendments` heading with their own date, never edited in place.
