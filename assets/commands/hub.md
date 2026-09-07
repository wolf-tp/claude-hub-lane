---
description: HUB role — coordinate other Claude sessions (start | status | assign <task-id> | handoff)
---
Invoke the `hub` skill (Skill tool) and run its `$ARGUMENTS` sub-flow (default `start`). Sub-flows: `start` = the startup checklist; `status` = `lane-coord.sh status` plus a ListAgents summary; `assign <task-id>` = cut the slice and dispatch a lane for it; `handoff` = write the handoff, release, print the paste line.
