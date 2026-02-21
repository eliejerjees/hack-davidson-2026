from __future__ import annotations


ITEM_TOOLS = {
    "fade_in",
    "fade_out",
    "cut_middle",
    "trim_to_time_selection",
    "split_at_cursor",
    "crossfade",
}

TRACK_TOOLS = {
    "set_volume_delta",
    "set_pan",
    "mute",
    "unmute",
    "solo",
    "unsolo",
    "add_fx",
}


def _fmt_duration(seconds: float) -> str:
    return f"{float(seconds):.1f}s"


def _fmt_range(seconds: float) -> str:
    m = int(seconds // 60)
    s = float(seconds) - (60 * m)
    return f"{m:02d}:{s:06.3f}"


def _selected_items(ctx: dict) -> list[dict]:
    items = (ctx or {}).get("selected_items")
    return items if isinstance(items, list) else []


def _selected_tracks(ctx: dict) -> list[dict]:
    tracks = (ctx or {}).get("selected_tracks")
    return tracks if isinstance(tracks, list) else []


def _time_selection(ctx: dict) -> dict | None:
    ts = (ctx or {}).get("time_selection")
    return ts if isinstance(ts, dict) else None


def build_preview(tool_calls: list[dict], ctx: dict) -> dict:
    bullets = []
    item_calls = False
    track_calls = False
    time_selection_calls = False

    selected_items = _selected_items(ctx)
    selected_tracks = _selected_tracks(ctx)
    ts = _time_selection(ctx)

    has_items = len(selected_items) > 0
    has_tracks = len(selected_tracks) > 0
    has_time_selection = bool(ts and "start" in ts and "end" in ts)

    for call in tool_calls:
        name = call.get("name")
        args = call.get("args", {})

        if name in ITEM_TOOLS:
            item_calls = True
        if name in TRACK_TOOLS:
            track_calls = True

        if name == "fade_in":
            target = "selected item(s)" if has_items else "time selection"
            bullets.append(f"Fade in {target} by {_fmt_duration(args['seconds'])}")
            if not has_items and has_time_selection:
                time_selection_calls = True
        elif name == "fade_out":
            target = "selected item(s)" if has_items else "time selection"
            bullets.append(f"Fade out {target} by {_fmt_duration(args['seconds'])}")
            if not has_items and has_time_selection:
                time_selection_calls = True
        elif name == "cut_middle":
            target = "selected item(s)" if has_items else "time selection"
            bullets.append(f"Cut {_fmt_duration(args['seconds'])} from middle of {target}")
            if not has_items and has_time_selection:
                time_selection_calls = True
        elif name == "trim_to_time_selection":
            bullets.append("Trim selected item(s) to current time selection")
            time_selection_calls = True
        elif name == "split_at_cursor":
            target = "selected item(s)" if has_items else "time selection"
            bullets.append(f"Split {target} at cursor")
            if not has_items and has_time_selection:
                time_selection_calls = True
        elif name == "duplicate":
            if has_items and not has_tracks:
                item_calls = True
                bullets.append(f"Duplicate selected item(s) by {args['count']} time(s)")
            elif has_tracks and not has_items:
                track_calls = True
                bullets.append(f"Duplicate selected track(s) by {args['count']} time(s)")
            else:
                bullets.append(f"Duplicate target by {args['count']} time(s)")
        elif name == "set_volume_delta":
            bullets.append(f"Adjust selected track volume by {float(args['db']):+.1f} dB")
        elif name == "set_pan":
            pan = float(args["pan"])
            if pan < 0:
                bullets.append(f"Set selected track pan to {abs(pan):.1f} left")
            elif pan > 0:
                bullets.append(f"Set selected track pan to {pan:.1f} right")
            else:
                bullets.append("Set selected track pan to center")
        elif name == "mute":
            bullets.append("Mute selected track(s)")
        elif name == "unmute":
            bullets.append("Unmute selected track(s)")
        elif name == "solo":
            bullets.append("Solo selected track(s)")
        elif name == "unsolo":
            bullets.append("Unsolo selected track(s)")
        elif name == "add_fx":
            bullets.append(f"Add {args['type']} FX to selected track(s)")
        elif name == "crossfade":
            bullets.append(f"Crossfade selected items by {_fmt_duration(args['seconds'])}")

    if item_calls:
        if has_items:
            bullets.append(f"Applied to {len(selected_items)} item(s)")
        elif has_time_selection:
            bullets.append("Applied to time selection")
        else:
            bullets.append("Applied to selected item(s)")

        starts = [float(i["start"]) for i in selected_items if isinstance(i, dict) and "start" in i and "end" in i]
        ends = [float(i["end"]) for i in selected_items if isinstance(i, dict) and "start" in i and "end" in i]
        if starts and ends:
            bullets.append(f"Range: {_fmt_range(min(starts))} -> {_fmt_range(max(ends))}")
        elif has_time_selection and ts:
            bullets.append(f"Range: {_fmt_range(float(ts['start']))} -> {_fmt_range(float(ts['end']))}")

    if track_calls:
        if has_tracks:
            bullets.append(f"Applied to {len(selected_tracks)} track(s)")
        else:
            bullets.append("Applied to selected track(s)")

    if time_selection_calls and has_time_selection and ts and not (item_calls and not has_items):
        bullets.append(f"Time selection: {_fmt_range(float(ts['start']))} -> {_fmt_range(float(ts['end']))}")

    return {"title": "Preview:", "bullets": bullets, "summary": f"{len(tool_calls)} tool call(s)"}
