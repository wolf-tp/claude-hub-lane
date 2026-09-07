#!/usr/bin/env bash
# lane-coord.test.sh — run: bash ~/.claude/skills/hub/tests/lane-coord.test.sh
set -u
S="$HOME/.claude/bin/lane-coord.sh"
T=$(mktemp -d); export HUB_COORD_DIR="$T/coord"
pass=0; fail=0
ok()   { pass=$((pass+1)); echo "  ok   $1"; }
bad()  { fail=$((fail+1)); echo "  FAIL $1"; echo "       got: $2"; }
expect() { # expect <desc> <expected-prefix> <expected-exit> <actual-output> <actual-exit>
  if [[ "$4" == "$2"* ]] && [ "$5" = "$3" ]; then ok "$1"; else bad "$1" "exit=$5 out=$4"; fi
}
run() { out=$("$@" 2>&1); rc=$?; }

echo "1 claim new task"
LANE_COORD_PID=$$ run bash "$S" lane claim lane-x-a plan#T1 feat/a "$T/wt-a"; expect "claim → CLAIMED" "CLAIMED" 0 "$out" "$rc"
[ -f "$HUB_COORD_DIR/tasks/plan#T1" ] && ok "task file exists" || bad "task file exists" "$(ls "$HUB_COORD_DIR/tasks")"

echo "2 same task, other lane, holder alive (pid 1)"
LANE_COORD_PID=1 run bash "$S" lane claim lane-x-b plan#T2 feat/b "$T/wt-b"; expect "seed by pid1" "CLAIMED" 0 "$out" "$rc"
LANE_COORD_PID=$$ run bash "$S" lane claim lane-x-c plan#T2 feat/c "$T/wt-c"; expect "duplicate → BUSY exit 1" "BUSY holder=lane-x-b pid=1 (alive)" 1 "$out" "$rc"

echo "3 holder dead → takeover"
LANE_COORD_PID=999999 run bash "$S" lane claim lane-x-d plan#T3 feat/d "$T/wt-d"; expect "seed by dead pid" "CLAIMED" 0 "$out" "$rc"
LANE_COORD_PID=$$ run bash "$S" lane claim lane-x-e plan#T3 feat/e "$T/wt-e"; expect "dead holder → TOOK-OVER-ORPHAN" "TOOK-OVER-ORPHAN" 0 "$out" "$rc"
grep -q "^lane-x-e " "$HUB_COORD_DIR/tasks/plan#T3" && ok "task now held by lane-x-e" || bad "task now held by lane-x-e" "$(cat "$HUB_COORD_DIR/tasks/plan#T3")"

echo "4 re-claim by same pid"
LANE_COORD_PID=$$ run bash "$S" lane claim lane-x-a plan#T1 feat/a "$T/wt-a"; expect "same pid → CLAIMED (already" "CLAIMED (already" 0 "$out" "$rc"

echo "5 branch held by another live lane"
LANE_COORD_PID=1 run bash "$S" lane claim lane-x-f plan#T5 feat/shared "$T/wt-f"; expect "seed branch" "CLAIMED" 0 "$out" "$rc"
LANE_COORD_PID=$$ run bash "$S" lane claim lane-x-g plan#T6 feat/shared "$T/wt-g"; expect "same branch → BUSY branch=" "BUSY branch=feat/shared holder=lane-x-f (alive)" 1 "$out" "$rc"

echo "6 release"
LANE_COORD_PID=$$ run bash "$S" lane release lane-x-a; expect "release → RELEASED" "RELEASED lane=lane-x-a tasks=1" 0 "$out" "$rc"
[ ! -f "$HUB_COORD_DIR/tasks/plan#T1" ] && ok "task file removed" || bad "task file removed" "still there"
[ ! -f "$HUB_COORD_DIR/lanes/lane-x-a" ] && ok "lane file removed" || bad "lane file removed" "still there"

echo "7 hub register / busy / orphan / release"
LANE_COORD_PID=1 run bash "$S" hub register hub-x; expect "register → REGISTERED" "REGISTERED hub=hub-x" 0 "$out" "$rc"
LANE_COORD_PID=$$ run bash "$S" hub register hub-y; expect "second hub alive → BUSY exit 1" "BUSY hub=hub-x pid=1 (alive)" 1 "$out" "$rc"
printf '999999 0 hub-dead\n' > "$HUB_COORD_DIR/HUB"
LANE_COORD_PID=$$ run bash "$S" hub register hub-z; expect "dead hub → TOOK-OVER-ORPHAN" "TOOK-OVER-ORPHAN" 0 "$out" "$rc"
LANE_COORD_PID=$$ run bash "$S" hub release; expect "hub release → RELEASED" "RELEASED" 0 "$out" "$rc"

echo "8 status prints board"
LANE_COORD_PID=$$ run bash "$S" status; [ "$rc" = 0 ] && echo "$out" | grep -q "lane-x-e" && echo "$out" | grep -q "plan#T3" && ok "status lists lane-x-e / plan#T3" || bad "status board" "$out"

echo "9 fail-open when dir cannot be created"
HUB_COORD_DIR=/dev/null/nope run bash "$S" status; expect "unwritable dir → WARN exit 0" "WARN" 0 "$out" "$rc"

echo "10 task key with slash"
LANE_COORD_PID=$$ run bash "$S" lane claim lane-x-h "2026-09-05-plan/T7" feat/h "$T/wt-h"; expect "slash task id" "CLAIMED" 0 "$out" "$rc"
[ -f "$HUB_COORD_DIR/tasks/2026-09-05-plan__T7" ] && ok "slash mapped to __" || bad "slash mapped to __" "$(ls "$HUB_COORD_DIR/tasks")"

echo "11 repo slug from a linked worktree = main repo basename"
R="$T/mainrepo"; git init -q -b main "$R"; git -C "$R" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
git -C "$R" worktree add -q "$T/wt-x" -b wt-x >/dev/null 2>&1
out=$(cd "$T/wt-x" && HUB_REPO= bash "$S" repo); [ "$out" = "mainrepo" ] && ok "worktree → mainrepo" || bad "worktree → mainrepo" "$out"
out=$(cd "$R" && HUB_REPO= bash "$S" repo); [ "$out" = "mainrepo" ] && ok "main tree → mainrepo" || bad "main tree → mainrepo" "$out"
out=$(cd "$R" && HUB_REPO=override bash "$S" repo); [ "$out" = "override" ] && ok "HUB_REPO override wins" || bad "HUB_REPO override wins" "$out"

echo "12 freeze / unfreeze"
LANE_COORD_PID=$$ run bash "$S" lane freeze lane-x-nope; expect "freeze unclaimed → not-claimed exit 1" "not-claimed" 1 "$out" "$rc"
LANE_COORD_PID=$$ run bash "$S" lane claim lane-x-fz plan#T12 feat/fz "$T/wt-fz"; expect "claim for freeze" "CLAIMED" 0 "$out" "$rc"
LANE_COORD_PID=$$ run bash "$S" lane freeze lane-x-fz; expect "freeze → FROZEN" "FROZEN lane=lane-x-fz" 0 "$out" "$rc"
[ -f "$HUB_COORD_DIR/lanes/lane-x-fz.frozen" ] && ok "frozen marker exists" || bad "frozen marker exists" "missing"
LANE_COORD_PID=$$ run bash "$S" status; echo "$out" | grep -q "lane-x-fz .*alive,FROZEN" && ok "status shows FROZEN" || bad "status shows FROZEN" "$out"
LANE_COORD_PID=$$ run bash "$S" lane claim lane-x-fz2 plan#T13 feat/other "$T/wt-fz2"; expect "claim unaffected by marker files" "CLAIMED" 0 "$out" "$rc"
LANE_COORD_PID=$$ run bash "$S" lane unfreeze lane-x-fz; expect "unfreeze → UNFROZEN" "UNFROZEN" 0 "$out" "$rc"
[ ! -f "$HUB_COORD_DIR/lanes/lane-x-fz.frozen" ] && ok "frozen marker removed" || bad "frozen marker removed" "still there"
LANE_COORD_PID=$$ run bash "$S" lane freeze lane-x-fz >/dev/null; LANE_COORD_PID=$$ run bash "$S" lane release lane-x-fz; expect "release clears marker too" "RELEASED lane=lane-x-fz" 0 "$out" "$rc"
[ ! -f "$HUB_COORD_DIR/lanes/lane-x-fz.frozen" ] && ok "release removed frozen marker" || bad "release removed frozen marker" "still there"

rm -rf "$T"
echo; echo "passed=$pass failed=$fail"; [ "$fail" = 0 ]
