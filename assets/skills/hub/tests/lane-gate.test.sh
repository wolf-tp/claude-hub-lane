#!/usr/bin/env bash
# lane-gate.test.sh — run: bash ~/.claude/skills/hub/tests/lane-gate.test.sh
set -u
G="${LANE_GATE_BIN:-$(cd "$(dirname "$0")/../../../bin" && pwd)/lane-gate.py}"; T=$(mktemp -d); export HUB_COORD_DIR="$T/coord" HUB_REPO=testrepo; mkdir -p "$HUB_COORD_DIR/lanes"
pass=0; fail=0; ok(){ pass=$((pass+1)); echo "  ok   $1"; }; bad(){ fail=$((fail+1)); echo "  FAIL $1"; echo "       got: $2"; }
gate(){ # gate <name> <pid> <json>  → sets OUT RC
  OUT=$(printf '%s' "$3" | LANE_GATE_NAME="$1" LANE_GATE_PID="$2" python3 "$G" 2>&1); RC=$?; }
edit='{"tool_name":"Edit","tool_input":{"file_path":"/x/src/a.go"},"cwd":"/x"}'
editmd='{"tool_name":"Edit","tool_input":{"file_path":"/x/docs/a.md"},"cwd":"/x"}'
gitc='{"tool_name":"Bash","tool_input":{"command":"git commit -m x"},"cwd":"/x"}'
gits='{"tool_name":"Bash","tool_input":{"command":"git status && git diff"},"cwd":"/x"}'
expect_allow(){ [ "$RC" = 0 ] && [ -z "$OUT" ] && ok "$1" || bad "$1" "rc=$RC out=$OUT"; }
expect_deny(){ [ "$RC" = 0 ] && printf '%s' "$OUT" | grep -q '"permissionDecision": *"deny"' && printf '%s' "$OUT" | grep -q "$2" && ok "$1" || bad "$1" "rc=$RC out=$OUT"; }

echo "1 other session → untouched"; gate monorepo-67 1 "$edit"; expect_allow "plain session allowed"
echo "2 lane not claimed → G1 deny"; gate lane-testrepo-a 4242 "$edit"; expect_deny "unclaimed lane denied" "G1"
echo "3 lane claimed by same pid → allow"; printf '4242 0 t#1 feat/a /x\n' > "$HUB_COORD_DIR/lanes/lane-testrepo-a"; gate lane-testrepo-a 4242 "$edit"; expect_allow "claimed lane allowed"
echo "4 lane claimed by OTHER pid → G1 deny"; gate lane-testrepo-a 9999 "$edit"; expect_deny "claim held by other pid denied" "G1"
echo "5 frozen lane"; touch "$HUB_COORD_DIR/lanes/lane-testrepo-a.frozen"
gate lane-testrepo-a 4242 "$edit"; expect_deny "frozen: code edit denied" "G2"
gate lane-testrepo-a 4242 "$editmd"; expect_deny "frozen: repo .md (the slice itself) still denied" "G2"
gate lane-testrepo-a 4242 '{"tool_name":"Edit","tool_input":{"file_path":"/x/.superpowers/sdd/p/progress.md"},"cwd":"/x"}'; expect_allow "frozen: ledger append allowed"
gate lane-testrepo-a 4242 '{"tool_name":"Write","tool_input":{"file_path":"/x/docs/superpowers/handoff/2026-09-05-lane-x-handoff.md"},"cwd":"/x"}'; expect_allow "frozen: handoff write allowed"
gate lane-testrepo-a 4242 "$gitc"; expect_deny "frozen: git commit denied" "G2"
gate lane-testrepo-a 4242 "$gits"; expect_allow "frozen: git status allowed"
rm -f "$HUB_COORD_DIR/lanes/lane-testrepo-a.frozen"
echo "6 hub with active lane"; gate hub-testrepo 1 "$edit"; expect_deny "hub code edit denied while lane active" "Hub CẤM"
gate hub-testrepo 1 "$editmd"; expect_allow "hub docs edit allowed"
echo "7 hub without lanes"; rm -f "$HUB_COORD_DIR/lanes/lane-testrepo-a"; gate hub-testrepo 1 "$edit"; expect_allow "hub allowed when no lane"
echo "8 malformed input → allow"; OUT=$(printf 'not json' | LANE_GATE_NAME=lane-testrepo-a LANE_GATE_PID=1 python3 "$G" 2>&1); RC=$?; expect_allow "malformed json fail-open"
echo "9 outside any repo → allow"; OUT=$(printf '%s' '{"tool_name":"Edit","tool_input":{"file_path":"/tmp/zz.go"},"cwd":"/tmp"}' | HUB_REPO= LANE_GATE_NAME=lane-testrepo-a LANE_GATE_PID=4242 python3 "$G" 2>&1); RC=$?; expect_allow "no git repo → allow"
echo "10 timing"; s=$(python3 -c 'import time;print(time.time())'); gate monorepo-67 1 "$edit"; e=$(python3 -c 'import time;print(time.time())'); ms=$(python3 -c "print(int(($e-$s)*1000))"); [ "$ms" -lt 400 ] && ok "plain-session path ${ms}ms < 400ms" || bad "timing" "${ms}ms"
rm -rf "$T"; echo; echo "passed=$pass failed=$fail"; [ "$fail" = 0 ]
