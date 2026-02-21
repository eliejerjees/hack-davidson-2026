from __future__ import annotations

import sys
from typing import Any

if sys.version_info >= (3, 10):
    from typing import TypeGuard
else:
    from typing_extensions import TypeGuard


def _is_number(value: Any) -> TypeGuard[int | float]:
    return isinstance(value, (int, float)) and not isinstance(value, bool)


def _as_float(value: Any, fallback: float = 0.0) -> float:
    if _is_number(value):
        return float(value)
    return fallback


def _as_int(value: Any, fallback: int = 0) -> int:
    if isinstance(value, int) and not isinstance(value, bool):
        return value
    if _is_number(value):
        return int(value)
    return fallback


def _fmt_time(seconds: float) -> str:
    minutes = int(seconds // 60)
    secs = float(seconds) - (60 * minutes)
    return f"{minutes:02d}:{secs:06.3f}"


def _selected_clips(ctx: dict[str, Any]) -> list[dict[str, Any]]:
    selected_items = ctx.get("selected_items")
    return selected_items if isinstance(selected_items, list) else []


def _selected_tracks(ctx: dict[str, Any]) -> list[dict[str, Any]]:
    selected_tracks = ctx.get("selected_tracks")
    return selected_tracks if isinstance(selected_tracks, list) else []


def _volume_delta_line(args: dict[str, Any]) -> str:
    if "db" in args:
        db = _as_float(args.get("db"))
        direction = "Raise" if db > 0 else "Lower"
        return f"{direction} track volume by {abs(db):.1f} dB"

    percent = _as_float(args.get("percent"))
    direction = "Raise" if percent > 0 else "Lower"
    multiplier = 1.0 + (percent / 100.0)
    return f"{direction} track volume by {abs(percent):.1f}% (gain x {multiplier:.2f})"


def _render_tool_line(tool_call: dict[str, Any], clip_count: int, track_count: int) -> str:
    name = tool_call.get("name")
    args_raw = tool_call.get("args")
    args = args_raw if isinstance(args_raw, dict) else {}

    if name == "fade_out":
        return f"Fade out by {_as_float(args.get('seconds')):.1f}s"
    if name == "fade_in":
        return f"Fade in by {_as_float(args.get('seconds')):.1f}s"
    if name == "set_volume_delta":
        return _volume_delta_line(args)
    if name == "set_volume_set":
        percent = _as_float(args.get("percent"))
        return f"Set track volume to {percent:.1f}% (gain = {percent / 100.0:.2f})"
    if name == "set_pan":
        pan = _as_int(args.get("pan"))
        if pan == 0:
            return "Set pan to center"
        direction = "left" if pan < 0 else "right"
        return f"Set pan to {abs(pan)} {direction}"
    if name == "add_fx":
        fx_type = args.get("type")
        return f"Add {fx_type} FX"
    if name == "mute":
        return "Mute selected track(s)"
    if name == "unmute":
        return "Unmute selected track(s)"
    if name == "solo":
        return "Solo selected track(s)"
    if name == "unsolo":
        return "Unsolo selected track(s)"
    if name == "crossfade":
        return f"Crossfade {clip_count} selected clips over {_as_float(args.get('seconds')):.1f}s"
    if name == "cut_middle":
        return f"Remove {_as_float(args.get('seconds')):.1f}s from middle of selected clip(s)"
    if name == "split_at_cursor":
        return "Split selected clip(s) at cursor"
    if name == "duplicate":
        count = _as_int(args.get("count"))
        if clip_count > 0:
            return f"Duplicate selected clip(s) {count} times"
        if track_count > 0:
            return f"Duplicate selected track(s) {count} times"
        return f"Duplicate selection {count} times"
    if name == "trim_to_time_selection":
        return "Trim selected clip(s) to time selection"

    return f"{name} {args}"


def build_preview(tool_calls: list[dict[str, Any]], ctx: dict[str, Any]) -> dict[str, Any]:
    clips = _selected_clips(ctx)
    tracks = _selected_tracks(ctx)
    clip_count = len(clips)
    track_count = len(tracks)

    bullets: list[str] = []
    uses_clips = False
    uses_tracks = False
    uses_time_selection = False

    for tool_call in tool_calls:
        name = tool_call.get("name")
        bullets.append(_render_tool_line(tool_call, clip_count, track_count))

        if name in {"fade_in", "fade_out", "crossfade", "cut_middle", "split_at_cursor", "trim_to_time_selection"}:
            uses_clips = True
        if name in {"set_volume_delta", "set_volume_set", "set_pan", "add_fx", "mute", "unmute", "solo", "unsolo"}:
            uses_tracks = True
        if name in {"split_at_cursor", "trim_to_time_selection"}:
            uses_time_selection = True
        if name == "duplicate":
            if clip_count > 0:
                uses_clips = True
            elif track_count > 0:
                uses_tracks = True

    if uses_clips:
        if clip_count == 1:
            bullets.append("Applied to 1 selected clip")
        elif clip_count > 1:
            bullets.append(f"Applied to {clip_count} selected clips")

        starts: list[float] = []
        ends: list[float] = []
        for clip in clips:
            if not isinstance(clip, dict):
                continue
            start = _as_float(clip.get("start"), fallback=-1.0)
            end = _as_float(clip.get("end"), fallback=-1.0)
            if start >= 0 and end >= 0:
                starts.append(start)
                ends.append(end)
        if starts and ends:
            bullets.append(f"Range: {_fmt_time(min(starts))} -> {_fmt_time(max(ends))}")

    if uses_tracks:
        if track_count == 1:
            bullets.append("Applied to 1 selected track")
        elif track_count > 1:
            bullets.append(f"Applied to {track_count} selected tracks")

    time_selection = ctx.get("time_selection")
    if uses_time_selection and isinstance(time_selection, dict):
        start = _as_float(time_selection.get("start"), fallback=-1.0)
        end = _as_float(time_selection.get("end"), fallback=-1.0)
        if end > start:
            bullets.append(f"Time selection: {_fmt_time(start)} -> {_fmt_time(end)}")

    return {"title": "Preview:", "bullets": bullets}


def render_preview_text(tool_calls: list[dict[str, Any]], ctx: dict[str, Any]) -> str:
    preview = build_preview(tool_calls, ctx)
    lines = [preview["title"]]
    lines.extend(f"- {bullet}" for bullet in preview["bullets"])
    return "\n".join(lines)
