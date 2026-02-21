import re

SUPPORTED_EXAMPLES = [
    "fade in 500ms",
    "fade out 2s",
    "cut middle 1s",
    "trim to time selection",
    "split at cursor",
    "duplicate 4",
    "volume +3db",
    "volume -6db",
    "pan 30L",
    "pan 20R",
    "mute",
    "solo",
    "unmute",
    "unsolo",
    "add eq",
    "add compressor",
    "add reverb",
]

_time_re = re.compile(r"(?P<num>\d+(?:\.\d+)?)\s*(?P<unit>ms|millisecond(?:s)?|s|sec(?:s)?|second(?:s)?)\b")
_db_re = re.compile(r"(?P<db>[+-]?\d+(?:\.\d+)?)\s*db\b")
_pan_re = re.compile(r"\bpan\s+(?P<num>\d+(?:\.\d+)?)\s*(?P<side>[lr])\b")
_dup_re = re.compile(r"\bduplicate\s+(?P<count>\d+)\b")

def _normalize(s: str) -> str:
    s = (s or "").strip().lower()
    s = re.sub(r"\s+", " ", s)
    return s

def _resolve_target(ctx: dict):
    if ctx.get("hasTimeSelection"):
        return "time_selection"
    if ctx.get("hasSelectedItems"):
        return "selected_items"
    if ctx.get("hasSelectedTracks"):
        return "selected_tracks"
    return None

def _parse_time_seconds(cmd: str) -> float:
    m = _time_re.search(cmd)
    if not m:
        raise ValueError("Missing time value (e.g., 500ms or 2s).")
    num = float(m.group("num"))
    unit = m.group("unit")
    if unit.startswith("ms") or unit.startswith("millisecond"):
        return num / 1000.0
    return num

def _parse_db(cmd: str) -> float:
    m = _db_re.search(cmd)
    if not m:
        raise ValueError("Missing dB value (e.g., +3db).")
    return float(m.group("db"))

def _parse_pan(cmd: str) -> float:
    m = _pan_re.search(cmd)
    if not m:
        raise ValueError("Missing pan value (e.g., pan 30L).")
    val = float(m.group("num"))
    side = m.group("side")
    pan = -val if side == "l" else val
    if abs(pan) > 100:
        raise ValueError("Pan must be between 0 and 100 (e.g., pan 30L, pan 20R).")
    return pan

def _parse_dup(cmd: str) -> int:
    m = _dup_re.search(cmd)
    if not m:
        raise ValueError("Missing duplicate count (e.g., duplicate 4).")
    count = int(m.group("count"))
    if count < 1 or count > 32:
        raise ValueError("Duplicate count must be between 1 and 32.")
    return count

def _err(msg: str):
    return {
        "ok": False,
        "errors": [msg, "", "Examples:"] + [f"- {e}" for e in SUPPORTED_EXAMPLES]
    }

def parse(command: str, target_context: dict):
    cmd = _normalize(command)
    if not cmd:
        return _err("Enter a command.")

    target = _resolve_target(target_context or {})
    if not target:
        return _err("Select a time selection, item(s), or track(s) first.")

    # ITEM EDITS
    if cmd.startswith("fade in"):
        if target not in ("time_selection", "selected_items"):
            return _err("Fade in requires a time selection or selected item(s).")
        try:
            sec = _parse_time_seconds(cmd)
        except ValueError as e:
            return _err(str(e))
        return {"ok": True, "actions": [{"op": "fade_in", "target": target, "params": {"seconds": sec}}]}

    if cmd.startswith("fade out"):
        if target not in ("time_selection", "selected_items"):
            return _err("Fade out requires a time selection or selected item(s).")
        try:
            sec = _parse_time_seconds(cmd)
        except ValueError as e:
            return _err(str(e))
        return {"ok": True, "actions": [{"op": "fade_out", "target": target, "params": {"seconds": sec}}]}

    if cmd.startswith("cut middle"):
        if target not in ("time_selection", "selected_items"):
            return _err("Cut middle requires a time selection or selected item(s).")
        try:
            sec = _parse_time_seconds(cmd)
        except ValueError as e:
            return _err(str(e))
        return {"ok": True, "actions": [{"op": "cut_middle", "target": target, "params": {"seconds": sec}}]}

    if cmd == "trim to time selection":
        if not target_context.get("hasTimeSelection"):
            return _err("Trim to time selection requires a time selection.")
        return {"ok": True, "actions": [{"op": "trim_to_time_selection", "target": "time_selection", "params": {}}]}

    if cmd == "split at cursor":
        if target not in ("time_selection", "selected_items"):
            return _err("Split at cursor requires selected item(s) or a time selection.")
        return {"ok": True, "actions": [{"op": "split_at_cursor", "target": target, "params": {}}]}

    if cmd.startswith("duplicate"):
        if target not in ("selected_items", "selected_tracks"):
            return _err("Duplicate requires selected item(s) or selected track(s).")
        try:
            count = _parse_dup(cmd)
        except ValueError as e:
            return _err(str(e))
        return {"ok": True, "actions": [{"op": "duplicate", "target": target, "params": {"count": count}}]}

    # TRACK CONTROLS
    if cmd.startswith("volume"):
        if target != "selected_tracks":
            return _err("Volume commands require selected track(s).")
        try:
            db = _parse_db(cmd)
        except ValueError as e:
            return _err(str(e))
        return {"ok": True, "actions": [{"op": "set_volume_delta", "target": "selected_tracks", "params": {"db": db}}]}

    if cmd.startswith("pan"):
        if target != "selected_tracks":
            return _err("Pan commands require selected track(s).")
        try:
            pan = _parse_pan(cmd)
        except ValueError as e:
            return _err(str(e))
        return {"ok": True, "actions": [{"op": "set_pan", "target": "selected_tracks", "params": {"pan": pan}}]}

    if cmd in ("mute", "unmute", "solo", "unsolo"):
        if target != "selected_tracks":
            return _err(f"{cmd} requires selected track(s).")
        return {"ok": True, "actions": [{"op": cmd, "target": "selected_tracks", "params": {}}]}

    # FX
    if cmd in ("add eq", "add compressor", "add reverb"):
        if target != "selected_tracks":
            return _err("FX insertion requires selected track(s).")
        fx_type = cmd.replace("add ", "")
        return {"ok": True, "actions": [{"op": "add_fx", "target": "selected_tracks", "params": {"type": fx_type}}]}

    return _err("Unsupported command.")