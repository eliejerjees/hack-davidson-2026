# Cursor for DAWs (Hackathon MVP)

Gemini-first REAPER assistant with strict tool-calling, hard validation, and in-REAPER execution.

Primary UX is `cursor_panel.lua` (dockable ReaImGui sidebar panel).

## Core Flow

1. User enters text command (or voice command) in REAPER.
2. REAPER sends command + live selection context to `reaper_py/bridge.py`.
3. Python runs Gemini planner -> validation -> tool call plan.
4. REAPER executes validated tool calls in one Undo block.

Safety:
- Gemini is always used for natural language interpretation.
- Tool calls are whitelist-only and schema-validated.
- No execution occurs on planning/validation failure.
- Every edit is wrapped in Undo (`Cmd/Ctrl+Z`).

## Requirements

- REAPER
- ReaPack + ReaImGui
- Python 3.10+
- Gemini API key
- ElevenLabs API key (for Speech tab STT/TTS)
- `ffmpeg` in PATH (for Speech tab recording)

`ffmpeg` quick install:
- macOS (Homebrew): `brew install ffmpeg`
- Windows (Chocolatey): `choco install ffmpeg`

## Setup

### 1) Python environment

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

Dependencies:
- `requests`
- `python-dotenv`

### 2) Environment variables

```bash
cp .env.example .env
```

Set values in `.env`:

```env
GEMINI_API_KEY=your_gemini_key
GEMINI_MODEL=gemini-2.5-flash
ELEVENLABS_API_KEY=your_elevenlabs_key
ELEVENLABS_VOICE_ID=your_default_voice_id
```

`.env` is gitignored. Do not commit secrets.

### 3) Install ReaPack + ReaImGui

1. Install ReaPack: [https://reapack.com](https://reapack.com)
2. In REAPER: `Extensions -> ReaPack -> Browse packages`
3. Install `ReaImGui`

### 4) Load scripts in REAPER

In `Actions -> Show action list... -> ReaScript -> Load...`:

- Main panel: `/Users/eliejerjees/Desktop/Personal Projects/hack-davidson-2026/cursor_panel.lua`
- Fallback dialog script: `/Users/eliejerjees/Desktop/Personal Projects/hack-davidson-2026/cursor.lua`

## Dock as Sidebar (Right Docker)

1. Run `cursor_panel.lua`.
2. Drag the `Cursor for DAWs` tab/title bar into REAPER’s right docker area.
3. Drop when the dock highlight appears.

REAPER remembers docked layout after that. Screensets can be used if needed.

## Panel UX

Top status:
- `Selected clips`
- `Selected tracks`
- `Time selection`
- `Cursor`
- `Status`

Tabs:

### Commands
- Scrollable history log (always visible)
- Input + `Run` (or Enter) + `Clear`
- Immediate execution on success
- Clarification buttons for ambiguous target:
  - `Apply to Track(s)`
  - `Apply to Clip(s)`

### Speech
- Voice command recording (`Start Recording`) with 3s/5s/8s duration
- STT transcription via ElevenLabs, then runs same command pipeline
- `Speak after running a command` toggle (TTS)
- `Speak last response` button
- Optional voice ID override field

If `ffmpeg` is missing, Speech tab shows a clear error and recording is disabled.

## Whitelisted Tools

- `fade_out(seconds)`
- `fade_in(seconds)`
- `set_volume_delta(db | percent)`
- `set_volume_set(percent)`
- `set_pan(pan)`
- `add_fx(type)`
- `mute()` / `unmute()`
- `solo()` / `unsolo()`
- `crossfade(seconds)`
- `cut_middle(seconds)`
- `split_at_cursor()`
- `duplicate(count)`
- `trim_to_time_selection()`

## Volume Interpretation

- `lower volume by 3` -> dB mode
- `lower volume by 3%` -> percent delta mode
- `set volume to 50%` -> absolute percent mode

## Speech Notes

- This implementation includes **speech only** (STT + TTS).
- Music generation is **not** implemented in this feature set.

## Fallback Script

If ReaImGui is unavailable, run `cursor.lua` (dialog-based flow).
