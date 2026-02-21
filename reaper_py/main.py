from __future__ import annotations

from reaper_py.contract import execute_tool_calls
from reaper_py.gemini_agent import GeminiAgentError, GeminiNotConfiguredError, plan_tool_calls
from reaper_py.history import CommandHistory
from reaper_py.preview import build_preview
from reaper_py.validate import validate_tool_plan


hist = CommandHistory()


def mock_ctx_items() -> dict:
    return {
        "selected_items": [{"id": "item-1", "start": 42.1, "end": 45.1}],
        "selected_tracks": [],
        "time_selection": None,
        "cursor": 43.0,
    }


def mock_ctx_items2() -> dict:
    return {
        "selected_items": [
            {"id": "item-1", "start": 42.1, "end": 44.2},
            {"id": "item-2", "start": 44.0, "end": 46.5},
        ],
        "selected_tracks": [],
        "time_selection": None,
        "cursor": 44.1,
    }


def mock_ctx_tracks() -> dict:
    return {
        "selected_items": [],
        "selected_tracks": [{"id": "track-1", "name": "Lead Vox"}],
        "time_selection": None,
        "cursor": 43.0,
    }


def mock_ctx_time() -> dict:
    return {
        "selected_items": [],
        "selected_tracks": [],
        "time_selection": {"start": 42.1, "end": 44.1},
        "cursor": 43.0,
    }


def mock_ctx_none() -> dict:
    return {"selected_items": [], "selected_tracks": [], "time_selection": None, "cursor": 43.0}


CONTEXT_PRESETS = {
    "items": mock_ctx_items,
    "items2": mock_ctx_items2,
    "tracks": mock_ctx_tracks,
    "time": mock_ctx_time,
    "none": mock_ctx_none,
}


def _fmt_time(value: float) -> str:
    m = int(value // 60)
    s = float(value) - (60 * m)
    return f"{m:02d}:{s:06.3f}"


def ctx_summary(ctx: dict) -> str:
    item_count = len((ctx or {}).get("selected_items") or [])
    track_count = len((ctx or {}).get("selected_tracks") or [])
    ts = (ctx or {}).get("time_selection")
    cursor = float((ctx or {}).get("cursor", 0.0))
    time_text = "none"
    if isinstance(ts, dict) and "start" in ts and "end" in ts:
        time_text = f"{_fmt_time(float(ts['start']))} -> {_fmt_time(float(ts['end']))}"
    return f"items={item_count}, tracks={track_count}, time_selection={time_text}, cursor={_fmt_time(cursor)}"


def handle_ctx_command(raw: str, current_ctx: dict) -> dict:
    parts = raw.split()
    if len(parts) == 1 or (len(parts) == 2 and parts[1] == "show"):
        print("Context presets: items, items2, tracks, time, none")
        print("Current:", ctx_summary(current_ctx))
        return current_ctx

    if len(parts) != 2:
        print("Usage: :ctx <items|items2|tracks|time|none>")
        return current_ctx

    preset = parts[1].lower()
    builder = CONTEXT_PRESETS.get(preset)
    if not builder:
        print(f"Unknown context preset: {preset}")
        print("Available: items, items2, tracks, time, none")
        return current_ctx

    new_ctx = builder()
    print(f"Switched context -> {preset}: {ctx_summary(new_ctx)}")
    return new_ctx


def main():
    print("Gemini-first REAPER agent (MVP)")
    print("Type commands. q to quit.")
    print("Use :ctx <items|items2|tracks|time|none> to switch mock REAPER context.")

    ctx = mock_ctx_items()
    print("Current:", ctx_summary(ctx))

    while True:
        cmd = input("> ").strip()
        if cmd in ("q", "quit", "exit"):
            break

        if not cmd:
            continue

        if cmd.startswith(":ctx"):
            ctx = handle_ctx_command(cmd, ctx)
            continue

        try:
            plan = plan_tool_calls(cmd, ctx)
        except GeminiNotConfiguredError as exc:
            print(exc)
            continue
        except GeminiAgentError as exc:
            print(f"Gemini planning error: {exc}")
            continue

        if plan["needs_clarification"]:
            print(plan["clarification_question"])
            hist.add(cmd, tool_calls=[])
            continue

        hist.add(cmd, tool_calls=plan["tool_calls"])

        ok, error = validate_tool_plan(plan, ctx)
        if not ok:
            print(f"Validation error: {error}")
            print("No changes were prepared.")
            continue

        tool_calls = plan["tool_calls"]
        preview = build_preview(tool_calls, ctx)
        print(preview["title"])
        for bullet in preview["bullets"]:
            print("✓", bullet)

        apply_now = input("Apply? (y/n) ").strip().lower()
        if apply_now not in ("y", "yes"):
            print("Canceled.")
            continue

        execute_tool_calls(tool_calls, ctx)


if __name__ == "__main__":
    main()
