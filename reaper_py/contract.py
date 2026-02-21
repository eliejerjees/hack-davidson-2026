from __future__ import annotations


def execute_tool_calls(tool_calls: list[dict], ctx: dict) -> None:
    # Person A will implement REAPER execution details here.
    selected_items = (ctx or {}).get("selected_items") or []
    selected_tracks = (ctx or {}).get("selected_tracks") or []
    time_selection = (ctx or {}).get("time_selection")

    print(
        "EXECUTION CONTEXT:",
        f"items={len(selected_items)}",
        f"tracks={len(selected_tracks)}",
        f"time_selection={'yes' if time_selection else 'no'}",
    )

    for call in tool_calls:
        name = call.get("name")
        args = call.get("args", {})
        if args:
            arg_text = ", ".join(f"{k}={v}" for k, v in args.items())
        else:
            arg_text = ""
        print(f"EXECUTE {name}({arg_text})")
