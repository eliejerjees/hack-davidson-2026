from __future__ import annotations

import sys
from typing import Any

if sys.version_info >= (3, 10):
    from typing import TypeGuard
else:
    from typing_extensions import TypeGuard


WHITELISTED_TOOLS = {
    "fade_out",
    "fade_in",
    "set_volume_delta",
    "set_volume_set",
    "set_pan",
    "add_fx",
    "mute",
    "unmute",
    "solo",
    "unsolo",
    "crossfade",
    "cut_middle",
    "split_at_cursor",
    "duplicate",
    "trim_to_time_selection",
}

FX_TYPES = {"compressor", "eq", "reverb"}
NO_ARG_TOOLS = {"mute", "unmute", "solo", "unsolo", "split_at_cursor", "trim_to_time_selection"}


def _is_number(value: Any) -> TypeGuard[int | float]:
    return isinstance(value, (int, float)) and not isinstance(value, bool)


def _selected_items(ctx: dict[str, Any]) -> list[dict[str, Any]]:
    selected_items = ctx.get("selected_items")
    return selected_items if isinstance(selected_items, list) else []


def _selected_tracks(ctx: dict[str, Any]) -> list[dict[str, Any]]:
    selected_tracks = ctx.get("selected_tracks")
    return selected_tracks if isinstance(selected_tracks, list) else []


def _has_time_selection(ctx: dict[str, Any]) -> bool:
    time_selection = ctx.get("time_selection")
    if not isinstance(time_selection, dict):
        return False
    start = time_selection.get("start")
    end = time_selection.get("end")
    if not (_is_number(start) and _is_number(end)):
        return False
    return float(end) > float(start)


def _validate_plan_shape(plan: dict[str, Any]) -> tuple[bool, str | None]:
    required_keys = {"tool_calls", "needs_clarification", "clarification_question"}
    if set(plan.keys()) != required_keys:
        return False, "Invalid plan: keys must be exactly tool_calls, needs_clarification, clarification_question."

    if not isinstance(plan.get("tool_calls"), list):
        return False, "Invalid plan: tool_calls must be a list."
    if not isinstance(plan.get("needs_clarification"), bool):
        return False, "Invalid plan: needs_clarification must be boolean."

    if plan["needs_clarification"]:
        if plan["tool_calls"]:
            return False, "Invalid plan: clarification response must not include tool calls."
        question = plan.get("clarification_question")
        if not isinstance(question, str) or not question.strip():
            return False, "Invalid plan: clarification_question must be a non-empty string."
        return True, None

    if plan.get("clarification_question") is not None:
        return False, "Invalid plan: clarification_question must be null when needs_clarification=false."
    if not plan["tool_calls"]:
        return False, "Invalid plan: tool_calls cannot be empty."

    return True, None


def _validate_set_volume_delta(args: dict[str, Any]) -> tuple[bool, str | None]:
    has_db = "db" in args
    has_percent = "percent" in args
    if has_db == has_percent:
        return False, "Invalid args for set_volume_delta: provide exactly one of db or percent."

    if has_db:
        if set(args.keys()) != {"db"}:
            return False, "Invalid args for set_volume_delta: only db is allowed in dB mode."
        db = args.get("db")
        if not _is_number(db):
            return False, "Invalid args for set_volume_delta: db must be numeric."
        if not (-24 <= float(db) <= 24):
            return False, "Invalid args for set_volume_delta: db must be between -24 and 24."
        return True, None

    if set(args.keys()) != {"percent"}:
        return False, "Invalid args for set_volume_delta: only percent is allowed in percent mode."
    percent = args.get("percent")
    if not _is_number(percent):
        return False, "Invalid args for set_volume_delta: percent must be numeric."
    if not (-90 <= float(percent) <= 200):
        return False, "Invalid args for set_volume_delta: percent must be between -90 and 200."
    return True, None


def _validate_set_volume_set(args: dict[str, Any]) -> tuple[bool, str | None]:
    if set(args.keys()) != {"percent"}:
        return False, "Invalid args for set_volume_set: expected only percent."
    percent = args.get("percent")
    if not _is_number(percent):
        return False, "Invalid args for set_volume_set: percent must be numeric."
    if not (0 <= float(percent) <= 200):
        return False, "Invalid args for set_volume_set: percent must be between 0 and 200."
    return True, None


def validate_tool_plan(plan: dict[str, Any], ctx: dict[str, Any]) -> tuple[bool, str | None]:
    if not isinstance(plan, dict):
        return False, "Invalid plan: expected object."
    if not isinstance(ctx, dict):
        return False, "Invalid context: expected object."

    ok, shape_error = _validate_plan_shape(plan)
    if not ok:
        return False, shape_error
    if plan["needs_clarification"]:
        return True, None

    item_count = len(_selected_items(ctx))
    track_count = len(_selected_tracks(ctx))
    has_time_selection = _has_time_selection(ctx)

    for index, tool_call in enumerate(plan["tool_calls"]):
        if not isinstance(tool_call, dict):
            return False, f"Invalid tool call at index {index}: expected object."
        if set(tool_call.keys()) != {"name", "args"}:
            return False, f"Invalid tool call at index {index}: keys must be exactly name and args."

        name = tool_call.get("name")
        args = tool_call.get("args")
        if not isinstance(name, str) or name not in WHITELISTED_TOOLS:
            return False, f"Unsupported tool: {name!r}."
        if not isinstance(args, dict):
            return False, f"Invalid args for {name}: expected object."

        if name in NO_ARG_TOOLS:
            if args:
                return False, f"Invalid args for {name}: expected no args."

        elif name in {"fade_in", "fade_out"}:
            if set(args.keys()) != {"seconds"}:
                return False, f"Invalid args for {name}: expected only seconds."
            seconds = args.get("seconds")
            if not _is_number(seconds):
                return False, f"Invalid args for {name}: seconds must be numeric."
            if not (0 < float(seconds) <= 30):
                return False, f"Invalid args for {name}: seconds must be > 0 and <= 30."
            if item_count < 1:
                return False, f"{name} requires at least 1 selected clip."

        elif name == "set_volume_delta":
            valid, err = _validate_set_volume_delta(args)
            if not valid:
                return False, err
            if track_count < 1:
                return False, "set_volume_delta requires at least 1 selected track."

        elif name == "set_volume_set":
            valid, err = _validate_set_volume_set(args)
            if not valid:
                return False, err
            if track_count < 1:
                return False, "set_volume_set requires at least 1 selected track."

        elif name == "set_pan":
            if set(args.keys()) != {"pan"}:
                return False, "Invalid args for set_pan: expected only pan."
            pan = args.get("pan")
            if not isinstance(pan, int) or isinstance(pan, bool):
                return False, "Invalid args for set_pan: pan must be an integer."
            if not (-100 <= pan <= 100):
                return False, "Invalid args for set_pan: pan must be between -100 and 100."
            if track_count < 1:
                return False, "set_pan requires at least 1 selected track."

        elif name == "add_fx":
            if set(args.keys()) != {"type"}:
                return False, "Invalid args for add_fx: expected only type."
            fx_type = args.get("type")
            if not isinstance(fx_type, str):
                return False, "Invalid args for add_fx: type must be a string."
            if fx_type not in FX_TYPES:
                return False, f"Invalid args for add_fx: type must be one of {sorted(FX_TYPES)}."
            if track_count < 1:
                return False, "add_fx requires at least 1 selected track."

        elif name in {"mute", "unmute", "solo", "unsolo"}:
            if track_count < 1:
                return False, f"{name} requires at least 1 selected track."

        elif name == "crossfade":
            if set(args.keys()) != {"seconds"}:
                return False, "Invalid args for crossfade: expected only seconds."
            seconds = args.get("seconds")
            if not _is_number(seconds):
                return False, "Invalid args for crossfade: seconds must be numeric."
            if not (0 < float(seconds) <= 10):
                return False, "Invalid args for crossfade: seconds must be > 0 and <= 10."
            if item_count != 2:
                return False, "crossfade requires exactly 2 selected clips."

        elif name == "cut_middle":
            if set(args.keys()) != {"seconds"}:
                return False, "Invalid args for cut_middle: expected only seconds."
            seconds = args.get("seconds")
            if not _is_number(seconds):
                return False, "Invalid args for cut_middle: seconds must be numeric."
            if not (float(seconds) > 0):
                return False, "Invalid args for cut_middle: seconds must be > 0."
            if item_count < 1:
                return False, "cut_middle requires at least 1 selected clip."

        elif name == "split_at_cursor":
            if item_count < 1 and not has_time_selection:
                return False, "split_at_cursor requires selected clip(s) or a time selection."

        elif name == "duplicate":
            if set(args.keys()) != {"count"}:
                return False, "Invalid args for duplicate: expected only count."
            count = args.get("count")
            if not isinstance(count, int) or isinstance(count, bool):
                return False, "Invalid args for duplicate: count must be an integer."
            if not (1 <= count <= 32):
                return False, "Invalid args for duplicate: count must be between 1 and 32."
            if item_count < 1 and track_count < 1:
                return False, "duplicate requires selected clip(s) or selected track(s)."

        elif name == "trim_to_time_selection":
            if not has_time_selection:
                return False, "trim_to_time_selection requires an active time selection."
            if item_count < 1:
                return False, "trim_to_time_selection requires at least 1 selected clip."

    return True, None


def suggestion_for_error(error: str, ctx: dict[str, Any]) -> str | None:
    item_count = len(_selected_items(ctx))
    track_count = len(_selected_tracks(ctx))

    if "selected clip" in error and track_count > 0:
        return "Do you mean the selected clip(s) or the selected track(s)?"
    if "selected track" in error and item_count > 0:
        return "Do you mean the selected track(s) or the selected clip(s)?"
    if "crossfade requires exactly 2 selected clips" in error:
        return "Please select exactly two clips to crossfade."
    return None
