#!/usr/bin/env bash
# lane-coord.sh — cross-session lock registry for the `hub` / `lane` skills.
# One repo = one SSOT dir: ~/.claude/hub/<repo>/ { HUB, lanes/<lane>, tasks/<task-key> }
#   hub register <name> | hub release | lane claim <lane> <task> [branch] [wt] | lane release|freeze|unfreeze <lane> | status | whoami | repo
# Identity = PID of the owning `claude` session (myclaude(), same walk as pw-coord.sh).
# Fail-open: cannot create the dir → print WARN, exit 0 (never block a session).
set -u
repo_slug() {   # main-repo basename even from a linked worktree (../<repo>-wt/<slug>, .claude/worktrees/<slug>)
  [ -n "${HUB_REPO:-}" ] && { echo "$HUB_REPO"; return; }
  local common; common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || { echo "no-repo"; return; }
  basename "$(dirname "$common")"
}
CO="${HUB_COORD_DIR:-$HOME/.claude/hub/$(repo_slug)}"; LANES="$CO/lanes"; TASKS="$CO/tasks"; HUBF="$CO/HUB"
if ! mkdir -p "$LANES" "$TASKS" 2>/dev/null; then echo "WARN lane-coord: cannot create $CO — running unguarded"; exit 0; fi

# Walk up from this shell to the owning claude session PID (case-sensitive match
# on the COMMAND, so a wrapper exporting CLAUDE_* is not mistaken for the binary).
myclaude() {
  local pid=$$ cmd ppid
  for _ in $(seq 1 20); do
    cmd=$(ps -o command= -p "$pid" 2>/dev/null)
    if printf '%s' "$cmd" | grep -qE '(^|/)claude( |$|--)'; then echo "$pid"; return; fi
    ppid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
    { [ -z "$ppid" ] || [ "$ppid" -le 1 ]; } && break
    pid=$ppid
  done
  echo "sh-$$"
}
alive() { [ -n "$1" ] && ps -p "$1" >/dev/null 2>&1; }
task_key() { printf '%s' "$1" | sed 's#/#__#g'; }   # only "/" → "__"
ME=${LANE_COORD_PID:-$(myclaude)}; NOW=$(date +%s)

lane_claim() {
  local lane="$1" task="$2" branch="${3:--}" wt="${4:--}" key f holder hpid hbranch other
  [ -n "$branch" ] || branch="-"; [ -n "$wt" ] || wt="-"
  key=$(task_key "$task"); f="$TASKS/$key"
  # branch held by another live lane?
  for other in "$LANES"/*; do
    [ -f "$other" ] || continue; case "$other" in *.frozen) continue;; esac
    read -r hpid _ _ hbranch _ < "$other"
    if [ "$branch" != "-" ] && [ "$hbranch" = "$branch" ] && [ "$(basename "$other")" != "$lane" ] && alive "$hpid"; then
      echo "BUSY branch=$branch holder=$(basename "$other") (alive) — pick another branch or ASK hub"; return 1
    fi
  done
  if ( set -o noclobber; printf '%s %s %s %s %s\n' "$lane" "$ME" "$NOW" "$branch" "$wt" >"$f" ) 2>/dev/null; then
    printf '%s %s %s %s %s\n' "$ME" "$NOW" "$task" "$branch" "$wt" >"$LANES/$lane"; echo "CLAIMED task=$task lane=$lane"; return 0
  fi
  read -r holder hpid _ < "$f"
  if [ "$hpid" = "$ME" ]; then echo "CLAIMED (already held by $holder pid=$hpid)"; return 0; fi
  if alive "$hpid"; then echo "BUSY holder=$holder pid=$hpid (alive) — do not start; ASK hub"; return 1; fi
  printf '%s %s %s %s %s\n' "$lane" "$ME" "$NOW" "$branch" "$wt" >"$f"
  printf '%s %s %s %s %s\n' "$ME" "$NOW" "$task" "$branch" "$wt" >"$LANES/$lane"
  echo "TOOK-OVER-ORPHAN task=$task (dead holder=$holder pid=$hpid) — read its worktree/ledger before continuing"; return 0
}
lane_release() {
  local lane="$1" n=0 f holder hpid
  for f in "$TASKS"/*; do
    [ -f "$f" ] || continue; read -r holder hpid _ < "$f"
    if [ "$holder" = "$lane" ] && { [ "$hpid" = "$ME" ] || ! alive "$hpid"; }; then rm -f "$f"; n=$((n+1)); fi
  done
  rm -f "$LANES/$lane" "$LANES/$lane.frozen"; echo "RELEASED lane=$lane tasks=$n"
}
lane_freeze()   { [ -f "$LANES/$1" ] || { echo "not-claimed lane=$1 — claim first"; return 1; }; : >"$LANES/$1.frozen"; echo "FROZEN lane=$1 — no edits/commits until ACK/FIX (lane-gate enforces)"; }
lane_unfreeze() { rm -f "$LANES/$1.frozen"; echo "UNFROZEN lane=$1"; }
hub_register() {
  local name="$1" hpid hname
  if [ -f "$HUBF" ]; then
    read -r hpid _ hname < "$HUBF"
    if [ "$hpid" = "$ME" ]; then printf '%s %s %s\n' "$ME" "$NOW" "$name" >"$HUBF"; echo "REGISTERED hub=$name (renewed)"; return 0; fi
    if alive "$hpid"; then echo "BUSY hub=$hname pid=$hpid (alive) — one hub per repo; message it or wait"; return 1; fi
    printf '%s %s %s\n' "$ME" "$NOW" "$name" >"$HUBF"; echo "TOOK-OVER-ORPHAN hub (dead=$hname pid=$hpid) now hub=$name"; return 0
  fi
  printf '%s %s %s\n' "$ME" "$NOW" "$name" >"$HUBF"; echo "REGISTERED hub=$name"
}
hub_release() {
  local hpid; [ -f "$HUBF" ] || { echo "not-hub (none)"; return 0; }
  read -r hpid _ _ < "$HUBF"
  if [ "$hpid" = "$ME" ]; then rm -f "$HUBF"; echo "RELEASED hub"; else echo "not-hub (current pid=$hpid)"; fi
}
status() {
  local hpid hname f pid ts task branch wt age st holder
  echo "repo=$(basename "$CO")  me=$ME"
  if [ -f "$HUBF" ]; then read -r hpid _ hname < "$HUBF"; alive "$hpid" && st=alive || st=DEAD; echo "HUB  $hname pid=$hpid $st"; else echo "HUB  none"; fi
  printf '%-28s %-8s %-6s %-32s %-28s %s\n' LANE PID STATE TASK BRANCH AGE
  for f in "$LANES"/*; do
    [ -f "$f" ] || continue; case "$f" in *.frozen) continue;; esac; read -r pid ts task branch wt < "$f"
    alive "$pid" && st=alive || st=DEAD; [ -f "$f.frozen" ] && st="$st,FROZEN"; age=$(( (NOW - ts) / 60 ))m
    printf '%-28s %-8s %-6s %-32s %-28s %s\n' "$(basename "$f")" "$pid" "$st" "$task" "$branch" "$age"
  done
  for f in "$TASKS"/*; do
    [ -f "$f" ] || continue; read -r holder pid _ < "$f"
    alive "$pid" || echo "ORPHAN task=$(basename "$f") holder=$holder pid=$pid (dead) — next claim takes over"
  done
}
case "${1:-status}" in
  hub)  case "${2:-}" in register) hub_register "${3:?hub name}";; release) hub_release;; *) echo "usage: hub register <name> | hub release"; exit 1;; esac;;
  lane) case "${2:-}" in claim) lane_claim "${3:?lane}" "${4:?task}" "${5:-}" "${6:-}";; release) lane_release "${3:?lane}";; freeze) lane_freeze "${3:?lane}";; unfreeze) lane_unfreeze "${3:?lane}";; *) echo "usage: lane claim <lane> <task> [branch] [wt] | lane release <lane> | lane freeze <lane> | lane unfreeze <lane>"; exit 1;; esac;;
  status) status;;
  whoami) echo "$ME";;
  repo)   repo_slug;;
  *) echo "usage: lane-coord.sh {hub register <name>|hub release|lane claim <lane> <task> [branch] [wt]|lane release <lane>|status|whoami|repo}"; exit 1;;
esac
