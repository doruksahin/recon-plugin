#!/bin/bash
# render-state-canvas.sh <TICKET-ID> — fills the recon-state canvas template
# MECHANICALLY from state/state.yaml (+ history.ndjson for the timeline) and
# writes state/canvas.html. The model authors nothing: node classes, status
# words, the next-action chip, and every fact slot come from the derived state;
# an unresolved «MARKER» in the output is a render failure (exit 1).
# Reading history.ndjson here is VIEW rendering, not evidence (invariant 16).
# Exit 0 rendered, 1 unrenderable, 2 missing inputs.
# RECON_ROOT overrides the workspace root (fixture tests).
set -euo pipefail

TICKET="${1:?usage: render-state-canvas.sh <TICKET-ID>}"
case "$TICKET" in
  *[!A-Za-z0-9-]* | "") echo "invalid ticket id: $TICKET" >&2; exit 2 ;;
esac

DIR="${RECON_ROOT:-$HOME/.claude/recon}/$TICKET"
STATE="$DIR/state/state.yaml"
[ -f "$STATE" ] || { echo "no $STATE — run derive-state.sh first" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required (ships with macOS CLT)" >&2; exit 2; }

TPL="$(cd "$(dirname "$0")" && pwd)/../skills/recon-state/template.html"
[ -f "$TPL" ] || { echo "no template: $TPL — broken plugin install" >&2; exit 2; }

python3 - "$TPL" "$STATE" "$DIR/history.ndjson" "$DIR/state/canvas.html" <<'PY'
import html, json, re, sys
from datetime import datetime, timezone

tpl_path, state_path, ledger_path, out_path = sys.argv[1:5]

state = {}
for line in open(state_path, encoding="utf-8"):
    key, _, val = line.rstrip("\n").partition(": ")
    if key and val is not None:
        state[key.strip()] = val.strip().strip('"')

stop = state.get("stop", "")
nodes = {k.split(".", 1)[1]: v for k, v in state.items() if k.startswith("node.")}
facts = {k.split(".", 1)[1]: v for k, v in state.items() if k.startswith("fact.")}

CLS = {"done": "done", "current": "now", "queued": "queued",
       "not-taken": "ghost queued", "absent": "ghost queued",
       "declined": "done"}
STS_BASE = {"done": "done", "current": "in progress", "queued": "queued",
            "not-taken": "not taken", "absent": "on-demand",
            "declined": "declined"}
STS_OVERRIDE = {  # per-node wording, data-driven suffixes
    ("triage", "done"): "done · <em>%s</em>" % html.escape(facts.get("disposition", "")),
    ("repro", "done"): "done · %s exhibits" % html.escape(facts.get("exhibits", "0")),
    ("repro", "absent"): "not triggered",
    ("routing", "done"): "done · %s" % html.escape(facts.get("route", "")),
    ("approval_gate", "current"): "waiting on you",
    ("blocked_path", "current"): "waiting on you",
    ("blocked_path", "done"): "done · awaiting replies",
    ("blocked_path", "declined"): "drafted · you declined posting",
    ("implement", "queued"): "queued · beyond recon",
    ("implement", "current"): "your move · beyond recon",
    ("dossier", "done"): "rendered",
}

CHIP_LABEL = {  # stop -> (anchor node, chip text)
    "triage-in-progress": ("triage", "six checks running"),
    "comment-gate": ("blocked_path", "approve comment + attachments"),
    "post-declined": ("blocked_path", "raise the blockers yourself"),
    "awaiting-replies": ("blocked_path", "waiting for ticket replies"),
    "discovery-in-progress": (None, "discovery running"),  # anchor = current node
    "approval-gate": ("approval_gate", "answer the gate"),
    "rejected": ("approval_gate", "fix + re-run discovery"),
    "handed-off": ("implement", "implement via handoff"),
}

anchor, chip_text = CHIP_LABEL.get(stop, (None, ""))
if anchor is None and chip_text:
    anchor = next((n for n, s in nodes.items() if s == "current"), None)

out = open(tpl_path, encoding="utf-8").read()
out = re.sub(r"^<!--.*?-->\n", "", out, count=1, flags=re.S)  # strip template header comment

def put(marker, value):
    global out
    out = out.replace("«%s»" % marker, value)

for node, status in nodes.items():
    put("CLS:%s" % node, CLS.get(status, "queued"))
    sts = STS_OVERRIDE.get((node, status), STS_BASE.get(status, status))
    put("STS:%s" % node, sts)
    chip = ""
    if node == anchor and chip_text:
        chip = '\n      <button class="chip" data-pop="p-next">%s</button>' % html.escape(chip_text)
    put("CHIP:%s" % node, chip)

for k, v in facts.items():
    out = out.replace("«FACT:%s»" % k, html.escape(v))

def short_ts(iso):
    try:
        dt = datetime.strptime(iso, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
        return dt.strftime("%d %b %H:%M")
    except ValueError:
        return html.escape(iso)

EVENT_LABEL = {
    "run_started": lambda r: "run started (v%s)" % r.get("v", "?"),
    "verdict": lambda r: "verdict %s (%s blocker%s)" % (r.get("disposition", "?"), r.get("blockers", "?"),
                                                        "" if r.get("blockers") == "1" else "s"),
    "routed": lambda r: "routed → %s (rule %s)" % (r.get("route", "?"), r.get("rule", "?")),
    "comment_posted": lambda r: "Jira comment %s" % r.get("action", "posted"),
    "post_declined": lambda r: "posting declined at the gate",
    "attachments_replaced": lambda r: "%s attachment(s) replaced" % r.get("count", "?"),
    "gate_answered": lambda r: "gate answered — approved: %s" % r.get("approved", "?"),
    "handoff_printed": lambda r: "handoff printed",
    "dossier_published": lambda r: "dossier published",
    "canvas_published": lambda r: "state canvas republished",
}

items = []
try:
    for line in open(ledger_path, encoding="utf-8"):
        if not line.strip():
            continue
        row = json.loads(line)
        label = EVENT_LABEL.get(row.get("event"), lambda r: r.get("event", "?"))(row)
        items.append('<li class="tl"><span class="ts">%s</span> %s</li>'
                     % (short_ts(row.get("ts", "?")), html.escape(label)))
except FileNotFoundError:
    items.append('<li class="tl"><span class="ts">—</span> no ledger yet — '
                 "events are recorded from the next run onward</li>")
put("TIMELINE", "\n".join(items))

put("TICKET", html.escape(state.get("ticket", "?")))
put("TITLE", html.escape(facts.get("title", "")))
put("NEXT", html.escape(state.get("next", "")))
put("STOP", html.escape(stop))
put("TS", html.escape(state.get("derived", "")))
put("RUN_STARTED", html.escape(state.get("run_started", "")))
put("RUN_VERSION", html.escape(state.get("run_version", "")))
put("META", html.escape(" · ".join(x for x in [
    facts.get("task_class", ""), facts.get("disposition", ""), facts.get("route", ""),
    "run v" + state.get("run_version", "?"), "derived " + state.get("derived", "?")] if x)))

leftover = sorted(set(re.findall(r"«[A-Z_]+(?::[a-z_]+)?»", out)))
if leftover:
    sys.stderr.write("render: unresolved markers: %s\n" % " ".join(leftover))
    sys.exit(1)

open(out_path, "w", encoding="utf-8").write(out)
PY

echo "rendered: $DIR/state/canvas.html"
