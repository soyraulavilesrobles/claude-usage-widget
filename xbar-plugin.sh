#!/bin/bash
# Claude Code Usage · xbar plugin
# Refresh: 2 minutes

python3 - <<'PYEOF'
import json, sys, urllib.request
from datetime import datetime, timezone
from pathlib import Path

config_path = Path.home() / "claude-usage" / "config.json"
if not config_path.exists():
    print("🤖 Claude · no config")
    sys.exit(0)

config = json.loads(config_path.read_text())
url = (f"https://gist.githubusercontent.com"
       f"/{config['github_user']}/{config['gist_id']}/raw/claude-usage.json")

try:
    req = urllib.request.Request(url, headers={
        "Cache-Control": "no-cache", "User-Agent": "xbar-claude/1.0"
    })
    with urllib.request.urlopen(req, timeout=8) as r:
        d = json.loads(r.read())
except Exception as e:
    print(f"🤖 ⚠️  error")
    print("---")
    print(str(e))
    sys.exit(0)

ua   = datetime.fromisoformat(d["updated_at"])
mins = int((datetime.now(timezone.utc) - ua).total_seconds() // 60)
t    = f"{mins}m" if mins < 60 else f"{mins//60}h{mins%60:02d}m"

pct    = d.get("usage_pct", 0)
cost   = d.get("estimated_cost_usd", 0)
lim    = d.get("limit_usd", 13.0)
source = "✓" if d.get("source") == "official" else "~"

# Progress bar (20 chars)
filled = int(pct / 100 * 20)
bar    = "█" * filled + "░" * (20 - filled)

# Color based on percentage
if pct >= 90:
    color = "#ef4444"  # red
elif pct >= 70:
    color = "#f59e0b"  # amber
else:
    color = "#22c55e"  # green

# ── menu bar ──────────────────────────────────────────────────
print(f"🤖 {pct:.0f}% | color={color} size=13")
print("---")

# ── dropdown ──────────────────────────────────────────────────
print(f"Claude Code · ventana 5h | size=13 color=#a78bfa")
print("---")
print(f"{bar}  {pct:.1f}% | font=Menlo size=11 color={color}")
print(f"${cost:.4f} / ${lim:.2f} USD")
print("---")
if d.get("source") == "official":
    print("Tokens: datos oficiales sin desglose")
else:
    print(f"Input:        {d['input_tokens']:>12,} tok")
    print(f"Output:       {d['output_tokens']:>12,} tok")
    print(f"Cache read:   {d['cache_read_input_tokens']:>12,} tok")
    print(f"Cache write:  {d['cache_creation_input_tokens']:>12,} tok")
print("---")
pct_7d = d.get("usage_pct_7d")
resets_str = ""
resets_raw = d.get("resets_at", "")
if resets_raw:
    try:
        from datetime import timedelta
        rt = datetime.fromisoformat(resets_raw).astimezone()
        now_local = datetime.now().astimezone()
        # Advance by 5h intervals until we find the next future reset
        while rt <= now_local:
            rt += timedelta(hours=5)
        diff = rt - now_local
        total_mins = int(diff.total_seconds() // 60)
        hrs, mins = divmod(total_mins, 60)
        countdown = f"{hrs}h{mins:02d}m" if hrs else f"{mins}m"
        resets_str = f"↺ en {countdown}  ({rt.strftime('%H:%M')})"
    except:
        resets_str = ""

print(f"Actualizado hace {t}  {source}")
if resets_str: print(resets_str)
if pct_7d is not None: print(f"Semana (7d): {pct_7d}%")
PYEOF
