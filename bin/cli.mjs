#!/usr/bin/env node
// claude-hub-lane — install the `hub` + `lane` skills into ~/.claude
//
//   npx claude-hub-lane            install or update
//   npx claude-hub-lane check      report only, write nothing
//   npx claude-hub-lane --force    also relax a stricter crossSessionInbound
//   npx claude-hub-lane uninstall  remove the files (settings keys are left; it tells you which)
//
// The installer itself is assets/skills/hub/install.sh — one implementation, so the npx path
// and the copy-the-folder path cannot drift. This file is a preflight + a thin wrapper.
import { spawnSync } from "node:child_process";
import { existsSync, rmSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { homedir, platform } from "node:os";

const PKG = join(dirname(fileURLToPath(import.meta.url)), "..");
const ASSETS = join(PKG, "assets");
const INSTALLER = join(ASSETS, "skills", "hub", "install.sh");
const HOME = homedir();

const argv = process.argv.slice(2);
const has = (...names) => argv.some((a) => names.includes(a));
const cmd = argv.find((a) => !a.startsWith("-")) ?? "install";

function die(msg, hint) {
  console.error(`\n  ✖ ${msg}`);
  if (hint) console.error(`    ${hint}`);
  console.error("");
  process.exit(1);
}

function have(bin) {
  return spawnSync("command", ["-v", bin], { shell: true, stdio: "ignore" }).status === 0;
}

if (has("-h", "--help", "help") || cmd === "help") {
  console.log(`
  claude-hub-lane — many Claude Code sessions working as one team

    npx claude-hub-lane              install or update into ~/.claude
    npx claude-hub-lane check        report what is installed, write nothing
    npx claude-hub-lane uninstall    remove the installed files
    npx claude-hub-lane --force      install, and relax a stricter crossSessionInbound

  After installing:  claude -n hub-<repo>   then type  /hub
  Docs: https://github.com/wolf-tp/claude-hub-lane
`);
  process.exit(0);
}

// ---- preflight -------------------------------------------------------------
if (platform() === "win32") {
  die(
    "Windows is not supported (the lock registry needs `ps` and the gate needs POSIX paths).",
    "Use WSL — it works there like any Linux box."
  );
}
if (!existsSync(INSTALLER)) die(`package looks incomplete: ${INSTALLER} is missing.`);
for (const [bin, why] of [
  ["bash", "the lock registry (lane-coord.sh) is a bash script"],
  ["python3", "the PreToolUse gate (lane-gate.py) is a python script"],
  ["git", "lanes work in git worktrees"],
]) {
  if (!have(bin)) die(`\`${bin}\` not found on PATH — ${why}.`);
}

// ---- uninstall -------------------------------------------------------------
if (cmd === "uninstall") {
  const targets = [
    "skills/hub", "skills/lane", "commands/hub.md", "commands/lane.md",
    "bin/lane-coord.sh", "bin/lane-gate.py",
  ].map((p) => join(HOME, ".claude", p));
  let removed = 0;
  for (const t of targets) {
    if (existsSync(t)) { rmSync(t, { recursive: true, force: true }); removed++; console.log(`  removed ${t.replace(HOME, "~")}`); }
  }
  console.log(`\n  ${removed} path(s) removed.`);
  console.log("  settings.json was NOT edited. To finish, remove by hand if you want them gone:");
  console.log('    • the "crossSessionInbound": "accept" key');
  console.log('    • the PreToolUse hook whose command mentions lane-gate.py');
  console.log("    (a timestamped backup from install time sits next to it: settings.json.hub-lane-bak-*)\n");
  process.exit(0);
}

// ---- install / check -------------------------------------------------------
const args = [INSTALLER];
if (cmd === "check" || has("--check")) args.push("--check");
if (has("--force")) args.push("--force");

const r = spawnSync("bash", args, {
  stdio: "inherit",
  env: { ...process.env, HUB_LANE_SRC: ASSETS },
});
process.exit(r.status ?? 1);
