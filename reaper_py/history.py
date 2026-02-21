from datetime import datetime, timezone


class CommandHistory:
    def __init__(self, limit=20):
        self.limit = limit
        self._items = []

    def add(self, cmd: str, tool_calls=None, timestamp=None):
        cmd = (cmd or "").strip()
        if not cmd:
            return

        entry = {
            "timestamp": timestamp or datetime.now(timezone.utc).isoformat(),
            "command": cmd,
            "tool_calls": list(tool_calls or []),
        }
        self._items.insert(0, entry)
        self._items = self._items[: self.limit]

    def items(self):
        return list(self._items)
