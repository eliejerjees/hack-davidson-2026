class CommandHistory:
    def __init__(self, limit=20):
        self.limit = limit
        self._items = []

    def add(self, cmd: str):
        cmd = (cmd or "").strip()
        if not cmd:
            return
        self._items.insert(0, cmd)
        self._items = self._items[: self.limit]

    def items(self):
        return list(self._items)