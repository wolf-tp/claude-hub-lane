#!/usr/bin/env bash
# install.sh — install the `hub` + `lane` skills (multi-session orchestration) onto a machine.
#
#   bash install.sh            install / update (idempotent; backs up settings.json before touching it)
#   bash install.sh --check    report only, write NOTHING
#   bash install.sh --force    also relax a stricter crossSessionInbound already in settings.json
#
# Source defaults to the tree containing this file. To move it by hand, carry
# skills/hub + skills/lane + commands/{hub,lane}.md + bin/{lane-coord.sh,lane-gate.py},
# or carry skills/hub alone and point HUB_LANE_SRC at a complete .claude tree.
#
# Target machine needs: Claude Code >= 2.1.224 (cross-session messaging), python3, git, bash + ps.
set -u

MODE=install
for a in "$@"; do
  case "$a" in
    --check) MODE=check;;
    --force) MODE=force;;
    -h|--help) sed -n '2,14p' "$0"; exit 0;;
    *) echo "unknown flag: $a (use --check | --force)"; exit 2;;
  esac
done

HERE=$(cd "$(dirname "$0")" && pwd)                 # …/skills/hub
SRC=${HUB_LANE_SRC:-$(cd "$HERE/../.." && pwd)}     # …/.claude nguồn
DST="$HOME/.claude"
SETTINGS="$DST/settings.json"
GATE_CMD='python3 "$HOME/.claude/bin/lane-gate.py"'
MATCHER='Edit|Write|MultiEdit|NotebookEdit|Bash'
warn=0

say()  { printf '%s\n' "$*"; }
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[ -d "$SRC/skills/hub" ] || fail "source not found at $SRC/skills/hub — point HUB_LANE_SRC at the source .claude directory"
for f in skills/hub/SKILL.md skills/lane/SKILL.md commands/hub.md commands/lane.md bin/lane-coord.sh bin/lane-gate.py; do
  [ -f "$SRC/$f" ] || fail "thiếu file nguồn: $SRC/$f"
done

# ---------- dependencies ----------
command -v python3 >/dev/null || fail "python3 is required"
command -v git >/dev/null     || fail "git is required"
if command -v claude >/dev/null; then
  ver=$(claude --version 2>/dev/null | awk '{print $1}')
  py_ok=$(python3 - "$ver" <<'EOF'
import sys
try:
    v=[int(x) for x in sys.argv[1].split(".")[:3]]
    print("ok" if v >= [2,1,224] else "old")
except Exception:
    print("unknown")
EOF
)
  case "$py_ok" in
    old) say "⚠ Claude Code $ver < 2.1.224 — cross-session messaging does not exist yet; upgrade before using hub/lane."; warn=1;;
    unknown) say "⚠ could not read the Claude Code version ($ver) — 2.1.224 or newer is required.";;
  esac
else
  say "⚠ no \`claude\` on PATH — installing anyway, but check that the version is >= 2.1.224."; warn=1
fi

# ---------- report current state ----------
report() {
  local missing=0 f
  for f in skills/hub/SKILL.md skills/lane/SKILL.md commands/hub.md commands/lane.md bin/lane-coord.sh bin/lane-gate.py; do
    if [ -f "$DST/$f" ]; then say "  ok       $f"; else say "  MISSING  $f"; missing=1; fi
  done
  if [ -f "$SETTINGS" ]; then
    python3 - "$SETTINGS" <<'EOF'
import json,sys
try: d=json.load(open(sys.argv[1]))
except Exception as e: print("  settings.json UNREADABLE:",e); sys.exit(0)
print("  crossSessionInbound =",d.get("crossSessionInbound") or "(unset — mail across permission classes gets held)")
n=sum(1 for e in d.get("hooks",{}).get("PreToolUse",[]) for h in e.get("hooks",[]) if "lane-gate" in str(h.get("command","")))
print("  lane-gate hook      =", f"{n} entry" if n else "NOT INSTALLED")
EOF
  else
    say "  settings.json       = not present"; missing=1
  fi
  return $missing
}

if [ "$MODE" = check ]; then
  say "Checking the hub/lane installation in $DST"
  if report; then say; say "Fully installed."; exit 0; else say; say "Not fully installed (missing) — run again without --check to install."; exit 1; fi
fi

# ---------- copy files ----------
mkdir -p "$DST/skills/hub/references/adapters" "$DST/skills/hub/tests" "$DST/skills/lane" "$DST/commands" "$DST/bin" || fail "could not create directories under $DST"
copy() { # copy <relative path>
  [ -f "$SRC/$1" ] || return 0
  mkdir -p "$(dirname "$DST/$1")"
  cp "$SRC/$1" "$DST/$1" || fail "copy failed: $1"
}
for f in \
  skills/hub/SKILL.md skills/hub/DESIGN.md skills/hub/install.sh \
  skills/hub/references/messages.md skills/hub/references/handoff-template.md \
  skills/hub/references/adapters/EXAMPLE.md \
  skills/hub/tests/lane-coord.test.sh skills/hub/tests/lane-gate.test.sh skills/hub/tests/install.test.sh \
  skills/lane/SKILL.md commands/hub.md commands/lane.md bin/lane-coord.sh bin/lane-gate.py
do copy "$f"; done
chmod +x "$DST/bin/lane-coord.sh" "$DST/bin/lane-gate.py" "$DST/skills/hub/install.sh" 2>/dev/null || true
# The source machine's acceptance evidence is deliberately NOT shipped.

# ---------- settings: back up, then merge exactly two keys ----------
[ -f "$SETTINGS" ] || printf '{}\n' > "$SETTINGS"
python3 - "$SETTINGS" "$GATE_CMD" "$MATCHER" "$MODE" <<'EOF'
import json, sys, collections, datetime, shutil, os
path, gate_cmd, matcher, mode = sys.argv[1:5]
try:
    with open(path) as f: raw = f.read()
    d = json.loads(raw or "{}", object_pairs_hook=collections.OrderedDict)
    if not isinstance(d, dict): raise ValueError("settings.json is not a JSON object")
except Exception as e:
    print(f"ERROR: settings.json is broken ({e}) — nothing was changed. Fix it by hand and rerun.", file=sys.stderr)
    sys.exit(1)

bak = f"{path}.hub-lane-bak-{datetime.datetime.now():%Y%m%d%H%M%S}"
shutil.copy2(path, bak)

changed = []
cur = d.get("crossSessionInbound")
if cur in (None, "accept"):
    if cur != "accept": changed.append("crossSessionInbound=accept")
    d["crossSessionInbound"] = "accept"
elif mode == "force":
    changed.append(f"crossSessionInbound {cur!r}→accept (--force)")
    d["crossSessionInbound"] = "accept"
else:
    print(f"⚠ keeping crossSessionInbound={cur!r} (stricter than 'accept'): mail between your sessions will be held or refused.")
    print("  For hub↔lane messaging: rerun with --force, or set that key to \"accept\" yourself.")

hooks = d.setdefault("hooks", collections.OrderedDict())
pre = hooks.setdefault("PreToolUse", [])
if not any("lane-gate" in str(h.get("command", "")) for e in pre for h in e.get("hooks", [])):
    pre.append(collections.OrderedDict([
        ("matcher", matcher),
        ("hooks", [collections.OrderedDict([
            ("type", "command"), ("command", gate_cmd),
            ("timeout", 5), ("statusMessage", "lane-gate (hub/lane only)")])])]))
    changed.append("hook PreToolUse lane-gate")

with open(path, "w") as f:
    json.dump(d, f, indent=2, ensure_ascii=False); f.write("\n")
print("  settings backed up →", os.path.basename(bak))
print("  settings:", ", ".join(changed) if changed else "already correct, nothing changed")
EOF
rc=$?; [ $rc = 0 ] || exit $rc

# ---------- measure again; never trust the write ----------
say "Re-measured after writing:"
report || true
python3 - "$SETTINGS" <<'EOF'
import json,sys
d=json.load(open(sys.argv[1]))
bad=[h["command"] for e in d.get("hooks",{}).get("PreToolUse",[]) for h in e.get("hooks",[])
     if "lane-gate" in str(h.get("command","")) and "$HOME" not in h["command"]]
if bad: print("⚠ the lane-gate hook holds an absolute path:", bad, "— use $HOME so it survives a machine move.")
EOF

# ---------- test ----------
if [ -f "$DST/skills/hub/tests/lane-coord.test.sh" ] && [ -f "$DST/skills/hub/tests/lane-gate.test.sh" ]; then
  say "Running the test suites:"
  a=$(bash "$DST/skills/hub/tests/lane-coord.test.sh" 2>&1 | tail -1)
  b=$(bash "$DST/skills/hub/tests/lane-gate.test.sh"  2>&1 | tail -1)
  say "  lane-coord: $a"; say "  lane-gate : $b"
  case "$a$b" in *failed=0*failed=0*) ;; *) fail "tests are not green — look before you use this";; esac
fi

say
say "Done. Open a hub:  claude -n hub-\$(basename \$(git rev-parse --show-toplevel))  then type /hub"
say "Read first:    $DST/skills/hub/DESIGN.md  (lifecycle, the six messages, the gates)"
say "New project:   add $DST/skills/hub/references/adapters/<repo>.md (template: EXAMPLE.md)"
[ "$warn" = 1 ] && say "There were version warnings above — read them before a real run."
exit 0
