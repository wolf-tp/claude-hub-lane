# claude-hub-lane

**Many Claude Code sessions working as one team, without stepping on each other.**

One **hub** session holds the architecture, cuts the work into disjoint slices, reviews, and approves.
N **lane** sessions each take one slice in their own git worktree, on their own model, and report back in
six fixed message formats. They talk over Claude Code's native cross-session messaging — no MCP server, no
tmux orchestrator, no second runtime.

```
                 ┌──────────────────────┐
                 │  hub-myrepo  (Opus)  │  architecture · slices · review · ACK
                 └──────────┬───────────┘
        ASSIGN / RULING     │     ASK / READY / DONE
     ┌──────────────────────┼──────────────────────┐
     ▼                      ▼                      ▼
 lane-myrepo-api      lane-myrepo-ui        lane-myrepo-docs
 worktree + branch    worktree + branch     worktree + branch
```

## Install

```bash
npx claude-hub-lane                  # from npm
npx github:wolf-tp/claude-hub-lane   # straight from this repo, same thing
```

[![npm](https://img.shields.io/npm/v/claude-hub-lane)](https://www.npmjs.com/package/claude-hub-lane)
[![ci](https://github.com/wolf-tp/claude-hub-lane/actions/workflows/ci.yml/badge.svg)](https://github.com/wolf-tp/claude-hub-lane/actions/workflows/ci.yml)

That copies the two skills into `~/.claude/`, adds exactly two keys to `settings.json` (backing it up
first), and runs the test suites. `npx claude-hub-lane check` reports without writing anything;
`npx claude-hub-lane uninstall` removes the files.

**Requirements:** Claude Code ≥ 2.1.224, `python3`, `git`, macOS or Linux (WSL works; native Windows does
not — the lock registry needs `ps`).

## Use

```bash
# terminal 1 — the hub
claude -n hub-myrepo
/hub
```

Tell it what you want built. It proposes a slicing, you approve, and it opens the lanes for you:

```bash
claude --mcp-config '{"mcpServers":{}}' --strict-mcp-config \
  --bg -n lane-myrepo-api --model opus --permission-mode <same as the hub> "<the ASSIGN>"
```

Watch them with `claude agents`, step into one with `claude attach <id>`. Or open a lane yourself in
another terminal and type `/lane` — it finds the hub and asks for work.

## What makes it hold together

**Six messages, nothing else.** `ASSIGN` · `RULING` · `ACK`/`FIX` from the hub; `ASK` · `READY` ·
`DONE`/`BLOCKED` from a lane. Each has required fields; a `READY` missing one gets rejected without
review. Evidence travels as a file path, never pasted into a message. Full formats live in
[`messages.md`](assets/skills/hub/references/messages.md).

**A lock registry, not good intentions.** `lane-coord.sh` gives each task an atomic claim keyed to the
owning session's pid. A second lane claiming the same task gets `BUSY` and has to ask. When a session
dies, the next claim reclaims the orphan automatically — the same shape as a cooperative file lock.

**Gates the machine actually holds.** A PreToolUse hook (`lane-gate.py`) fires *only* for sessions named
`hub-*` or `lane-*` and is fail-open by construction:

| Gate | What it blocks |
|---|---|
| G1 | A lane editing files before its claim succeeded |
| G2 | A lane editing code or running `git commit/push/merge/rebase` after it reported `READY` (the branch is frozen while the hub reviews that exact SHA) |
| — | The hub editing a lane's code while that lane is active — it must delegate through `ASSIGN`/`FIX` |

**State in files, not in context.** A lock registry under `~/.claude/hub/<repo>/`, an append-only ledger in
the repo, and a dated handoff file ending in a paste line. That is what lets the hub role move to a fresh
session mid-flight: paste one line, and the new session picks up the board.

## Adapters: one file per repository

The core knows nothing about your repo. Everything project-specific — how you cut branches, which command
counts as verify, how PRs open, who is allowed to press merge, which numbered artifacts cannot be reserved,
which resources only one session may hold — goes in a single adapter file. Start from
[`EXAMPLE.md`](assets/skills/hub/references/adapters/EXAMPLE.md), save it as
`~/.claude/skills/hub/references/adapters/<repo>.md`, and the core stays untouched.

## Why not a plugin

These are plain files in `~/.claude/`. Claude Code loads them because of where they sit. There is nothing
to register, and uninstalling is deleting a folder. The npm package exists only so that installing is one
command instead of a `tar` and a checklist.

## Design notes

- [`DESIGN.md`](assets/skills/hub/DESIGN.md) — the native mechanisms it stands on, the roles, the
  lifecycle, the gates, and what was deliberately left out.
- [`hub/SKILL.md`](assets/skills/hub/SKILL.md) · [`lane/SKILL.md`](assets/skills/lane/SKILL.md) — what each
  role actually does, including the failure table.

Three traps worth knowing before you start, each of which cost a real debugging session:

1. Messages between sessions in **different permission classes** are held for five minutes and then
   dropped. The installer sets `crossSessionInbound: accept`; still launch lanes with the hub's
   `--permission-mode`.
2. `git rev-parse --show-toplevel` inside a linked worktree returns the *worktree* name, not the repo's.
   Use `lane-coord.sh repo`.
3. The two MCP-silencing flags must come **before** `--bg`; they are variadic, and placed after they
   swallow the prompt, leaving an empty session.

## Development

```bash
npm test    # lock registry (34) · gate (16) · installer (33), all bash, no dependencies
```

CI runs the same three suites on Linux and macOS, then installs the packed tarball into a scratch `HOME`
and checks the `npx` entry point end to end.

## License

MIT
