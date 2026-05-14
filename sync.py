#!/usr/bin/env python3
"""Reads Claude Code usage (official stdin cache) and pushes to a GitHub Gist."""
import json
import urllib.request
from datetime import datetime, timezone, timedelta
from pathlib import Path

CONFIG_PATH    = Path.home() / "claude-usage" / "config.json"
CACHE_FILE     = Path.home() / ".cache" / "claude-usage" / "rate_limits.json"
CACHE_MAX_AGE  = timedelta(minutes=10)  # if older, fall back to JSONL estimate


def load_config():
    return json.loads(CONFIG_PATH.read_text())


def read_official_cache():
    """Read rate-limit data cached by statusline.py from Claude Code stdin."""
    if not CACHE_FILE.exists():
        return None
    try:
        d = json.loads(CACHE_FILE.read_text())
        received = datetime.fromisoformat(d["received_at"])
        now = datetime.now(timezone.utc)
        if now - received > CACHE_MAX_AGE:
            return None  # stale by age
        # Also invalidate if the 5h window already reset since data was cached
        resets_at_raw = d.get("five_hour", {}).get("resets_at")
        if resets_at_raw:
            resets_at = datetime.fromtimestamp(float(resets_at_raw), tz=timezone.utc)
            if resets_at <= now:
                return None  # window reset — data belongs to previous window
        return d
    except Exception:
        return None


def window_start_from_stale_cache():
    """Return the start of the current Anthropic window from cached resets_at.

    resets_at is the *end* of the current window (next reset). The window
    starts 5 hours before that. If resets_at is already in the past the
    window has reset; the new window started at that time.
    Returns None when the cache or timestamp is unavailable.
    """
    if not CACHE_FILE.exists():
        return None
    try:
        d = json.loads(CACHE_FILE.read_text())
        resets_at_raw = d.get("five_hour", {}).get("resets_at")
        if not resets_at_raw:
            return None
        resets_at = datetime.fromtimestamp(float(resets_at_raw), tz=timezone.utc)
        now = datetime.now(timezone.utc)
        if resets_at > now:
            # Window has NOT reset yet — it started 5h before resets_at
            return resets_at - timedelta(hours=5)
        else:
            # Window already reset — new window started at resets_at
            return resets_at
    except Exception:
        return None


# ── Fallback: estimate from JSONL if statusline cache is unavailable ──────────
PRICING = {
    "claude-opus-4-7":           (15.0, 75.0, 18.75, 1.50),
    "claude-opus-4-6":           (15.0, 75.0, 18.75, 1.50),
    "claude-sonnet-4-6":         ( 3.0, 15.0,  3.75, 0.30),
    "claude-haiku-4-5-20251001": ( 0.80, 4.0,  1.00, 0.08),
}
DEFAULT_PRICING = (3.0, 15.0, 3.75, 0.30)
PLAN_LIMITS = {"pro": 13.00, "max_5x": 65.00, "max_20x": 260.00}


def estimate_from_jsonl():
    rolling = datetime.now(timezone.utc) - timedelta(hours=5)
    window_start = window_start_from_stale_cache()
    # Use whichever is more recent: rolling 5h window or known window start
    cutoff = max(rolling, window_start) if window_start else rolling
    totals = dict(input_tokens=0, output_tokens=0,
                  cache_creation_input_tokens=0, cache_read_input_tokens=0)
    cost_usd = 0.0
    seen = set()

    for jsonl in (Path.home() / ".claude" / "projects").rglob("*.jsonl"):
        try:
            for line in jsonl.read_text(errors="ignore").splitlines():
                if not line:
                    continue
                try:
                    e = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if e.get("type") != "assistant" or e.get("isSidechain"):
                    continue
                ts = e.get("timestamp", "")
                try:
                    t = datetime.fromisoformat(ts.replace("Z", "+00:00"))
                except ValueError:
                    continue
                if t < cutoff:
                    continue
                rid = e.get("requestId", "")
                if not rid or rid in seen:
                    continue
                seen.add(rid)
                usage = e.get("message", {}).get("usage", {})
                if not any(usage.get(k, 0) for k in ["input_tokens", "output_tokens",
                                                       "cache_creation_input_tokens"]):
                    continue
                model = e.get("message", {}).get("model", "")
                pi, po, pcw, pcr = PRICING.get(model, DEFAULT_PRICING)
                inp = usage.get("input_tokens", 0)
                out = usage.get("output_tokens", 0)
                cw  = usage.get("cache_creation_input_tokens", 0)
                cr  = usage.get("cache_read_input_tokens", 0)
                totals["input_tokens"]                += inp
                totals["output_tokens"]               += out
                totals["cache_creation_input_tokens"] += cw
                totals["cache_read_input_tokens"]     += cr
                cost_usd += (inp*pi + out*po + cw*pcw + cr*pcr) / 1_000_000
        except (IOError, OSError):
            continue

    return totals, cost_usd


def update_gist(config, data):
    url = f"https://api.github.com/gists/{config['gist_id']}"
    payload = json.dumps({
        "files": {"claude-usage.json": {"content": json.dumps(data)}}
    }).encode()
    req = urllib.request.Request(url, data=payload, method="PATCH")
    req.add_header("Authorization", f"token {config['github_token']}")
    req.add_header("Content-Type", "application/json")
    req.add_header("User-Agent", "claude-usage-widget/1.0")
    with urllib.request.urlopen(req, timeout=15) as resp:
        return json.loads(resp.read())


def main():
    config = load_config()
    plan      = config.get("subscription_type", "pro")
    limit_usd = config.get("limit_usd") or PLAN_LIMITS.get(plan, PLAN_LIMITS["pro"])

    official = read_official_cache()

    if official:
        # ── Official data from Anthropic via Claude Code stdin ────────────────
        fh  = official.get("five_hour", {})
        sd  = official.get("seven_day", {})
        cost_obj = official.get("cost", {})

        pct_5h   = min(int(round(float(fh.get("used_percentage", 0)))), 100)
        pct_7d   = min(int(round(float(sd.get("used_percentage", 0)))), 100) if sd else None
        resets_at = fh.get("resets_at")

        reset_str = ""
        if resets_at:
            try:
                t = datetime.fromtimestamp(float(resets_at), tz=timezone.utc)
                reset_str = t.isoformat()
            except Exception:
                pass

        data = {
            "source": "official",
            "window_hours": 5,
            "updated_at": datetime.now(timezone.utc).isoformat(),
            "resets_at": reset_str,
            "usage_pct": pct_5h,
            "usage_pct_7d": pct_7d,
            "session_cost_usd": cost_obj.get("total_cost_usd", 0),
            "estimated_cost_usd": cost_obj.get("total_cost_usd", 0),
            "limit_usd": limit_usd,
            # token totals not available from official source
            "input_tokens": 0,
            "output_tokens": 0,
            "cache_creation_input_tokens": 0,
            "cache_read_input_tokens": 0,
            "total_tokens": 0,
        }
    else:
        # ── Fallback: estimate from local JSONL ───────────────────────────────
        totals, cost_usd = estimate_from_jsonl()
        pct = min(round(cost_usd / limit_usd * 100, 1), 100.0)

        # Derive estimated resets_at from cached window start + 5 h
        window_start = window_start_from_stale_cache()
        resets_at_str = ""
        if window_start:
            est_resets = window_start + timedelta(hours=5)
            if est_resets > datetime.now(timezone.utc):
                resets_at_str = est_resets.isoformat()

        data = {
            "source": "jsonl_estimate",
            "window_hours": 5,
            "updated_at": datetime.now(timezone.utc).isoformat(),
            "resets_at": resets_at_str,
            "usage_pct": pct,
            "usage_pct_7d": None,
            "session_cost_usd": round(cost_usd, 4),
            "estimated_cost_usd": round(cost_usd, 4),
            "limit_usd": limit_usd,
            "input_tokens": totals["input_tokens"],
            "output_tokens": totals["output_tokens"],
            "cache_creation_input_tokens": totals["cache_creation_input_tokens"],
            "cache_read_input_tokens": totals["cache_read_input_tokens"],
            "total_tokens": totals["input_tokens"] + totals["output_tokens"],
        }

    update_gist(config, data)
    print(json.dumps(data, indent=2))


if __name__ == "__main__":
    main()
