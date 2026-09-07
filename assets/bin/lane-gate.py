#!/usr/bin/env python3
"""lane-gate.py — PreToolUse gate for the `hub` / `lane` skills (peer-session orchestration).

Fires ONLY when this session's name (from ~/.claude/sessions/<claude-pid>.json, the record
`claude -n` / `/rename` maintain) starts with `hub-` or `lane-`. Every other session: exit 0, no output.
Fail-open: any error → allow. A deny is the documented PreToolUse JSON (permissionDecision=deny).

Gates:
  lane  G1  Edit/Write/MultiEdit/NotebookEdit inside a repo require `lane-coord.sh lane claim` held by THIS pid.
  lane  G2  while `lanes/<lane>.frozen` exists (READY sent): no file edits except ledger/handoff, no git commit/push/merge/rebase.
  hub       while any lane is active: hub may only write docs (docs/**, .superpowers/**, *.md, ~/.claude/**).
Test overrides: LANE_GATE_PID, LANE_GATE_NAME, HUB_REPO, HUB_COORD_DIR.
"""
import json, os, re, subprocess, sys

H = os.path.expanduser("~")
EDIT_TOOLS = {"Edit", "Write", "MultiEdit", "NotebookEdit"}
GIT_MUTATE = re.compile(r"\bgit\b[^|;&\n]*\b(commit|push|merge|rebase|cherry-pick|am|reset|revert)\b")


def allow():
    sys.exit(0)


def deny(reason):
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse",
                                             "permissionDecision": "deny",
                                             "permissionDecisionReason": reason}}, ensure_ascii=False))
    sys.exit(0)


def my_claude_pid():
    pid = os.getpid()
    for _ in range(25):
        try:
            out = subprocess.run(["ps", "-o", "ppid=,command=", "-p", str(pid)],
                                 capture_output=True, text=True, timeout=2).stdout.strip()
        except Exception:
            return None
        if not out:
            return None
        ppid, _, cmd = out.partition(" ")
        if re.search(r"(^|/)claude( |$|--)", cmd.strip()):
            return pid
        try:
            ppid = int(ppid.strip() or 0)
        except ValueError:
            return None
        if ppid <= 1:
            return None
        pid = ppid
    return None


def repo_slug(start):
    if os.environ.get("HUB_REPO"):
        return os.environ["HUB_REPO"]
    try:
        out = subprocess.run(["git", "rev-parse", "--path-format=absolute", "--git-common-dir"],
                             cwd=start, capture_output=True, text=True, timeout=3)
    except Exception:
        return None
    if out.returncode != 0:
        return None
    return os.path.basename(os.path.dirname(out.stdout.strip()))


def is_doc(path):
    """Hub exemption: docs, specs, plans, ledger, handoff, ~/.claude — never a lane's code."""
    p = path or ""
    return ("/docs/" in p or "/.superpowers/" in p or p.endswith(".md")
            or p.startswith(H + "/.claude/"))


def is_ledger_or_handoff(path):
    """Frozen-lane exemption: ONLY the append-only ledger and the handoff file — a frozen
    lane's own .md/skill/doc files are still the slice under review and stay locked."""
    p = path or ""
    return "/.superpowers/" in p or "/docs/superpowers/handoff/" in p


def main():
    try:
        d = json.load(sys.stdin)
    except Exception:
        allow()
    pid = os.environ.get("LANE_GATE_PID") or my_claude_pid()
    if not pid:
        allow()
    name = os.environ.get("LANE_GATE_NAME")
    if not name:
        try:
            name = json.load(open(f"{H}/.claude/sessions/{pid}.json")).get("name", "")
        except Exception:
            allow()
    if not (name.startswith("lane-") or name.startswith("hub-")):
        allow()

    tool = d.get("tool_name", "")
    ti = d.get("tool_input") or {}
    path = ti.get("file_path") or ti.get("notebook_path") or ""
    cmd = ti.get("command") or ""
    cwd = d.get("cwd") or os.getcwd()
    start = cwd
    if path and os.path.isabs(path) and os.path.isdir(os.path.dirname(path)):
        start = os.path.dirname(path)
    repo = repo_slug(start)
    if not repo:
        allow()  # outside any git repo → not our business
    co = os.environ.get("HUB_COORD_DIR") or f"{H}/.claude/hub/{repo}"
    lanes = f"{co}/lanes"

    if name.startswith("lane-"):
        frozen = os.path.exists(f"{lanes}/{name}.frozen")
        held = False
        try:
            with open(f"{lanes}/{name}") as f:
                held = f.read().split()[0] == str(pid)
        except Exception:
            held = False
        if tool in EDIT_TOOLS:
            if frozen and not is_ledger_or_handoff(path):
                deny(f"G2: nhánh đã đóng băng (đã gửi READY, chờ ACK/FIX) — không sửa {path}. "
                     f"Nhận ACK/FIX rồi chạy `~/.claude/bin/lane-coord.sh lane unfreeze {name}`.")
            if not held:
                deny(f"G1: session {name} chưa claim lát nào trong repo {repo} — chạy "
                     f"`~/.claude/bin/lane-coord.sh lane claim {name} <task-id> <branch> <worktree>` "
                     f"(CLAIMED / TOOK-OVER-ORPHAN) trước khi sửa file. BUSY thì gửi ASK, không code.")
        elif tool == "Bash" and frozen and GIT_MUTATE.search(cmd):
            deny(f"G2: nhánh đã đóng băng — không commit/push/merge/rebase cho tới khi có ACK/FIX; "
                 f"rồi `~/.claude/bin/lane-coord.sh lane unfreeze {name}`.")
        allow()

    # hub
    if tool in EDIT_TOOLS and path:
        try:
            active = any(not f.endswith(".frozen") for f in os.listdir(lanes))
        except Exception:
            active = False
        if active and not is_doc(path):
            deny("Hub CẤM tự sửa code lát khi đang có lane hoạt động — giao qua ASSIGN/FIX. "
                 "Hub chỉ ghi docs/handoff/ledger (docs/**, .superpowers/**, *.md, ~/.claude/**).")
    allow()


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except Exception:
        sys.exit(0)
