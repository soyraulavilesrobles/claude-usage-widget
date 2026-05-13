#!/usr/bin/env python3
"""
Receives official rate-limit data from Claude Code via stdin,
caches it for sync.py, and outputs a status line for Claude Code.
"""
import json
import os
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path

CACHE_DIR  = Path.home() / ".cache" / "claude-usage"
CACHE_FILE = CACHE_DIR / "rate_limits.json"


def atomic_write(path: Path, text: str):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix=f".{path.name}.", dir=str(path.parent))
    try:
        with os.fdopen(fd, "w") as f:
            f.write(text)
        os.replace(tmp, path)
    except Exception:
        try: os.unlink(tmp)
        except: pass


def main():
    if sys.stdin.isatty():
        print("", end="")
        return

    try:
        raw = sys.stdin.read()
        data = json.loads(raw)
    except (json.JSONDecodeError, OSError):
        print("", end="")
        return

    rl = data.get("rate_limits", {})
    fh = rl.get("five_hour", {})
    sd = rl.get("seven_day", {})

    if fh or sd:
        cache = {
            "received_at": datetime.now(timezone.utc).isoformat(),
            "five_hour": fh,
            "seven_day": sd,
            "cost": data.get("cost", {}),
            "session_id": data.get("session_id", ""),
        }
        atomic_write(CACHE_FILE, json.dumps(cache))

    # Format status line for Claude Code terminal
    pct_5h = fh.get("used_percentage", 0) if fh else None
    if pct_5h is None:
        print("", end="")
        return

    pct_5h = int(round(float(pct_5h)))
    cost = data.get("cost", {}).get("total_cost_usd", 0)

    # Color via ANSI (Claude Code status bar supports it)
    if pct_5h >= 90:
        bar_color = "\033[31m"  # red
    elif pct_5h >= 70:
        bar_color = "\033[33m"  # yellow
    else:
        bar_color = "\033[32m"  # green
    reset = "\033[0m"

    resets_at = fh.get("resets_at")
    reset_str = ""
    if resets_at:
        try:
            t = datetime.fromtimestamp(float(resets_at), tz=timezone.utc)
            local = t.astimezone()
            reset_str = f" ↺{local.strftime('%H:%M')}"
        except Exception:
            pass

    print(f"🤖 {bar_color}{pct_5h}%{reset} ${cost:.2f}{reset_str}", end="")


if __name__ == "__main__":
    main()
