#!/usr/bin/env bash
# install.sh — cài bộ skill `hub` + `lane` (điều phối nhiều Claude session) sang một máy.
#
#   bash install.sh            cài / cập nhật (idempotent, sao lưu settings trước khi sửa)
#   bash install.sh --check    chỉ báo cáo, KHÔNG ghi gì
#   bash install.sh --force    ghi đè cả khi settings đang đặt crossSessionInbound chặt hơn
#
# Nguồn mặc định = thư mục chứa file này. Chép sang máy khác: mang cả cây
# skills/hub + skills/lane + commands/{hub,lane}.md + bin/{lane-coord.sh,lane-gate.py},
# hoặc chỉ mang skills/hub rồi đặt HUB_LANE_SRC trỏ về một bản ~/.claude đầy đủ.
#
# Yêu cầu máy đích: Claude Code >= 2.1.224 (nhắn chéo session), python3, git, bash + ps.
set -u

MODE=install
for a in "$@"; do
  case "$a" in
    --check) MODE=check;;
    --force) MODE=force;;
    -h|--help) sed -n '2,14p' "$0"; exit 0;;
    *) echo "unknown flag: $a (dùng --check | --force)"; exit 2;;
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
fail() { printf 'LỖI: %s\n' "$*" >&2; exit 1; }

[ -d "$SRC/skills/hub" ] || fail "không thấy nguồn $SRC/skills/hub — đặt HUB_LANE_SRC trỏ tới thư mục .claude nguồn"
for f in skills/hub/SKILL.md skills/lane/SKILL.md commands/hub.md commands/lane.md bin/lane-coord.sh bin/lane-gate.py; do
  [ -f "$SRC/$f" ] || fail "thiếu file nguồn: $SRC/$f"
done

# ---------- phụ thuộc ----------
command -v python3 >/dev/null || fail "cần python3"
command -v git >/dev/null     || fail "cần git"
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
    old) say "⚠ Claude Code $ver < 2.1.224 — nhắn chéo giữa session chưa có; nâng cấp trước khi dùng hub/lane."; warn=1;;
    unknown) say "⚠ không đọc được phiên bản Claude Code ($ver) — cần >= 2.1.224.";;
  esac
else
  say "⚠ không thấy lệnh \`claude\` trên PATH — vẫn cài file, nhưng kiểm lại phiên bản >= 2.1.224."; warn=1
fi

# ---------- báo cáo trạng thái ----------
report() {
  local missing=0 f
  for f in skills/hub/SKILL.md skills/lane/SKILL.md commands/hub.md commands/lane.md bin/lane-coord.sh bin/lane-gate.py; do
    if [ -f "$DST/$f" ]; then say "  có     $f"; else say "  THIẾU  $f"; missing=1; fi
  done
  if [ -f "$SETTINGS" ]; then
    python3 - "$SETTINGS" <<'EOF'
import json,sys
try: d=json.load(open(sys.argv[1]))
except Exception as e: print("  settings.json ĐỌC KHÔNG ĐƯỢC:",e); sys.exit(0)
print("  crossSessionInbound =",d.get("crossSessionInbound") or "(chưa đặt — tin giữa hai lớp permission sẽ bị giữ)")
n=sum(1 for e in d.get("hooks",{}).get("PreToolUse",[]) for h in e.get("hooks",[]) if "lane-gate" in str(h.get("command","")))
print("  hook lane-gate      =", f"{n} mục" if n else "CHƯA CẮM")
EOF
  else
    say "  settings.json       = chưa có"; missing=1
  fi
  return $missing
}

if [ "$MODE" = check ]; then
  say "Kiểm tra cài đặt hub/lane tại $DST"
  if report; then say; say "Đã cài đủ."; exit 0; else say; say "Chưa cài đủ (missing/not installed) — chạy lại không kèm --check để cài."; exit 1; fi
fi

# ---------- chép file ----------
mkdir -p "$DST/skills/hub/references/adapters" "$DST/skills/hub/tests" "$DST/skills/lane" "$DST/commands" "$DST/bin" || fail "không tạo được thư mục dưới $DST"
copy() { # copy <đường dẫn tương đối>
  [ -f "$SRC/$1" ] || return 0
  mkdir -p "$(dirname "$DST/$1")"
  cp "$SRC/$1" "$DST/$1" || fail "chép hỏng: $1"
}
for f in \
  skills/hub/SKILL.md skills/hub/DESIGN.md skills/hub/install.sh \
  skills/hub/references/messages.md skills/hub/references/handoff-template.md \
  skills/hub/references/adapters/EXAMPLE.md \
  skills/hub/tests/lane-coord.test.sh skills/hub/tests/lane-gate.test.sh skills/hub/tests/install.test.sh \
  skills/lane/SKILL.md commands/hub.md commands/lane.md bin/lane-coord.sh bin/lane-gate.py
do copy "$f"; done
chmod +x "$DST/bin/lane-coord.sh" "$DST/bin/lane-gate.py" "$DST/skills/hub/install.sh" 2>/dev/null || true
# Bằng chứng nghiệm thu của máy nguồn KHÔNG đi theo (acceptance-*.md + thư mục bằng chứng).

# ---------- settings: sao lưu rồi merge hai khoá ----------
[ -f "$SETTINGS" ] || printf '{}\n' > "$SETTINGS"
python3 - "$SETTINGS" "$GATE_CMD" "$MATCHER" "$MODE" <<'EOF'
import json, sys, collections, datetime, shutil, os
path, gate_cmd, matcher, mode = sys.argv[1:5]
try:
    with open(path) as f: raw = f.read()
    d = json.loads(raw or "{}", object_pairs_hook=collections.OrderedDict)
    if not isinstance(d, dict): raise ValueError("settings.json không phải một object JSON")
except Exception as e:
    print(f"LỖI: settings.json hỏng ({e}) — KHÔNG sửa gì. Sửa tay rồi chạy lại.", file=sys.stderr)
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
    print(f"⚠ giữ nguyên crossSessionInbound={cur!r} (chặt hơn 'accept'): tin giữa các session của bạn sẽ bị hold/refuse.")
    print("  Muốn hub↔lane nhắn được: chạy lại với --force, hoặc tự đổi khoá này thành \"accept\".")

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
print("  sao lưu settings →", os.path.basename(bak))
print("  settings:", ", ".join(changed) if changed else "đã đúng, không đổi gì")
EOF
rc=$?; [ $rc = 0 ] || exit $rc

# ---------- V8: đo lại, đừng tin thao tác ----------
say "Kiểm lại sau khi ghi:"
report || true
python3 - "$SETTINGS" <<'EOF'
import json,sys
d=json.load(open(sys.argv[1]))
bad=[h["command"] for e in d.get("hooks",{}).get("PreToolUse",[]) for h in e.get("hooks",[])
     if "lane-gate" in str(h.get("command","")) and "$HOME" not in h["command"]]
if bad: print("⚠ hook lane-gate đang ghi đường dẫn tuyệt đối:", bad, "— sửa thành $HOME để chuyển máy được.")
EOF

# ---------- test ----------
if [ -f "$DST/skills/hub/tests/lane-coord.test.sh" ] && [ -f "$DST/skills/hub/tests/lane-gate.test.sh" ]; then
  say "Chạy test:"
  a=$(bash "$DST/skills/hub/tests/lane-coord.test.sh" 2>&1 | tail -1)
  b=$(bash "$DST/skills/hub/tests/lane-gate.test.sh"  2>&1 | tail -1)
  say "  lane-coord: $a"; say "  lane-gate : $b"
  case "$a$b" in *failed=0*failed=0*) ;; *) fail "test không xanh — xem lại trước khi dùng";; esac
fi

say
say "Done. Open a hub:  claude -n hub-\$(basename \$(git rev-parse --show-toplevel))  then type /hub"
say "Read first:    $DST/skills/hub/DESIGN.md  (lifecycle, the six messages, the gates)"
say "New project:   add $DST/skills/hub/references/adapters/<repo>.md (template: EXAMPLE.md)"
[ "$warn" = 1 ] && say "There were version warnings above — read them before a real run."
exit 0
