from __future__ import annotations

from typing import Any


FX_TYPES = {"eq", "compressor", "reverb"}

WHITELISTED_TOOLS = {
    "fade_in",
    "fade_out",
    "cut_middle",
    "trim_to_time_selection",
    "split_at_cursor",
    "duplicate",
    "set_volume_delta",
    "set_pan",
    "mute",
    "unmute",
    "solo",
    "unsolo",
    "add_fx",
    "crossfade",
}

NO_ARG_TOOLS = {
    "trim_to_time_selection",
    "split_at_cursor",
    "mute",
    "unmute",
    "solo",
    "unsolo",
}

SECONDS_TOOLS = {"fade_in", "fade_out", "cut_middle", "crossfade"}
ITEM_OR_TIME_TOOLS = {"fade_in", "fade_out", "cut_middle", "split_at_cursor"}
TRACK_TOOLS = {"set_volume_delta", "set_pan", "mute", "unmute", "solo", "unsolo", "add_fx"}
ITEM_TOOLS = {"crossfade"}


def _is_number(value: Any) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool)


def _expected_arg_keys(tool_name: str) -> set[str]:
    if tool_name in SECONDS_TOOLS:
        return {"seconds"}
    if tool_name == "duplicate":
        return {"count"}
    if tool_name == "set_volume_delta":
        return {"db"}
    if tool_name == "set_pan":
        return {"pan"}
    if tool_name == "add_fx":
        return {"type"}
    if tool_name in NO_ARG_TOOLS:
        return set()
    return set()


def _has_time_selection(ctx: dict[str, Any]) -> bool:
    ts = ctx.get("time_selection")
    if ts is None:
        return False
    if not isinstance(ts, dict):
        return False
    start = ts.get("start")
    end = ts.get("end")
    return _is_number(start) and _is_number(end) and float(end) > float(start)


def _selected_items(ctx: dict[str, Any]) -> list[dict[str, Any]]:
    items = ctx.get("selected_items")
    return items if isinstance(items, list) else []


def _selected_tracks(ctx: dict[str, Any]) -> list[dict[str, Any]]:
    tracks = ctx.get("selected_tracks")
    return tracks if isinstance(tracks, list) else []


def validate_tool_plan(plan: dict[str, Any], ctx: dict[str, Any]) -> tuple[bool, str | None]:
    if not isinstance(plan, dict):
        return False, "Invalid plan: expected object."

    required_plan_keys = {"tool_calls", "needs_clarification", "clarification_question"}
    if set(plan.keys()) != required_plan_keys:
        return False, "Invalid plan: keys must be exactly tool_calls, needs_clarification, clarification_question."

    tool_calls = plan.get("tool_calls")
    needs_clarification = plan.get("needs_clarification")
    clarification_question = plan.get("clarification_question")

    if not isinstance(needs_clarification, bool):
        return False, "Invalid plan: needs_clarification must be boolean."
    if not isinstance(tool_calls, list):
        return False, "Invalid plan: tool_calls must be a list."

    if needs_clarification:
        if tool_calls:
            return False, "Invalid plan: clarification responses must not include tool calls."
        if not isinstance(clarification_question, str) or not clarification_question.strip():
            return False, "Invalid plan: clarification_question must be a non-empty string when clarification is needed."
        return True, None

    if clarification_question is not None:
        return False, "Invalid plan: clarification_question must be null when clarification is not needed."
    if not tool_calls:
        return False, "Invalid plan: at least one tool call is required."

    has_items = len(_selected_items(ctx)) > 0
    has_tracks = len(_selected_tracks(ctx)) > 0
    has_time_selection = _has_time_selection(ctx)

    for index, call in enumerate(tool_calls):
        if not isinstance(call, dict):
            return False, f"Invalid tool call at index {index}: expected object."
        if set(call.keys()) != {"name", "args"}:
            return False, f"Invalid tool call at index {index}: keys must be exactly name and args."

        name = call.get("name")
        args = call.get("args")

        if not isinstance(name, str) or name not in WHITELISTED_TOOLS:
            return False, f"Unsupported tool: {name!r}."
        if not isinstance(args, dict):
            return False, f"Invalid args for {name}: expected object."

        expected_keys = _expected_arg_keys(name)
        if set(args.keys()) != expected_keys:
            return False, f"Invalid args for {name}: expected keys {sorted(expected_keys)}."

        if name in SECONDS_TOOLS:
            seconds = args.get("seconds")
            if not _is_number(seconds):
                return False, f"Invalid args for {name}: seconds must be a number."
            if not (0 < float(seconds) <= 30):
                return False, f"Invalid args for {name}: seconds must be > 0 and <= 30."
        elif name == "duplicate":
            count = args.get("count")
            if not isinstance(count, int) or isinstance(count, bool):
                return False, "Invalid args for duplicate: count must be an integer."
            if not (1 <= count <= 32):
                return False, "Invalid args for duplicate: count must be between 1 and 32."
        elif name == "set_volume_delta":
            db = args.get("db")
            if not _is_number(db):
                return False, "Invalid args for set_volume_delta: db must be a number."
            if not (-24 <= float(db) <= 24):
                return False, "Invalid args for set_volume_delta: db must be between -24 and 24."
        elif name == "set_pan":
            pan = args.get("pan")
            if not _is_number(pan):
                return False, "Invalid args for set_pan: pan must be a number."
            if not (-100 <= float(pan) <= 100):
                return False, "Invalid args for set_pan: pan must be between -100 and 100."
        elif name == "add_fx":
            fx_type = args.get("type")
            if not isinstance(fx_type, str):
                return False, "Invalid args for add_fx: type must be a string."
            if fx_type not in FX_TYPES:
                return False, f"Invalid args for add_fx: type must be one of {sorted(FX_TYPES)}."

        if name in ITEM_OR_TIME_TOOLS and not (has_items or has_time_selection):
            return False, f"{name} requires selected items or a valid time selection."
        if name == "duplicate" and not (has_items or has_tracks):
            return False, "duplicate requires selected items or selected tracks."
        if name in TRACK_TOOLS and not has_tracks:
            return False, f"{name} requires selected tracks."
        if name == "trim_to_time_selection" and not has_time_selection:
            return False, "trim_to_time_selection requires a valid time selection."
        if name in ITEM_TOOLS and not has_items:
            return False, f"{name} requires selected items."
        if name == "crossfade" and len(_selected_items(ctx)) != 2:
            return False, "crossfade requires exactly 2 selected items."

    return True, None
