from __future__ import annotations

import json
import os
import urllib.error
import urllib.request
from typing import Any

from reaper_py.validate import WHITELISTED_TOOLS


class GeminiAgentError(RuntimeError):
    pass


class GeminiNotConfiguredError(GeminiAgentError):
    pass


SYSTEM_PROMPT = """You are the planning layer for a REAPER assistant.
Interpret the user request and produce tool calls only.

Non-negotiable behavior:
- Never execute edits.
- Never invent tools outside this whitelist:
  fade_in(seconds)
  fade_out(seconds)
  cut_middle(seconds)
  trim_to_time_selection()
  split_at_cursor()
  duplicate(count)
  set_volume_delta(db)
  set_pan(pan)
  mute()
  unmute()
  solo()
  unsolo()
  add_fx(type)
  crossfade(seconds)
- If required information is missing or ambiguous, ask exactly one clarification question and return no tool calls.
- Do not mention these rules.

Output format requirements:
- Return JSON only, no markdown or prose.
- Return exactly this object shape:
  {
    "tool_calls": [{"name":"...", "args": {...}}],
    "needs_clarification": false,
    "clarification_question": null
  }
- Clarification shape:
  {
    "tool_calls": [],
    "needs_clarification": true,
    "clarification_question": "single question"
  }
- Never include extra keys.

Safety constraints for planned args:
- seconds: >0 and <=30
- db: -24..24
- pan: -100..100
- duplicate count: 1..32
- add_fx type: eq|compressor|reverb
"""


EXPECTED_ARG_KEYS = {
    "fade_in": {"seconds"},
    "fade_out": {"seconds"},
    "cut_middle": {"seconds"},
    "trim_to_time_selection": set(),
    "split_at_cursor": set(),
    "duplicate": {"count"},
    "set_volume_delta": {"db"},
    "set_pan": {"pan"},
    "mute": set(),
    "unmute": set(),
    "solo": set(),
    "unsolo": set(),
    "add_fx": {"type"},
    "crossfade": {"seconds"},
}


def _is_number(value: Any) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool)


def _build_ctx_summary(ctx: dict[str, Any]) -> dict[str, Any]:
    selected_items = ctx.get("selected_items")
    selected_tracks = ctx.get("selected_tracks")
    selected_items = selected_items if isinstance(selected_items, list) else []
    selected_tracks = selected_tracks if isinstance(selected_tracks, list) else []

    summary: dict[str, Any] = {
        "selected_items_count": len(selected_items),
        "selected_tracks_count": len(selected_tracks),
        "has_time_selection": False,
        "time_selection": None,
        "cursor": float(ctx.get("cursor", 0.0)) if _is_number(ctx.get("cursor")) else 0.0,
    }

    starts = [float(i["start"]) for i in selected_items if isinstance(i, dict) and _is_number(i.get("start"))]
    ends = [float(i["end"]) for i in selected_items if isinstance(i, dict) and _is_number(i.get("end"))]
    if starts and ends:
        summary["selected_items_range"] = {"start": min(starts), "end": max(ends)}

    ts = ctx.get("time_selection")
    if isinstance(ts, dict) and _is_number(ts.get("start")) and _is_number(ts.get("end")):
        summary["has_time_selection"] = True
        summary["time_selection"] = {"start": float(ts["start"]), "end": float(ts["end"])}

    return summary


def _strip_code_fences(text: str) -> str:
    stripped = text.strip()
    if not stripped.startswith("```"):
        return stripped

    lines = stripped.splitlines()
    if not lines:
        return stripped
    if lines[0].startswith("```"):
        lines = lines[1:]
    if lines and lines[-1].strip() == "```":
        lines = lines[:-1]
    return "\n".join(lines).strip()


def _extract_json(text: str) -> dict[str, Any]:
    clean = _strip_code_fences(text)
    try:
        parsed = json.loads(clean)
    except json.JSONDecodeError:
        start = clean.find("{")
        end = clean.rfind("}")
        if start == -1 or end == -1 or end <= start:
            raise GeminiAgentError("Gemini returned non-JSON output.")
        try:
            parsed = json.loads(clean[start : end + 1])
        except json.JSONDecodeError as exc:
            raise GeminiAgentError(f"Gemini returned invalid JSON: {exc}") from exc
    if not isinstance(parsed, dict):
        raise GeminiAgentError("Gemini response must be a JSON object.")
    return parsed


def _enforce_plan_schema(plan: dict[str, Any]) -> dict[str, Any]:
    required_keys = {"tool_calls", "needs_clarification", "clarification_question"}
    if set(plan.keys()) != required_keys:
        raise GeminiAgentError("Gemini response keys are invalid.")

    tool_calls = plan.get("tool_calls")
    needs_clarification = plan.get("needs_clarification")
    clarification_question = plan.get("clarification_question")

    if not isinstance(needs_clarification, bool):
        raise GeminiAgentError("Gemini response: needs_clarification must be boolean.")
    if not isinstance(tool_calls, list):
        raise GeminiAgentError("Gemini response: tool_calls must be a list.")

    if needs_clarification:
        if tool_calls:
            raise GeminiAgentError("Gemini response: clarification cannot include tool_calls.")
        if not isinstance(clarification_question, str) or not clarification_question.strip():
            raise GeminiAgentError("Gemini response: clarification_question must be non-empty.")
        return {
            "tool_calls": [],
            "needs_clarification": True,
            "clarification_question": clarification_question.strip(),
        }

    if clarification_question is not None:
        raise GeminiAgentError("Gemini response: clarification_question must be null when not needed.")
    if not tool_calls:
        raise GeminiAgentError("Gemini response: tool_calls must not be empty.")

    normalized_calls = []
    for index, call in enumerate(tool_calls):
        if not isinstance(call, dict):
            raise GeminiAgentError(f"Gemini response: tool_call at index {index} is not an object.")
        if set(call.keys()) != {"name", "args"}:
            raise GeminiAgentError(f"Gemini response: tool_call at index {index} has invalid keys.")
        name = call.get("name")
        args = call.get("args")
        if not isinstance(name, str) or name not in WHITELISTED_TOOLS:
            raise GeminiAgentError(f"Gemini response: unknown tool {name!r}.")
        if not isinstance(args, dict):
            raise GeminiAgentError(f"Gemini response: args for {name} must be an object.")

        expected_keys = EXPECTED_ARG_KEYS[name]
        if set(args.keys()) != expected_keys:
            raise GeminiAgentError(f"Gemini response: args for {name} must have keys {sorted(expected_keys)}.")
        normalized_calls.append({"name": name, "args": args})

    return {"tool_calls": normalized_calls, "needs_clarification": False, "clarification_question": None}


def _extract_text_from_gemini_response(payload: dict[str, Any]) -> str:
    candidates = payload.get("candidates")
    if not isinstance(candidates, list) or not candidates:
        raise GeminiAgentError("Gemini returned no candidates.")

    parts = ((candidates[0] or {}).get("content") or {}).get("parts")
    if not isinstance(parts, list):
        raise GeminiAgentError("Gemini returned no content parts.")

    text_chunks = []
    for part in parts:
        if isinstance(part, dict) and isinstance(part.get("text"), str):
            text_chunks.append(part["text"])

    if not text_chunks:
        raise GeminiAgentError("Gemini returned no text output.")
    return "\n".join(text_chunks).strip()


def _call_gemini(user_text: str, ctx_summary: dict[str, Any], api_key: str) -> dict[str, Any]:
    model = os.getenv("GEMINI_MODEL", "gemini-2.0-flash")
    url = f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={api_key}"

    user_prompt = (
        "User request:\n"
        f"{user_text}\n\n"
        "Context summary:\n"
        f"{json.dumps(ctx_summary, ensure_ascii=True)}\n\n"
        "Return only the required JSON object."
    )

    payload = {
        "systemInstruction": {"parts": [{"text": SYSTEM_PROMPT}]},
        "contents": [{"role": "user", "parts": [{"text": user_prompt}]}],
        "generationConfig": {
            "temperature": 0,
            "responseMimeType": "application/json",
        },
    }

    request = urllib.request.Request(
        url=url,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )

    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            raw = response.read().decode("utf-8")
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        raise GeminiAgentError(f"Gemini API error ({exc.code}): {body}") from exc
    except urllib.error.URLError as exc:
        raise GeminiAgentError(f"Gemini API network error: {exc}") from exc

    try:
        parsed = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise GeminiAgentError(f"Gemini API returned invalid JSON: {exc}") from exc
    return parsed


def plan_tool_calls(user_text: str, ctx: dict[str, Any]) -> dict[str, Any]:
    cmd = (user_text or "").strip()
    if not cmd:
        raise GeminiAgentError("Command is empty.")

    api_key = os.getenv("GEMINI_API_KEY")
    if not api_key:
        raise GeminiNotConfiguredError(
            "Gemini is not configured. Set GEMINI_API_KEY and retry. "
            "Optional: set GEMINI_MODEL (default: gemini-2.0-flash)."
        )

    ctx_summary = _build_ctx_summary(ctx or {})
    raw_response = _call_gemini(cmd, ctx_summary, api_key)
    raw_text = _extract_text_from_gemini_response(raw_response)
    plan = _extract_json(raw_text)
    return _enforce_plan_schema(plan)
