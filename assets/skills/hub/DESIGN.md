# DESIGN — `hub` & `lane`: many Claude Code sessions working as one team

> Scope: a **global** skill pair under `~/.claude/`, usable in any repository. It uses only what Claude
> Code ships natively — no MCP server, no tmux orchestrator, no second runtime.

## 0. One sentence

**Many sessions working as one team, without stepping on each other.**

One `hub` session (a strong model) holds architecture, cuts slices, issues rulings, reviews and ACKs.
N `lane` sessions each take one slice, one branch, one worktree, and report in fixed formats. Live state
lives in files, not in messages and not in anyone's memory.

## 1. The native parts this is built on (verified on Claude Code 2.1.26x)

| Need | Mechanism |
|---|---|
| Independent sessions message each other | `SendMessage` to a session name; mail arrives as `<cross-session-message from="uds:…" from-name="…" from-mode="…">`, delivered over a Unix socket, never through a server |
| A stable address | `claude -n <name>` · `/rename <name>` · `@<name>` in a prompt · `claude --resume <name>` |
| Know a lane is free without polling | `SendMessage{notify_when_idle: true}` — one notice, main conversation only, same machine only |
| Long-lived lanes you can attach to | `claude --bg -n <name> --model <m> "<prompt>"` → `claude agents` / `attach` / `logs` / `stop` / `rm` |
| A different model per lane | `--model` per session |
| File isolation | one git worktree per lane |
| A cross-session lock | `~/.claude/bin/lane-coord.sh` (atomic `noclobber` claim, identity = the owning `claude` pid, auto-reclaim when that pid dies) |

**The trap that bites first:** mail between two sessions in **different permission classes** (one bypassing
prompts, one prompting) is *held* for five minutes and then dropped. Fix it with
`"crossSessionInbound": "accept"` in `~/.claude/settings.json` (the installer adds it), and still launch
lanes with the hub's `--permission-mode`.

**Do not call these:** `TeamCreate`, `TaskCreate`, `TaskGet`, `TeamDelete` — removed from the harness.
A subagent given a `name` is a teammate; that is a different, in-session mechanism.

## 2. The two roles

| | `hub` | `lane` |
|---|---|---|
| Count per repo | 1 (a role, not a fixed session — it hands over) | N (2–5 recommended) |
| Name | `hub-<repo>` | `lane-<repo>-<slug>` |
| Does | architecture · disjoint slices · `ASSIGN` · `RULING` · review · `ACK`/`FIX` · collects evidence · handoff | `claim` → TDD → verify → e2e → PR → `READY` → fix on `FIX` → merge after `ACK` → `DONE` |
| Never | edits a lane's code · polls · merges for a lane · ACKs with "looks good" | codes before a successful claim · edits outside `own:` · merges before an `ACK` · sends progress pings |

`<repo>` = `lane-coord.sh repo` (basename of the **main** repo via `git rev-parse --git-common-dir`, so it
is right inside a linked worktree too); override with `HUB_REPO`.

## 3. One channel, six messages

Full formats: `references/messages.md`. `ASSIGN` · `RULING` · `ACK`/`FIX` (hub→lane); `ASK` · `READY` ·
`DONE`/`BLOCKED` (lane→hub). First line is `<KIND> <sender> — <one self-contained sentence>`, because the
harness previews only that line. Evidence travels as a file path; messages carry pointers, not payloads.

## 4. State is files

| What | Where | Written by |
|---|---|---|
| Lock registry | `~/.claude/hub/<repo>/{HUB, lanes/<lane>, lanes/<lane>.frozen, tasks/<task>}` | `lane-coord.sh` |
| Ledger | an append-only progress file in the repo, prefixed `[hub]` / `[lane-<slug>]` | hub + lanes, one line per milestone |
| Handoff | a dated file from `references/handoff-template.md`, ending in a paste line | whoever leaves a role |
| Roster | `lane-coord.sh status` — the source of truth; `ListAgents` is only an address book | the machine |

## 5. Lifecycle

1. **Open the hub**: `claude -n hub-<repo>` → `/hub` → name check, inbox check, `hub register`, read state, print board.
2. **Cut slices**: disjoint `own:` sets; one owner per shared contract; measurable acceptance + a verify command each.
3. **Open lanes**: a worktree per lane, then `claude --bg -n lane-<repo>-<slug> --model … "<ASSIGN>"` whose
   first line loads the `lane` skill. Or the user opens one by hand and types `/lane`.
4. **Lane works**: `claim` → TDD → verify → e2e → PR → `READY` → `freeze`.
5. **Hub reviews**: fields complete → three-way SHA → re-run verify at that SHA → dispatch a reviewer →
   findings table → `ACK` or `FIX` (max 3 rounds).
6. **Merge**: the lane merges after the `ACK`, following the project's governance. `DONE` → `release`.
7. **Handoff**: write the file, `release`, print the paste line, tell every live lane the new hub's name.

## 6. Gates

| # | Gate | Held by |
|---|---|---|
| G1 | No successful claim, no code | `lane-coord.sh lane claim` + the `lane-gate.py` hook denying Edit/Write |
| G2 | `READY` only with verify PASS + e2e evidence + `tests: all_pass` + a frozen branch | the required fields, plus `lane freeze` + the hook blocking edits and git writes |
| G3 | `ACK` only after a matching SHA, a findings table, and a re-run verify | the hub skill + the project adapter |
| G4 | The lane merges after `ACK`; the hub only on 15 minutes of silence or its own docs PR | the ritual |
| G5 | Handoff and release before leaving a role | the skill; `status` exposes orphans |

`lane-gate.py` is a PreToolUse hook that fires **only** for sessions named `hub-*` or `lane-*` (the name is
read from `~/.claude/sessions/<pid>.json`), is fail-open by construction, and costs ~50 ms for every other
session on the machine.

## 7. Files

```
~/.claude/skills/hub/SKILL.md                 the hub role
~/.claude/skills/hub/DESIGN.md                this file
~/.claude/skills/hub/install.sh               install/update on a machine (--check | --force)
~/.claude/skills/hub/references/messages.md   the six message formats (shared with the lane skill)
~/.claude/skills/hub/references/handoff-template.md
~/.claude/skills/hub/references/adapters/EXAMPLE.md   template: one file per repository
~/.claude/skills/hub/tests/*.test.sh          bash suites for the registry, the gate, the installer
~/.claude/skills/lane/SKILL.md                the lane role
~/.claude/commands/{hub,lane}.md              /hub and /lane
~/.claude/bin/lane-coord.sh                   lock registry + freeze/unfreeze
~/.claude/bin/lane-gate.py                    the PreToolUse gate
~/.claude/settings.json                       + "crossSessionInbound": "accept" and the hook entry
```

## 8. Deliberately not included

No MCP server, no tmux orchestrator, no separate task board, no auto-merge, no plan-approval protocol, no
model proxy. Each of those either duplicates something native, or takes a decision that belongs to the
project's own CI and its humans.

## 9. Installing elsewhere

`npx claude-hub-lane` — or copy the folders and run `bash ~/.claude/skills/hub/install.sh`. The installer
is idempotent: it copies a whitelist, backs up `settings.json` before touching it, merges exactly two keys
(the hook command written with `$HOME`, never an absolute path), re-measures what it wrote, and runs the
test suites. `--check` reports without writing. `--force` is needed only when the target machine already
sets a stricter `crossSessionInbound`; by default the installer warns instead of loosening it.

Requirements on the target: Claude Code ≥ 2.1.224, `python3`, `git`, and a POSIX shell. Windows is not
supported (WSL is). Each repository then wants its own adapter file — start from `EXAMPLE.md`.

## 10. Extending safely

A new message kind = a section in `references/messages.md` plus one line in both skills. A new gate = a
subcommand in `lane-coord.sh` with a test. A new project = one adapter file. The core stays untouched.
