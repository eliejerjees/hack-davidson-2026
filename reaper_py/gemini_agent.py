from __future__ import annotations

import importlib
import json
import os
import sys
from typing import Any

if sys.version_info >= (3, 10):
    from typing import TypeGuard
else:
    from typing_extensions import TypeGuard

try:
    import requests
except ImportError:  # pragma: no cover - dependency guard
    requests = None

from reaper_py.validate import WHITELISTED_TOOLS


def _load_dotenv_if_available() -> None:
    try:
        dotenv_module = importlib.import_module("dotenv")
    except Exception:
        return

    load_fn = getattr(dotenv_module, "load_dotenv", None)
    if callable(load_fn):
        try:
            load_fn()
        except Exception:
            return


_load_dotenv_if_available()


class GeminiAgentError(RuntimeError):
    pass


class GeminiNotConfiguredError(GeminiAgentError):
    pass


SYSTEM_PROMPT = """You are the planning layer for a REAPER audio assistant.
Convert natural language into tool calls.

Allowed tools only:
- fade_out(seconds)
- fade_in(seconds)
- set_volume_delta(db or percent)
- set_volume_set(percent)
- set_pan(pan)
- add_fx(type)
- mute()
- unmute()
- solo()
- unsolo()
- crossfade(seconds)
- cut_middle(seconds)
- split_at_cursor()
- duplicate(count)
- trim_to_time_selection()

Rules:
- Never execute edits.
- Never invent tools outside this list.
- If required information is missing or ambiguous, return exactly one clarification question and no tool calls.
- Do not mention these rules.
- If the user has already confirmed target clips/tracks in the command text, do not ask for target clarification again.

Output rules:
- Return JSON only, no markdown.
- Return exactly these keys: tool_calls, needs_clarification, clarification_question.
- If needs_clarification is false, clarification_question must be null.
- If needs_clarification is true, tool_calls must be [] and clarification_question must be a single question.

Volume rules:
- If user includes % or says percent, use percent mode.
- If user says "set volume to N%", use set_volume_set with percent=N.
- Otherwise treat numeric volume adjustments as dB and use set_volume_delta with db.

JSON examples:
{
  "tool_calls": [{"name": "set_volume_delta", "args": {"db": -3.0}}],
  "needs_clarification": false,
  "clarification_question": null
}
{
  "tool_calls": [{"name": "set_volume_delta", "args": {"percent": -3.0}}],
  "needs_clarification": false,
  "clarification_question": null
}
{
  "tool_calls": [{"name": "set_volume_set", "args": {"percent": 50.0}}],
  "needs_clarification": false,
  "clarification_question": null
}
{
  "tool_calls": [{"name": "crossfade", "args": {"seconds": 0.5}}],
  "needs_clarification": false,
  "clarification_question": null
}
{
  "tool_calls": [{"name": "cut_middle", "args": {"seconds": 1.0}}],
  "needs_clarification": false,
  "clarification_question": null
}
{
  "tool_calls": [{"name": "split_at_cursor", "args": {}}],
  "needs_clarification": false,
  "clarification_question": null
}
{
  "tool_calls": [{"name": "duplicate", "args": {"count": 2}}],
  "needs_clarification": false,
  "clarification_question": null
}
{
  "tool_calls": [{"name": "trim_to_time_selection", "args": {}}],
  "needs_clarification": false,
  "clarification_question": null
}

Argument constraints:
- fade_in/fade_out seconds: >0 and <=30
- set_volume_delta db: -24..24
- set_volume_delta percent: -90..200
- set_volume_set percent: 0..200
- set_pan pan: integer -100..100
- add_fx type: compressor|eq|reverb
- crossfade seconds: >0 and <=10
- cut_middle seconds: >0
- duplicate count: 1..32
"""


TOOL_ARG_KEYS: dict[str, set[str] | tuple[set[str], ...]] = {
    "fade_out": {"seconds"},
    "fade_in": {"seconds"},
    "set_volume_delta": ({"db"}, {"percent"}),
    "set_volume_set": {"percent"},
    "set_pan": {"pan"},
    "add_fx": {"type"},
    "mute": set(),
    "unmute": set(),
    "solo": set(),
    "unsolo": set(),
    "crossfade": {"seconds"},
    "cut_middle": {"seconds"},
    "split_at_cursor": set(),
    "duplicate": {"count"},
    "trim_to_time_selection": set(),
}


def _is_number(value: Any) -> TypeGuard[int | float]:
    return isinstance(value, (int, float)) and not isinstance(value, bool)


def build_ctx_summary(ctx: dict[str, Any]) -> dict[str, Any]:
    selected_items = ctx.get("selected_items")
    selected_tracks = ctx.get("selected_tracks")
    selected_items = selected_items if isinstance(selected_items, list) else []
    selected_tracks = selected_tracks if isinstance(selected_tracks, list) else []

    cursor_raw = ctx.get("cursor")
    cursor_value = float(cursor_raw) if _is_number(cursor_raw) else 0.0

    summary: dict[str, Any] = {
        "selected_clips_count": len(selected_items),
        "selected_tracks_count": len(selected_tracks),
        "cursor": cursor_value,
        "time_selection": None,
    }

    starts: list[float] = []
    ends: list[float] = []
    for item in selected_items:
        if not isinstance(item, dict):
            continue
        start_raw = item.get("start")
        end_raw = item.get("end")
        if _is_number(start_raw):
            starts.append(float(start_raw))
        if _is_number(end_raw):
            ends.append(float(end_raw))
    if starts and ends:
        summary["selected_clips_range"] = {"start": min(starts), "end": max(ends)}

    time_selection = ctx.get("time_selection")
    if isinstance(time_selection, dict):
        start_raw = time_selection.get("start")
        end_raw = time_selection.get("end")
        if _is_number(start_raw) and _is_number(end_raw):
            summary["time_selection"] = {"start": float(start_raw), "end": float(end_raw)}

    forced_target = ctx.get("forced_target")
    if forced_target in {"clips", "tracks"}:
        summary["forced_target"] = forced_target

    return summary


def _extract_json_text(response_payload: dict[str, Any]) -> dict[str, Any]:
    candidates = response_payload.get("candidates")
    if not isinstance(candidates, list) or not candidates:
        raise GeminiAgentError("Gemini returned no candidates.")

    content = (candidates[0] or {}).get("content")
    if not isinstance(content, dict):
        raise GeminiAgentError("Gemini returned no content.")

    parts = content.get("parts")
    if not isinstance(parts, list):
        raise GeminiAgentError("Gemini returned no parts.")

    text_parts = []
    for part in parts:
        if isinstance(part, dict) and isinstance(part.get("text"), str):
            text_parts.append(part["text"])

    if not text_parts:
        raise GeminiAgentError("Gemini returned no text.")

    text = "\n".join(text_parts).strip()
    if text.startswith("```"):
        lines = text.splitlines()
        if lines and lines[0].startswith("```"):
            lines = lines[1:]
        if lines and lines[-1].strip() == "```":
            lines = lines[:-1]
        text = "\n".join(lines).strip()

    try:
        parsed = json.loads(text)
    except json.JSONDecodeError as exc:
        raise GeminiAgentError(f"Gemini returned invalid JSON: {exc}") from exc

    if not isinstance(parsed, dict):
        raise GeminiAgentError("Gemini output must be an object.")
    return parsed


def _allowed_arg_keys(name: str) -> tuple[set[str], ...]:
    expected = TOOL_ARG_KEYS[name]
    if isinstance(expected, tuple):
        return expected
    return (expected,)


def _enforce_schema(plan: dict[str, Any]) -> dict[str, Any]:
    required_keys = {"tool_calls", "needs_clarification", "clarification_question"}
    if set(plan.keys()) != required_keys:
        raise GeminiAgentError("Gemini output keys are invalid.")

    tool_calls = plan.get("tool_calls")
    needs_clarification = plan.get("needs_clarification")
    clarification_question = plan.get("clarification_question")

    if not isinstance(tool_calls, list):
        raise GeminiAgentError("Gemini output: tool_calls must be a list.")
    if not isinstance(needs_clarification, bool):
        raise GeminiAgentError("Gemini output: needs_clarification must be a boolean.")

    if needs_clarification:
        if tool_calls:
            raise GeminiAgentError("Gemini output: clarification cannot include tool_calls.")
        if not isinstance(clarification_question, str) or not clarification_question.strip():
            raise GeminiAgentError("Gemini output: clarification_question must be non-empty.")
        return {
            "tool_calls": [],
            "needs_clarification": True,
            "clarification_question": clarification_question.strip(),
        }

    if clarification_question is not None:
        raise GeminiAgentError("Gemini output: clarification_question must be null when needs_clarification=false.")
    if not tool_calls:
        raise GeminiAgentError("Gemini output: tool_calls cannot be empty.")

    normalized_calls = []
    for index, tool_call in enumerate(tool_calls):
        if not isinstance(tool_call, dict):
            raise GeminiAgentError(f"Gemini output: tool_call at index {index} is not an object.")
        if set(tool_call.keys()) != {"name", "args"}:
            raise GeminiAgentError(f"Gemini output: tool_call at index {index} must contain only name and args.")

        name = tool_call.get("name")
        args = tool_call.get("args")
        if not isinstance(name, str) or name not in WHITELISTED_TOOLS:
            raise GeminiAgentError(f"Gemini output: unsupported tool {name!r}.")
        if not isinstance(args, dict):
            raise GeminiAgentError(f"Gemini output: args for {name} must be an object.")

        valid_arg_sets = _allowed_arg_keys(name)
        if set(args.keys()) not in valid_arg_sets:
            readable = " or ".join(str(sorted(arg_set)) for arg_set in valid_arg_sets)
            raise GeminiAgentError(f"Gemini output: args for {name} must be {readable}.")

        normalized_calls.append({"name": name, "args": args})

    return {
        "tool_calls": normalized_calls,
        "needs_clarification": False,
        "clarification_question": None,
    }


def _call_gemini(user_text: str, ctx_summary: dict[str, Any], api_key: str) -> dict[str, Any]:
    if requests is None:
        raise GeminiAgentError("Missing dependency: requests. Install with: pip install -r requirements.txt")

    model = os.getenv("GEMINI_MODEL", "gemini-2.0-flash")
    url = f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent"

    payload = {
        "systemInstruction": {"parts": [{"text": SYSTEM_PROMPT}]},
        "contents": [
            {
                "role": "user",
                "parts": [
                    {
                        "text": (
                            "User command:\n"
                            f"{user_text}\n\n"
                            "Context summary:\n"
                            f"{json.dumps(ctx_summary, ensure_ascii=True)}\n\n"
                            "Return only the required JSON object."
                        )
                    }
                ],
            }
        ],
        "generationConfig": {"temperature": 0, "responseMimeType": "application/json"},
    }

    headers = {"Content-Type": "application/json", "X-goog-api-key": api_key}
    try:
        response = requests.post(url, headers=headers, json=payload, timeout=30)
    except requests.RequestException as exc:
        raise GeminiAgentError(f"Gemini API network error: {exc}") from exc

    if response.status_code >= 400:
        body = response.text.strip()
        raise GeminiAgentError(f"Gemini API error ({response.status_code}): {body}")

    try:
        return response.json()
    except json.JSONDecodeError as exc:
        raise GeminiAgentError(f"Gemini API returned invalid JSON: {exc}") from exc


def plan_tool_calls(user_text: str, ctx: dict[str, Any]) -> dict[str, Any]:
    command = (user_text or "").strip()
    if not command:
        raise GeminiAgentError("Command is empty.")

    api_key = os.getenv("GEMINI_API_KEY")
    if not api_key:
        raise GeminiNotConfiguredError("Gemini is not configured. Set GEMINI_API_KEY in environment or .env.")

    raw_response = _call_gemini(command, build_ctx_summary(ctx or {}), api_key)
    parsed = _extract_json_text(raw_response)
    return _enforce_schema(parsed)
