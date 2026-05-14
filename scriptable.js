// Claude Usage Widget · Scriptable
// Instala Scriptable desde App Store, crea un script nuevo y pega este código.

// ── CONFIGURA ESTO ───────────────────────────────────────────────────────────
const GITHUB_USER = "TU_USUARIO_GITHUB";
const GIST_ID     = "TU_GIST_ID";
// ────────────────────────────────────────────────────────────────────────────

const RAW_URL = `https://gist.githubusercontent.com/${GITHUB_USER}/${GIST_ID}/raw/claude-usage.json`;

let d;
try {
  const req = new Request(RAW_URL);
  req.headers = { "Cache-Control": "no-cache" };
  d = await req.loadJSON();
} catch (e) {
  const w = new ListWidget();
  w.backgroundColor = new Color("#1e1b2e");
  const txt = w.addText("🤖 Claude\n⚠️ Sin datos");
  txt.textColor = Color.white();
  txt.font = Font.systemFont(12);
  Script.setWidget(w);
  if (!config.runsInWidget) await w.presentSmall();
  Script.complete();
  return;
}

const pct      = d.usage_pct ?? 0;
const cost     = d.estimated_cost_usd ?? 0;
const limitUsd = d.limit_usd ?? 13.0;

const pctColor = pct >= 90 ? new Color("#ef4444")
               : pct >= 70 ? new Color("#f59e0b")
               :              new Color("#22c55e");

const updatedAt = new Date(d.updated_at);
const mins      = Math.floor((Date.now() - updatedAt) / 60000);
const timeStr   = mins < 60 ? `${mins}m` : `${Math.floor(mins/60)}h${(mins%60).toString().padStart(2,"0")}m`;

let resetStr = "";
if (d.resets_at) {
  // Advance by 5h intervals if resets_at is stale (API sometimes keeps old value)
  let resetsAt = new Date(d.resets_at);
  while (resetsAt <= new Date()) {
    resetsAt = new Date(resetsAt.getTime() + 5 * 60 * 60 * 1000);
  }
  const diffMs   = resetsAt - Date.now();
  const diffMins = Math.floor(diffMs / 60000);
  const rh = Math.floor(diffMins / 60);
  const rm = diffMins % 60;
  resetStr = rh > 0
    ? `↺ en ${rh}h${rm.toString().padStart(2,"0")}m`
    : `↺ en ${rm}m`;
}

// ── Widget ────────────────────────────────────────────────────────────────────
const w = new ListWidget();
w.backgroundColor = new Color("#1e1b2e");
w.setPadding(12, 14, 10, 14);

// Header
const hStack = w.addStack();
hStack.layoutHorizontally();
hStack.centerAlignContent();

const icon = hStack.addText("🤖");
icon.font = Font.systemFont(13);
hStack.addSpacer(4);
const title = hStack.addText("Claude Code");
title.font = Font.boldSystemFont(13);
title.textColor = new Color("#c4b5fd");
hStack.addSpacer();
const winLabel = hStack.addText("5h");
winLabel.font = Font.systemFont(11);
winLabel.textColor = new Color("#6b7280");

w.addSpacer(10);

// Percentage (big)
const pctTxt = w.addText(`${pct.toFixed(0)}%`);
pctTxt.font = Font.boldSystemFont(36);
pctTxt.textColor = pctColor;
pctTxt.minimumScaleFactor = 0.6;

const usedLabel = w.addText("usado en ventana 5h");
usedLabel.font = Font.systemFont(10);
usedLabel.textColor = new Color("#6b7280");

w.addSpacer(8);

// Progress bar
const barBg = w.addStack();
barBg.layoutHorizontally();
barBg.cornerRadius = 4;
barBg.backgroundColor = new Color("#374151");
barBg.size = new Size(0, 8);

const filledStack = barBg.addStack();
filledStack.backgroundColor = pctColor;
filledStack.cornerRadius = 4;
filledStack.size = new Size(0, 8);
const filledPct = Math.max(pct / 100, 0.02);
filledStack.addSpacer(filledPct * 120);
barBg.addSpacer((1 - filledPct) * 120);

w.addSpacer(6);

// Cost line
const costTxt = w.addText(`$${cost.toFixed(3)} / $${limitUsd.toFixed(2)} USD`);
costTxt.font = Font.mediumSystemFont(12);
costTxt.textColor = new Color("#9ca3af");

// Token breakdown (medium/large only, only when source is jsonl_estimate)
if (config.widgetFamily !== "small" && d.source !== "official") {
  w.addSpacer(6);
  const rows = [
    ["↓ in",       d.input_tokens],
    ["↑ out",      d.output_tokens],
    ["📦 cache r.", d.cache_read_input_tokens],
  ];
  for (const [label, val] of rows) {
    const row = w.addStack();
    row.layoutHorizontally();
    const lbl = row.addText(label);
    lbl.font = Font.systemFont(10);
    lbl.textColor = new Color("#6b7280");
    row.addSpacer();
    const num = row.addText((val ?? 0).toLocaleString());
    num.font = Font.systemFont(10);
    num.textColor = new Color("#6b7280");
  }
}

if (resetStr) {
  w.addSpacer(4);
  const resetTxt = w.addText(resetStr);
  resetTxt.font = Font.systemFont(11);
  resetTxt.textColor = new Color("#a78bfa");
}

w.addSpacer();

const footer = w.addText(`act. hace ${timeStr}`);
footer.font = Font.systemFont(9);
footer.textColor = new Color("#4b5563");

// When run manually (tap), mark as expired so iOS redraws immediately.
// When run as widget, request refresh in 2 min.
w.refreshAfterDate = config.runsInWidget
  ? new Date(Date.now() + 2 * 60 * 1000)
  : new Date(Date.now() - 1000);
// Tap widget → opens Scriptable, re-runs this script with fresh data
w.url = "scriptable:///run/ClaudeUsage";

Script.setWidget(w);
if (!config.runsInWidget) await w.presentSmall();
Script.complete();
