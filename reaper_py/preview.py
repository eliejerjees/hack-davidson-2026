def _fmt_time(seconds: float) -> str:
    if seconds < 1:
        return f"{int(round(seconds * 1000))}ms"
    return f"{seconds:.1f}s"

def _fmt_range(t: float) -> str:
    m = int(t // 60)
    s = t - 60 * m
    return f"{m:02d}:{s:06.3f}"

def build_preview(actions: list, target: str, ctx: dict) -> dict:
    bullets = []
    counts = (ctx or {}).get("counts") or {}
    items = counts.get("items")
    tracks = counts.get("tracks")

    for a in actions:
        op = a["op"]
        p = a.get("params", {})

        if op == "fade_in":
            bullets.append(f"Fade in by {_fmt_time(p['seconds'])}")
        elif op == "fade_out":
            bullets.append(f"Fade out by {_fmt_time(p['seconds'])}")
        elif op == "cut_middle":
            bullets.append(f"Cut middle {_fmt_time(p['seconds'])}")
        elif op == "trim_to_time_selection":
            bullets.append("Trim selected items to time selection")
        elif op == "split_at_cursor":
            bullets.append("Split at play cursor")
        elif op == "duplicate":
            bullets.append(f"Duplicate {p['count']} time(s)")
        elif op == "set_volume_delta":
            bullets.append(f"Change volume by {p['db']} dB")
        elif op == "set_pan":
            pan = p["pan"]
            side = "L" if pan < 0 else "R"
            bullets.append(f"Set pan to {abs(pan)}{side}")
        elif op in ("mute", "unmute", "solo", "unsolo"):
            bullets.append(op.capitalize())
        elif op == "add_fx":
            bullets.append(f"Add {p['type']} FX")
        else:
            bullets.append(f"{op}: {p}")

    # context bullets
    if target == "time_selection":
        ts = (ctx or {}).get("timeSelection")
        if ts and "start" in ts and "end" in ts:
            bullets.append(f"Range: {_fmt_range(ts['start'])} to {_fmt_range(ts['end'])}")
        else:
            bullets.append("Range: time selection")
    elif target == "selected_items":
        bullets.append(f"Applied to {items} item(s)" if isinstance(items, int) else "Applied to selected item(s)")
    elif target == "selected_tracks":
        bullets.append(f"Applied to {tracks} track(s)" if isinstance(tracks, int) else "Applied to selected track(s)")

    return {"title": "Will:", "bullets": bullets, "summary": f"{len(actions)} operation(s)"}