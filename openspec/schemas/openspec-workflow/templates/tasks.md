# Implementation Tasks for [Change ID]

> **For Claude:** Use `phase-protocol` skill at the start of EACH phase to prevent context drift.

## Status
- Total Tasks: X
- Completed: 0
- In Progress: 0
- Pending: X

---

## Phase 1: [Phase Name]

### Entry Gate
> Read `skills/phase-protocol/SKILL.md` and follow Entry Protocol before starting tasks.

### Tasks
- [ ] 1.1 Write test for Scenario: [name]
  - Spec: `### Requirement: X` → `#### Scenario: Y`
- [ ] 1.2 Implement [function/component]
- [ ] 1.3 Commit: feat([cap]): [description]

### Exit Gate
> After completing all Phase 1 tasks:
> 1. Update this file (mark tasks [x], update Status and Completion Tracking)
> 2. Git commit
> 3. Re-read `phase-protocol` skill and create Phase 2 TODO

---

## Phase 2: [Phase Name]

### Entry Gate
> Read `skills/phase-protocol/SKILL.md` and follow Entry Protocol before starting tasks.

### Tasks
- [ ] 2.1 Write test for Scenario: [name]
  - Spec: `### Requirement: X` → `#### Scenario: Y`
- [ ] 2.2 Implement [function/component]
- [ ] 2.3 Commit

### Exit Gate
> After completing all Phase 2 tasks:
> 1. Update this file
> 2. Git commit
> 3. Re-read `phase-protocol` skill and create Phase 3 TODO (or proceed to finish)

---

## Phase 3: [Final Phase Name]

### Entry Gate
> Read `skills/phase-protocol/SKILL.md` and follow Entry Protocol before starting tasks.

### Tasks
- [ ] 3.1 Integration tests
- [ ] 3.2 Final verification
- [ ] 3.3 Documentation updates

### Exit Gate
> After completing all Phase 3 tasks:
> 1. Update this file
> 2. Git commit
> 3. Proceed to `/opsx-verify` then `/opsx-archive`

---

## Completion Tracking

| Phase | Tasks | Completed | Status |
|-------|-------|-----------|--------|
| Phase 1 | 3 | 0 | PENDING |
| Phase 2 | 3 | 0 | PENDING |
| Phase 3 | 3 | 0 | PENDING |
| **Total** | **9** | **0** | **0%** |

**Status values:** `PENDING` → `IN_PROGRESS` → `COMPLETE`

---

## Phase Protocol Reminder

```
┌────────────────────────────────────────────────────────────────┐
│ 🔴 AT START OF EACH PHASE:                                      │
│    1. Read openspec apply skill                                  │
│    2. Read this tasks.md                                        │
│    3. CREATE TODO IMMEDIATELY (before reading other docs)       │
│    4. Gate: Verify TODO completeness                            │
│    5. Read plan.md, design.md, specs/*.md                       │
│    6. Gate: Output key understanding                            │
│    7. Begin implementation                                      │
├────────────────────────────────────────────────────────────────┤
│ 🔴 AT END OF EACH PHASE:                                        │
│    1. Update this tasks.md                                      │
│    2. Git commit                                                │
│    3. Re-read phase-protocol skill                              │
│    4. Create next phase TODO → Loop back                        │
└────────────────────────────────────────────────────────────────┘
```
