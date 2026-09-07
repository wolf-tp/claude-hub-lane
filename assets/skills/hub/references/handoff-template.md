# Handoff template — passing the `hub` or `lane` role to the next session

> **How to use:** copy the block below into a new file, fill every `<…>`, delete unused lines, keep the
> section order (the next session reads by number, and the **paste line** in §6 points at those numbers).
> **File name:** `<handoff-dir>/YYYY-MM-DD-hub-<repo>-handoff.md` or
> `<handoff-dir>/YYYY-MM-DD-lane-<repo>-<slug>-handoff.md`. A second handoff the same day gets `-2`.
> **Write it before you run out of context, not after.** Write it first, *then*
> `lane-coord.sh hub release` (or `lane release <lane>`) — the other order leaves a window with no owner.

---

# Handing over the <HUB|LANE> role — <DD/MM/YYYY HH:MM> (<old session name> → new session)

> Session <HH:MM>–<HH:MM>. Shared ledger (append-only, one line per milestone, prefixed `[hub]` /
> `[lane-<slug>]`): `<ledger path>` — **read the last 60 lines before doing anything**.
> Previous handoff: `<path — or "none">`.
> Lock registry: `~/.claude/bin/lane-coord.sh status` — the source of truth for who holds what;
> `ListAgents` is only an address book.
> Plan in flight: `<path>`. Project adapter: `~/.claude/skills/hub/references/adapters/<repo>.md`.

## 0. What changed this session (read before touching anything)

1. `<architectural decision / ruling — with the path or ledger line that proves it>`
2. `<what the owner decided, and when>`
3. `<a change to the ritual, a CI gate, or the merge rule — binding from now on>`
4. `<what landed on the base branch: which PRs, which numbers moved>`

## 1. Lanes × what they hold × what is next

| Lane (name in `ListAgents`) | Holds (task · branch · worktree · SHA) | Next |
|---|---|---|
| `lane-<repo>-<slug>` | `<plan>#<task>` · `<branch>` · `<worktree>` · `<short sha>` — `<state in one sentence>` | `<next step · what blocks it · which lane must finish first>` |

⚠ Duplicate names: the harness appends a `[xxxxxx]` suffix when two sessions share a name — write the real
suffix here. A lane showing `DEAD` in `lane-coord.sh status`: read its worktree and ledger tail **before**
claiming over it or reopening under the same name.

## 2. The ritual (unchanged, plus this session's additions)

- The six message kinds and their required fields: `~/.claude/skills/hub/references/messages.md`.
  Reject a `READY` that is missing fields; never fill in the blanks yourself.
- A lane does not code until `lane-coord.sh lane claim` returns `CLAIMED`; on `BUSY` it sends an `ASK`.
- The hub only ACKs after: the SHA matches three ways · a findings table exists · verify passed.
- A lane merges after the `ACK`, per project governance; the hub merges only after 15 minutes of silence,
  or for its own docs PR.
- The branch is frozen from `READY` until `ACK`/`FIX` — no further commits, not even correct ones.
- `<this session's addition: the trap you just hit, now written as a rule>`

## 3. What is left, in order

| # | Work | Lane | State | Blocked by |
|---|---|---|---|---|
| 1 | `<work>` | `<lane>` | in progress / next / not started / on hold | `<condition>` |

## 4. Waiting on the owner

1. `<question — what it blocks — what happens by default if nobody answers>`

## 5. Traps hit this session (do not repeat)

- `<symptom → cause → how to avoid, one line each>`

## 6. Paste line for the next session

```
You are the <role> <name> of <repo>. Read <handoff path>, then the last 60 lines of <ledger path>. Run ListAgents; message <the lanes / the hub>: "the new <role> is <name>, the ritual is unchanged". Continue from §<n>.
```

After pasting, the new session runs `~/.claude/bin/lane-coord.sh hub register hub-<repo>` (a lane:
`lane claim <lane> <task-id> <branch> <worktree>`), then `status` to print the board, and only then
sends its messages.
