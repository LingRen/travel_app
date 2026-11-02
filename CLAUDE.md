<!-- SUPERSPEC:START -->
# SuperSpec Instructions

This project uses SuperSpec for spec-driven development with TDD discipline.

## Quick Reference

| Command | Description |
|---------|-------------|
| `/superspec:kickoff` | **Fast track**: brainstorm + validate + plan in one session |
| `/superspec:brainstorm` | **Full workflow**: progressive design (Explore → Propose → Spec) |
| `superspec validate [id]` | Validate specifications (CLI) |
| `/superspec:plan` | Create TDD implementation plan (after brainstorm) |
| `/superspec:execute` | Execute with subagent-driven TDD |
| `/superspec:verify` | Verify implementation matches specs |
| `/superspec:finish-branch` | Complete branch (merge/PR) |
| `/superspec:archive` | Archive changes |

## Four Iron Rules

1. **TDD Rule**: No production code without a failing test first
2. **Spec Rule**: Specs are truth. Changes are proposals.
3. **SuperSpec Rule**: Every Scenario becomes a test. Every test traces to a Scenario.
4. **Verification Rule**: No completion claims without fresh verification evidence

## Workflow

```
Fast track:   /superspec:kickoff → execute → verify → finish-branch → archive
Full workflow: brainstorm → validate → plan → execute → verify → finish-branch → archive
```

Use `/superspec:kickoff` for quick features or `/superspec:brainstorm` for larger changes.

Keep this managed block so `superspec init` can refresh the instructions.
<!-- SUPERSPEC:END -->
