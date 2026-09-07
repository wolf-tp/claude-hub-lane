---
description: LANE role — take one slice from the hub, work in your own worktree, report in the fixed formats (claim <task-id> | status | handoff)
---
Invoke the `lane` skill (Skill tool) and run its `$ARGUMENTS` sub-flow (default: startup, then request work). Sub-flows: `claim <task-id>` = run gate G1 then start; `status` = `lane-coord.sh status` plus what you hold; `handoff` = write the handoff, release, print the paste line.
