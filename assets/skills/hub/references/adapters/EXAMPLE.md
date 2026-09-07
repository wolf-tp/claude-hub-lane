# Adapter template — `<repo>`

> Copy this to `~/.claude/skills/hub/references/adapters/<repo>.md` and fill it in. An adapter holds
> everything a hub and a lane must know that is **specific to one repository**. The core skills stay
> untouched — that is the whole point of keeping this in a separate file.
>
> Rule of thumb: if a command would be wrong in another repo, it belongs here.

## Worktree + branch

Which branch lanes cut from, and where worktrees live.

```bash
git -C <repo path> fetch -q origin <base branch>
git -C <repo path> worktree add ../<repo>-wt/<slug> -b <type>/<scope>-<desc> origin/<base branch>
```

`<type>` ∈ `feat | fix | chore | docs | refactor | test`. One lane = one branch = one worktree.
When the slice is merged: `git -C <repo path> worktree remove ../<repo>-wt/<slug>`.

## Opening a lane

```bash
cd <repo path>-wt/<slug>
claude --mcp-config '{"mcpServers":{}}' --strict-mcp-config \
  --bg -n lane-<repo>-<slug> --model opus --permission-mode <same class as the hub> "Use the lane skill (Skill tool), then follow the ASSIGN below.
<the full ASSIGN>"
```

The two MCP flags go **before** `--bg` (they are variadic). Drop them for a slice that genuinely needs a
browser or a database MCP server.

## Verify

The command a lane must run before `READY`, per area.

| Scope | Command |
|---|---|
| Default (any slice) | `<e.g. npm test>` |
| Frontend | `<e.g. npm run typecheck && npm run lint && npm run build>` |
| Backend | `<e.g. go test -race ./...>` |

State explicitly what does **not** count as a PASS (for example a result that only defers to CI).

## Pull request

- How PRs are opened here (a template? a script? a required description section?).
- Any check that must run before opening one.
- **Who is allowed to press merge.** If a human maintainer merges, say so plainly: the lane reports
  `merged_sha: pending-maintainer` and never calls the merge API.

## Three-way SHA (the hub, before an ACK)

The commands that prove branch head = PR sha = CI sha. For GitHub:

```bash
gh pr view <N> --json headRefOid,statusCheckRollup -q '.headRefOid'
git ls-remote origin refs/heads/<branch>
```

A mismatch means a commit landed after CI ran ⇒ **do not ACK**, send a `FIX` asking for a fresh SHA.

## Numbered artifacts that cannot be reserved

Migrations, sequence files, anything where two lanes may grab the same number. Write the command that
reads the current maximum, and the rule (usually: take max+1 at push time, renumber on collision).

## Review

Which reviewer the hub should dispatch for which kind of change, and which model.

| Change | Reviewer | Model |
|---|---|---|
| Default | `<agent or skill>` | `<model>` |
| Security-sensitive (auth, money, personal data) | `<agent>` | `<model>` |

The result must be a `Finding | Severity | Evidence file:line | Action` table plus a verdict.

## Ledger

Where the append-only progress file lives, and the exact line shape:

```
HH:MM [hub|lane-<slug>] <event> — <pointer>
```

## Single-occupant resources

Anything only one session may hold at a time: a shared browser profile, a local stack, fixed ports, a test
database. For each one: how to acquire it, how to wait, and how to release it. The rule is always
**poll and wait**, never spawn a second one.
