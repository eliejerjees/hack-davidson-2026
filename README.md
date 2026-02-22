# Cursor for DAWs (Hackathon MVP)

Gemini-first REAPER assistant with strict tool-calling, hard validation, preview rendering, and explicit Apply gating.

Primary UX is a dockable ReaImGui panel inside REAPER (`cursor_panel.lua`).

## What It Does

Flow:
1. User enters natural language command in REAPER panel.
2. REAPER sends command + live selection context to Python bridge.
3. Python runs Gemini planner -> validation -> preview.
4. REAPER shows preview.
5. Only when user clicks **Apply**, REAPER executes tool calls in an undo block.

No edits occur before Apply.

## Requirements

- REAPER
- ReaPack + ReaImGui extension
- Python 3.10+
- Gemini API key

## Setup

### 1) Python

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

`requirements.txt`:
- `requests`
- `python-dotenv`

### 2) Environment variables

```bash
cp .env.example .env
```

Edit `.env`:

```env
GEMINI_API_KEY=your_real_key
GEMINI_MODEL=gemini-2.5-flash
```

`.env` is gitignored. Do not commit secrets.

### 3) Install ReaPack + ReaImGui

1. Install ReaPack: [https://reapack.com](https://reapack.com)
2. In REAPER: `Extensions -> ReaPack -> Browse packages`
3. Search and install `ReaImGui`
4. Restart REAPER if prompted.

### 4) Load scripts in REAPER

1. Open `Actions -> Show action list...`
2. Click `ReaScript -> Load...`
3. Load `/Users/eliejerjees/Desktop/Personal Projects/hack-davidson-2026/cursor_panel.lua`
4. (Optional fallback) also load `/Users/eliejerjees/Desktop/Personal Projects/hack-davidson-2026/cursor.lua`

## Primary REAPER UX (Panel)

Run `cursor_panel.lua`.

Dock as sidebar:
1. Run the panel once.
2. Drag the `Cursor for DAWs` tab/title bar into REAPER's right docker area.
3. Release when REAPER shows the right-dock drop highlight.

After docking once, REAPER will remember the layout on future runs. If needed, save/restore with REAPER screensets.

Panel features:
- Dockable window titled **Cursor for DAWs**
- Live status row (selected clips, selected tracks, time selection, cursor)
- Chat history
- Command input + `Preview` button
- `Apply` button (only enabled with valid pending plan)
- `Clear` button
- Preview area + error/status line

Clarification behavior:
- At most one clarification turn (`Clips` / `Tracks` buttons)
- If still infeasible, panel shows one error and stops

## Whitelisted Tools

Only these tool calls are allowed:

- `fade_out(seconds)`
- `fade_in(seconds)`
- `set_volume_delta(db | percent)`
- `set_volume_set(percent)`
- `set_pan(pan)` where `pan` is integer `-100..100`
- `add_fx(type)` where type is `compressor|eq|reverb`
- `mute()` / `unmute()`
- `solo()` / `unsolo()`
- `crossfade(seconds)`
- `cut_middle(seconds)`
- `split_at_cursor()`
- `duplicate(count)`
- `trim_to_time_selection()`

## Volume Interpretation

- `lower volume by 3` -> dB mode -> `set_volume_delta({"db": -3})`
- `lower volume by 3%` -> percent delta mode -> `set_volume_delta({"percent": -3})`
- `set volume to 50%` -> absolute percent mode -> `set_volume_set({"percent": 50})`

Preview explicitly shows which interpretation was used.

## Manual Acceptance Tests (REAPER)

1. Select one clip:
   - Command: `fade this out by 500 ms`
   - Expect preview, then Apply changes clip fade.

2. Select one track:
   - Command: `lower volume by 3`
   - Expect dB preview, Apply changes track volume.

3. Select one track:
   - Command: `lower volume by 3%`
   - Expect percent preview with gain multiplier, Apply changes track volume.

4. No track selected:
   - Command: `lower volume by 3`
   - Expect single clarification/error, no loop, no edit.

5. Two clips selected:
   - Command: `crossfade these by half a second`
   - Expect preview and crossfade on Apply.

## Fallback Script

If ReaImGui is not installed, run `cursor.lua` (dialog-based flow).
It uses the same Python bridge and still enforces preview + explicit Apply.

## Dev Harness (Optional)

Run:

```bash
python3 -m reaper_py.main
```

Mock selection commands:
- `select a track`
- `select a clip`
- `select two clips`
- `select a time range`
- `clear selection`

Harness also uses the same bridge pipeline and supports one clarification turn.
