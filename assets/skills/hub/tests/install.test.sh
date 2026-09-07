#!/usr/bin/env bash
# install.test.sh — run: bash ~/.claude/skills/hub/tests/install.test.sh
# Tests the installer against a FAKE home (never touches the real ~/.claude).
set -u
SRC="${HUB_LANE_SRC:-$HOME/.claude}"; I="$SRC/skills/hub/install.sh"
pass=0; fail=0
ok(){ pass=$((pass+1)); echo "  ok   $1"; }
bad(){ fail=$((fail+1)); echo "  FAIL $1"; echo "       got: $2"; }
newhome(){ H=$(mktemp -d); mkdir -p "$H/.claude"; echo "$H"; }
run(){ out=$(HOME="$1" HUB_LANE_SRC="$SRC" bash "$I" "${@:2}" 2>&1); rc=$?; }
key(){ python3 -c "import json,sys;d=json.load(open('$1/.claude/settings.json'));print(d.get('crossSessionInbound'))"; }
hookcmd(){ python3 -c "
import json;d=json.load(open('$1/.claude/settings.json'))
print([h['command'] for e in d.get('hooks',{}).get('PreToolUse',[]) for h in e['hooks'] if 'lane-gate' in h['command']])"; }
hookcount(){ python3 -c "
import json;d=json.load(open('$1/.claude/settings.json'))
print(sum(1 for e in d.get('hooks',{}).get('PreToolUse',[]) for h in e['hooks'] if 'lane-gate' in h['command']))"; }

echo "1 fresh install (no settings.json yet)"
H=$(newhome); run "$H"
[ "$rc" = 0 ] && ok "exit 0" || bad "exit 0" "rc=$rc out=$out"
for f in skills/hub/SKILL.md skills/lane/SKILL.md commands/hub.md commands/lane.md bin/lane-coord.sh bin/lane-gate.py skills/hub/references/messages.md skills/hub/references/adapters/EXAMPLE.md; do
  [ -f "$H/.claude/$f" ] && ok "copied $f" || bad "copied $f" "missing"
done
[ -x "$H/.claude/bin/lane-coord.sh" ] && [ -x "$H/.claude/bin/lane-gate.py" ] && ok "scripts executable" || bad "scripts executable" "not +x"
[ "$(key "$H")" = accept ] && ok "crossSessionInbound=accept" || bad "crossSessionInbound=accept" "$(key "$H")"
hc=$(hookcmd "$H"); case "$hc" in *'$HOME/.claude/bin/lane-gate.py'*) ok "hook uses \$HOME, not a literal path";; *) bad "hook uses \$HOME, not a literal path" "$hc";; esac
case "$hc" in */Users/*) bad "hook must not hardcode /Users" "$hc";; *) ok "hook has no hardcoded /Users";; esac
[ ! -e "$H/.claude/skills/hub/tests/acceptance-2026-09-05" ] && ok "evidence dir not shipped" || bad "evidence dir not shipped" "present"
# scan shipped CONTENT only — not the test harness, whose own pattern string would self-match
leak=$(grep -rilE "finan|canonical\.|tenant_entity|gitlab" \
  "$H/.claude/skills/hub/SKILL.md" "$H/.claude/skills/hub/DESIGN.md" "$H/.claude/skills/hub/references" \
  "$H/.claude/skills/lane" "$H/.claude/commands" "$H/.claude/bin" 2>/dev/null | head -3)
[ -z "$leak" ] && ok "no employer-internal identifiers installed" || bad "no employer-internal identifiers installed" "$leak"

echo "2 idempotent (run twice)"
run "$H"; [ "$rc" = 0 ] && ok "second run exit 0" || bad "second run exit 0" "rc=$rc out=$out"
[ "$(hookcount "$H")" = 1 ] && ok "hook not duplicated" || bad "hook not duplicated" "count=$(hookcount "$H")"

echo "3 preserves existing settings"
H=$(newhome)
cat > "$H/.claude/settings.json" <<'EOF'
{
  "model": "opus",
  "env": {"MY_VAR": "keepme"},
  "permissions": {"allow": ["Bash(git *)"]},
  "hooks": {"PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command", "command": "echo mine"}]}],
            "Stop": [{"hooks": [{"type": "command", "command": "echo bye"}]}]}
}
EOF
run "$H"; [ "$rc" = 0 ] && ok "exit 0 with existing settings" || bad "exit 0 with existing settings" "rc=$rc out=$out"
python3 - "$H" <<'EOF'
import json,sys
d=json.load(open(sys.argv[1]+"/.claude/settings.json"))
checks={"model kept":d.get("model")=="opus","env kept":d.get("env",{}).get("MY_VAR")=="keepme",
 "permissions kept":d.get("permissions",{}).get("allow")==["Bash(git *)"],
 "Stop hook kept":any("bye" in h["command"] for e in d["hooks"].get("Stop",[]) for h in e["hooks"]),
 "existing PreToolUse kept":any("mine" in h["command"] for e in d["hooks"]["PreToolUse"] for h in e["hooks"]),
 "lane-gate added":any("lane-gate" in h["command"] for e in d["hooks"]["PreToolUse"] for h in e["hooks"])}
for k,v in checks.items(): print(("  ok   " if v else "  FAIL ")+k)
sys.exit(0 if all(checks.values()) else 1)
EOF
[ $? = 0 ] && pass=$((pass+6)) || fail=$((fail+1))
[ -f "$H/.claude/settings.json.hub-lane-bak-"*.json ] 2>/dev/null || ls "$H/.claude/"settings.json.hub-lane-bak-* >/dev/null 2>&1 && ok "backup written" || bad "backup written" "none"

echo "4 refuses a stricter existing crossSessionInbound without --force"
H=$(newhome); printf '{"crossSessionInbound":"refuse"}\n' > "$H/.claude/settings.json"
run "$H"; [ "$(key "$H")" = refuse ] && ok "did not silently loosen refuse" || bad "did not silently loosen refuse" "$(key "$H")"
printf '%s' "$out" | grep -qi "refuse" && ok "warned about it" || bad "warned about it" "$out"
run "$H" --force; [ "$(key "$H")" = accept ] && ok "--force overrides" || bad "--force overrides" "$(key "$H")"

echo "5 --check reports without writing"
H=$(newhome); run "$H" --check
[ ! -f "$H/.claude/settings.json" ] && [ ! -d "$H/.claude/skills/hub" ] && ok "--check wrote nothing" || bad "--check wrote nothing" "files appeared"
printf '%s' "$out" | grep -qiE "missing|not installed|chưa" && ok "--check says not installed" || bad "--check says not installed" "$out"

echo "6 broken settings.json → refuse, keep file"
H=$(newhome); printf '{ this is not json' > "$H/.claude/settings.json"
run "$H"; [ "$rc" != 0 ] && ok "exit non-zero on malformed settings" || bad "exit non-zero on malformed settings" "rc=$rc"
grep -q "this is not json" "$H/.claude/settings.json" && ok "malformed file untouched" || bad "malformed file untouched" "changed"

echo "7 installed gate + coord actually work in the fake home"
H=$(newhome); run "$H" >/dev/null
o=$(printf '%s' '{"tool_name":"Edit","tool_input":{"file_path":"/x/a.go"},"cwd":"/x"}' | HOME="$H" HUB_REPO=r LANE_GATE_NAME=lane-r-a LANE_GATE_PID=1 python3 "$H/.claude/bin/lane-gate.py")
printf '%s' "$o" | grep -q '"permissionDecision": *"deny"' && ok "installed lane-gate denies unclaimed lane" || bad "installed lane-gate denies unclaimed lane" "$o"
o=$(cd "$H" && HOME="$H" HUB_REPO=r HUB_COORD_DIR="$H/coord" bash "$H/.claude/bin/lane-coord.sh" hub register hub-r)
case "$o" in REGISTERED*) ok "installed lane-coord registers";; *) bad "installed lane-coord registers" "$o";; esac

echo; echo "passed=$pass failed=$fail"; [ "$fail" = 0 ]
