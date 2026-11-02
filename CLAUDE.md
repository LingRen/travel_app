# OpenSpec Instructions

This project uses OpenSpec for spec-driven development with TDD discipline.
All specs and changes live under `openspec/`; schema is `openspec-workflow`
(`openspec/schemas/openspec-workflow/schema.yaml`).

## Quick Reference

| Command | Description |
|---------|-------------|
| `/opsx-propose` | **Fast track**: generate proposal + design + specs in one step |
| `/opsx-new` | Start a change and walk the artifacts step by step |
| `/opsx-explore` | Free-form exploration before committing to a change |
| `/opsx-continue` | Create the next artifact of the active change |
| `/opsx-ff` | Fast-forward all planning artifacts |
| `/opsx-apply` | Implement tasks (TDD, one task at a time) |
| `/opsx-update` | Revise planning artifacts and keep them coherent |
| `/opsx-verify` | Verify implementation covers every requirement and scenario |
| `/opsx-sync` | Apply delta specs to main specs without archiving |
| `/opsx-archive` | Archive one completed change |
| `/opsx-bulk-archive` | Archive several completed changes |
| `/opsx-onboard` | Guided tour of the workflow |

CLI equivalents: `openspec list --specs`、`openspec validate --specs`、
`openspec validate <change> --strict`、`openspec view`。

## Four Iron Rules

1. **TDD Rule**: No production code without a failing test first
2. **Spec Rule**: Specs are truth. Changes are proposals.
3. **Spec Rule**: Every Scenario becomes a test. Every test traces to a Scenario.
4. **Verification Rule**: No completion claims without fresh verification evidence

Gates: `fvm flutter analyze` and `fvm flutter test` must pass before a change is archived.

## Workflow

```
Fast track:     /opsx-propose → /opsx-apply → /opsx-verify → /opsx-archive
Full workflow:  /opsx-new → explore → design → specs → plan → tasks → apply → verify → archive
```

Use `/opsx-propose` for small changes and `/opsx-new` when the design needs discussion.
