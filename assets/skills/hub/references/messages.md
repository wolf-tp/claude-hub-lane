# The six messages between `hub` and `lane`

Shared source of truth for the `hub` and the `lane` skill. One channel: `SendMessage` between
Claude Code sessions on this machine. Exactly six kinds: `ASSIGN` · `RULING` · `ACK`/`FIX` · `ASK` ·
`READY` · `DONE`/`BLOCKED`. There is no seventh.

## House rules

- **First line** is always `<KIND> <sender> — <one self-contained sentence>`. The harness previews only
  that line, so it has to make sense alone.
- Body ≤ ~40 lines. Longer means you are telling a story, not filing a report.
- Evidence (diffs, logs, screenshots, test output) travels as a **file path**, never pasted inline.
- The hub sets `notify_when_idle: true` on every `ASSIGN` and `FIX` — that is how it learns a lane is
  free without polling.
- A lane touching a shared contract messages the **owning lane directly** and copies the hub in one line.
- No status JSON, no "working on it" pings, no progress reports nobody asked for.
- Reply to the exact `from-name` on the incoming `<cross-session-message>` tag. Never guess a name.

## ASSIGN

**Direction** hub→lane · **When** handing over a slice. It is the startup prompt of `claude --bg`, plus a
one-line copy sent with `SendMessage` so the hub can subscribe to the idle notice.

| Field | Meaning | Example |
|---|---|---|
| `task` · `goal` · `acceptance` | slice id · user-visible outcome · measurable bar (not "it works") | `…#T3` · "a user can filter their own todos" · `GET /api/todos?status=open → 200 {items,total_count}` |
| `own` · `readonly` · `nogo` | files you may edit · read only · never touch | `src/api/todos/**` · `src/db/schema.ts` · `migrations/**` |
| `branch` · `worktree` | branch · its own working directory | `feat/todo-filters` · `../todo-api-wt/todo-filters` |
| `verify` · `e2e` | a command that runs, not a description | `npm test -- todos` · `npx playwright test e2e/todos.spec.ts` |
| `ledger` · `report_to` | append-only progress file · session name to report to | `.notes/2026-01-15-filters/progress.md` · `hub-todo-api` |

```
ASSIGN hub-todo-api — Take slice T3 (todo filters) on branch feat/todo-filters, verify with npm test -- todos.
task: 2026-01-15-todo-filters#T3
goal: a signed-in user narrows their list to open / done / overdue without reloading the page.
acceptance: GET /api/todos?status=open returns 200 {items,total_count}; another user's rows never appear.
own: src/api/todos/** · src/ui/todos/FilterBar.tsx
readonly: src/db/schema.ts · src/lib/auth.ts
nogo: migrations/** · .github/workflows/** · package.json
branch: feat/todo-filters
worktree: ../todo-api-wt/todo-filters
verify: npm test -- todos
e2e: npx playwright test e2e/todos.spec.ts
ledger: .notes/2026-01-15-todo-filters/progress.md
report_to: hub-todo-api
```

## RULING

**Direction** hub→lane · **When** answering an `ASK`, or settling something that binds several lanes.
A lane applies it immediately and does not relitigate it in the same thread.

| Field | Meaning | Example |
|---|---|---|
| `re` · `decision` | which ASK · the decision in one sentence | `ASK#2 lane-todo-api-filters 14:05` · "filter in SQL, not in the client" |
| `why` · `applies_to` | the reason, with evidence · scope | `src/db/README.md §indexes` · "every slice in this plan" |

```
RULING hub-todo-api — Filtering happens in SQL against the existing index, not in the client.
re: ASK#2 lane-todo-api-filters 14:05
decision: push the status filter into the query; drop the client-side Array.filter path.
why: the list is paginated, so client filtering silently drops rows past page 1; idx_todos_status already exists.
applies_to: every slice in plan 2026-01-15-todo-filters
```

## ACK / FIX

**Direction** hub→lane · **When** the hub has checked the SHA and holds a findings table. `verdict:`
decides whether this is an `ACK` or a `FIX`; both carry the same fields.

| Field | Meaning | Example |
|---|---|---|
| `task` · `pr` · `sha` | slice · pull request · the reviewed SHA (must match three ways) | `…#T3` · `#412` · `9f2c1ab` |
| `verdict` · `merge` | `ack` or `fix` · who presses merge: `you` (the lane) or `hub` | `ack` · `you` |
| `findings` | path to a `Finding \| Severity \| file:line \| Action` table, or ≤5 lines | `.notes/reviews/2026-01-15-T3.md` |

```
ACK hub-todo-api — T3 passes review at SHA 9f2c1ab, no blocking findings, you may merge.
task: 2026-01-15-todo-filters#T3
pr: #412
sha: 9f2c1ab
verdict: ack
findings: .notes/reviews/2026-01-15-T3-todo-filters.md — 3 minor notes recorded, none blocking
merge: you

FIX hub-todo-api — T3 is not through: two blockers (tenant leak, silent write failure). Round 1 of 3.
task: 2026-01-15-todo-filters#T3 · pr: #412 · sha: 9f2c1ab
verdict: fix
findings: .notes/reviews/2026-01-15-T3-todo-filters.md — todos/query.ts:88 misses the owner predicate; FilterBar.tsx:141 mutation has no error path
merge: you (after the next ACK)
```

## ASK

**Direction** lane→hub · **When** an ambiguity changes more than one file, you must touch something in
`readonly:`, your claim came back `BUSY`, or verify fails for a reason outside your `own:`. Always two
options and a recommendation.

| Field | Meaning | Example |
|---|---|---|
| `task` · `question` | slice · exactly one question | `…#T3` · "add the column or drop it from this slice?" |
| `options` · `recommend` | concrete A/B · which one you would take and why | `A) … — B) …` · `B` |
| `blocking` · `default_if_silent_15m` | are you stuck · what you do if nobody answers | `no` · "take B, note it in the ledger" |

```
ASK lane-todo-api-filters — The overdue filter needs a due_date index that lives outside my scope; A or B?
task: 2026-01-15-todo-filters#T3
question: filtering by overdue does a full scan without an index on due_date — add one, or drop overdue from this slice?
options: A) add the index (touches migrations/, which is in my nogo) — B) ship open/done now, file overdue as follow-up
recommend: B — it keeps the slices disjoint, and overdue is not in T3's acceptance
blocking: no
default_if_silent_15m: take B, write one ledger line, mention it in READY
```

## READY

**Direction** lane→hub · **When** verify passes, the e2e evidence exists, and the branch is frozen.
This is gate G2 — a missing field means the hub replies `FIX` without reviewing.

| Field | Meaning | Example |
|---|---|---|
| `task` · `branch` · `sha` · `pr` · `ci` | slice · branch · the SHA to review · PR · CI link and colour | `…#T3` · `feat/todo-filters` · `9f2c1ab` · `#412` · "green" |
| `verify` · `e2e` | command + PASS/FAIL + path to the log | `npm test -- todos → PASS · .tmp/verify.log` |
| `tests` · `frozen` | `all_pass` \| `has_skip` \| `has_failure` · is the branch frozen | `all_pass` · `yes` |
| `touched_flows` · `out_of_scope_noticed` | critical flows you touched · things you saw broken outside `own:` | `todo-list` · `src/lib/date.ts:31` |

```
READY lane-todo-api-filters — T3 done at SHA 9f2c1ab, verify PASS, e2e 4/4, branch frozen, awaiting ACK.
task: 2026-01-15-todo-filters#T3
branch: feat/todo-filters
sha: 9f2c1ab
pr: #412
ci: https://github.com/acme/todo-api/actions/runs/8812 — green (lint · test · build)
verify: npm test -- todos → PASS · log .tmp/verify-1450.log
e2e: npx playwright test e2e/todos.spec.ts → 4 passed · .tmp/e2e-todos/
tests: all_pass
touched_flows: todo-list — spec re-run, green
out_of_scope_noticed: src/lib/date.ts:31 parses dates in local time (outside own:, untouched)
frozen: yes
```

After sending `READY`, run `lane-coord.sh lane freeze <lane>`: the gate then blocks edits and commits
until you `unfreeze` on `ACK`/`FIX`. `tests: all_pass` is the ONLY value that earns an `ACK`. `has_skip`
and `has_failure` both get a `FIX`: **SKIP = FAIL** — a skipped test proves nothing.

## DONE / BLOCKED

**Direction** lane→hub · **When** `DONE` after the merge landed and the lock is released; `BLOCKED` when
you genuinely cannot go further alone.

| Field | Meaning | Example |
|---|---|---|
| `task` · `merged_sha` | slice · SHA on the base branch (or `pending-maintainer`) | `…#T3` · `4c81de9` |
| `ledger_line` · `next` | the line you just wrote · free, or what you are on | `15:12 [lane-…] merged #412` · "free" |
| `blocker` · `tried` · `need` | (BLOCKED) where it stops · what you tried · what you need | "two lanes claimed one file" · "read their ledger" · "a RULING on who owns it" |

```
DONE lane-todo-api-filters — T3 merged into main at 4c81de9, lock released, ready for the next slice.
task: 2026-01-15-todo-filters#T3
merged_sha: 4c81de9
ledger_line: 15:12 [lane-filters] merged #412 — .notes/2026-01-15-todo-filters/progress.md
next: free; ran lane-coord.sh lane release lane-todo-api-filters

BLOCKED lane-todo-api-filters — T3 stops: the shared FilterBar is owned by another lane, need a ruling.
task: 2026-01-15-todo-filters#T3
blocker: FilterBar.tsx is in my own: but lane-todo-api-sorting already edits it on its branch.
tried: read the last 60 ledger lines, messaged that lane directly (silent for 20 minutes)
need: a RULING on who owns FilterBar, or a re-cut of the slice
```

## How the hub calls SendMessage

`ASSIGN` and `FIX` — subscribe to one idle notice instead of polling:

```json
{"to": "lane-todo-api-filters", "message": "ASSIGN hub-todo-api — Take slice T3 …\ntask: 2026-01-15-todo-filters#T3\n…", "notify_when_idle": true}
```

`RULING`, `ACK`, and everything a lane sends — no flag:

```json
{"to": "hub-todo-api", "message": "READY lane-todo-api-filters — T3 done at SHA 9f2c1ab …\ntask: 2026-01-15-todo-filters#T3\n…"}
```

`notify_when_idle: true` only works from a main conversation, and only for a session on this machine.
Anywhere else it is a dead flag.

## Rejecting a message that is missing fields

- Hub receives a `READY` with a field missing → reply `FIX` with `verdict: fix` and
  `findings: missing fields: sha, tests, frozen`. **Do not review, do not ACK** — a missing field means
  missing evidence.
- Lane receives an `ASSIGN` without `own:` or `verify:` → reply `ASK` with `blocking: yes`, and **do not
  claim, do not code** until a `RULING` arrives.
- A first line that breaks the shape (no kind, no sender, not self-contained) → reply in one line asking
  for a resend. Do not guess what was meant.
