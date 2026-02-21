from __future__ import annotations

from typing import Any

from reaper_py.bridge import process_payload
from reaper_py.contract import execute_tool_calls
from reaper_py.history import CommandHistory


history = CommandHistory()


def mock_ctx_none() -> dict[str, Any]:
    return {
        "selected_items": [],
        "selected_tracks": [],
        "time_selection": None,
        "cursor": 43.0,
    }


def mock_ctx_clip() -> dict[str, Any]:
    return {
        "selected_items": [{"start": 42.1, "end": 45.1, "length": 3.0}],
        "selected_tracks": [],
        "time_selection": None,
        "cursor": 43.0,
    }


def mock_ctx_two_clips() -> dict[str, Any]:
    return {
        "selected_items": [
            {"start": 42.1, "end": 44.1, "length": 2.0},
            {"start": 44.2, "end": 46.2, "length": 2.0},
        ],
        "selected_tracks": [],
        "time_selection": None,
        "cursor": 44.1,
    }


def mock_ctx_track() -> dict[str, Any]:
    return {
        "selected_items": [],
        "selected_tracks": [{"name": "Track 1", "index": 1}],
        "time_selection": None,
        "cursor": 43.0,
    }


def mock_ctx_time() -> dict[str, Any]:
    return {
        "selected_items": [],
        "selected_tracks": [],
        "time_selection": {"start": 42.0, "end": 46.0},
        "cursor": 43.0,
    }


def _show_ctx(ctx: dict[str, Any]) -> str:
    return (
        f"clips={len(ctx.get('selected_items') or [])}, "
        f"tracks={len(ctx.get('selected_tracks') or [])}, "
        f"time_selection={'yes' if ctx.get('time_selection') else 'no'}"
    )


def _context_hint(answer: str, ctx: dict[str, Any]) -> str | None:
    if answer == "tracks" and not (ctx.get("selected_tracks") or []):
        return "No tracks in this mock context. Use 'select a track' to simulate selection."
    if answer == "clips" and not (ctx.get("selected_items") or []):
        return "No clips in this mock context. Use 'select a clip' to simulate selection."
    return None


def _set_context_from_command(command: str) -> dict[str, Any] | None:
    normalized = " ".join(command.strip().lower().split())
    if normalized == "select a track":
        return mock_ctx_track()
    if normalized == "select a clip":
        return mock_ctx_clip()
    if normalized == "select two clips":
        return mock_ctx_two_clips()
    if normalized == "select a time range":
        return mock_ctx_time()
    if normalized == "clear selection":
        return mock_ctx_none()
    return None


def main() -> None:
    print("Cursor for DAWs dev harness")
    print("Type natural-language commands, or q to quit.")
    print("Mock selection commands:")
    print("- select a track")
    print("- select a clip")
    print("- select two clips")
    print("- select a time range")
    print("- clear selection")

    ctx = mock_ctx_none()
    print(f"Current context: {_show_ctx(ctx)}")

    while True:
        command = input("> ").strip()
        if command in {"q", "quit", "exit"}:
            break
        if not command:
            continue

        next_ctx = _set_context_from_command(command)
        if next_ctx is not None:
            ctx = next_ctx
            print(f"Context updated -> {_show_ctx(ctx)}")
            continue

        response = process_payload({"cmd": command, "ctx": ctx})
        history.add(command, response.get("tool_calls") or [])

        if not response.get("ok"):
            print(response.get("error") or "Unknown error.")
            continue

        if response.get("needs_clarification"):
            question = response.get("clarification_question") or "Do you mean clips or tracks?"
            print(question)
            answer = input("Answer (clips/tracks): ").strip().lower()
            if answer not in {"clips", "clip", "tracks", "track"}:
                print("Clarification skipped. Please answer with clips or tracks.")
                continue

            forced_target = "tracks" if answer.startswith("track") else "clips"
            follow_up = process_payload(
                {
                    "cmd": command,
                    "ctx": ctx,
                    "forced_target": forced_target,
                    "clarification_answer": forced_target,
                }
            )

            if not follow_up.get("ok"):
                print(follow_up.get("error") or "Could not resolve clarification.")
                hint = _context_hint(forced_target, ctx)
                if hint:
                    print(hint)
                continue

            if follow_up.get("needs_clarification"):
                print("Still ambiguous after one clarification. Try a more specific command.")
                continue

            response = follow_up

        print(response.get("preview") or "")
        apply_now = input("Apply? (y/n) ").strip().lower()
        if apply_now not in {"y", "yes"}:
            print("Canceled.")
            continue

        execute_tool_calls(response.get("tool_calls") or [], ctx)


if __name__ == "__main__":
    main()
