# cloud-catcher

The meta-repo for the agentic stack. It holds the plan, the decisions, the
composition manifest, the cross-project work record, and the archivist's
task definition. It holds **no component source**: the components stay in
their own repos and remain independently installable.

| Component | Repo | Role |
|---|---|---|
| trine-eval | `ats-kinoshita-iso/trine-eval` | Evaluation: sprint contracts, rubrics, trials, regression graduation; the `trine_eval` eval library |
| henkaten-council | `ats-kinoshita-iso/henka-council` | Governance: henkaten detection, append-only ledgers, autonomy floor, andon, nemawashi |
| auto-mate | `ats-kinoshita-iso/auto-mate` | Headless execution lifecycle: worktree, crew, gates, safe-push, PR review |
| cloud-catcher | this repo | Plan, decisions, manifest, work record, archivist |

## Layout

```
PLAN.md                        the phased implementation plan (start here)
plan/sprints.json              machine-readable decomposition, one entry per sprint per repo
decisions/                     ADRs (same format as henka-council's docs/design/adr-*)
manifest.json                  what is installed, which version, which role
workspace/repos.json           sibling repos to clone for AI context
workspace/sync.sh              clones or fast-forwards them into workspace/<name>/ (git-ignored)
index/work-record.schema.json  schema of the cross-project work record the archivist builds
index/diagnostic-event.schema.json  schema of diagnostic events (tokens, cost, tool use, outcomes; ADR-0006)
index/diagnostics/             monthly event files the archivist maintains (work-record branch)
index/README.md                what the work record aggregates and how its signals are derived
archivist/briefing-task.md     the scheduled-task prompt for the archivist (fresh session per firing)
inbox/<project>/               captures filed by the archivist from the project's Drive inbox
```

## Using it as a workspace

```bash
bash workspace/sync.sh          # clone or update every sibling repo under workspace/
```

Open this repo in Claude Code and the sibling checkouts give the session the
whole stack's context without vendoring anything.

## Conventions

- JSON for structured data, markdown for prose (trine-eval's harness convention).
- Ledgers are append-only and live in each governed project's `.council/`; this
  repo never writes to a sibling's ledgers. The archivist writes only here and
  to Drive (see `decisions/ADR-0004-storage-split.md`).
- Existing names are kept. Nothing here introduces a vocabulary the component
  repos do not already use.
