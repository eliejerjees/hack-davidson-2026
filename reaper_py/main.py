from reaper_py.history import CommandHistory
import reaper_py.parser as Parser
from reaper_py.preview import build_preview

hist = CommandHistory()

def mock_ctx_items():
    return {"hasTimeSelection": False, "hasSelectedItems": True, "hasSelectedTracks": False, "counts": {"items": 1}}

def mock_ctx_tracks():
    return {"hasTimeSelection": False, "hasSelectedItems": False, "hasSelectedTracks": True, "counts": {"tracks": 2}}

def mock_ctx_time():
    return {"hasTimeSelection": True, "hasSelectedItems": False, "hasSelectedTracks": False,
            "timeSelection": {"start": 42.1, "end": 44.1}}

def resolve_target(ctx):
    if ctx.get("hasTimeSelection"): return "time_selection"
    if ctx.get("hasSelectedItems"): return "selected_items"
    if ctx.get("hasSelectedTracks"): return "selected_tracks"
    return None

def main():
    print("Type commands. q to quit.")
    ctx = mock_ctx_items()  # switch to tracks/time to test
    while True:
        cmd = input("> ").strip()
        if cmd in ("q", "quit", "exit"):
            break

        res = Parser.parse(cmd, ctx)
        if not res.get("ok"):
            print("\n".join(res.get("errors", ["Parse error"])))
            continue

        actions = res["actions"]
        target = resolve_target(ctx)
        if target is None:
            print("No target selected.")
            continue

        prev = build_preview(actions, target, ctx)

        print(prev["title"])
        for b in prev["bullets"]:
            print("✓", b)

        hist.add(cmd)
        print("actions:", actions)
        print("history:", hist.items())

if __name__ == "__main__":
    main()