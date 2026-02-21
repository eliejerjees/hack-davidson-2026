from __future__ import annotations

import copy
import json
import sys
from pathlib import Path
from typing import Any

# Ensure "python3 reaper_py/bridge.py ..." can import the package.
ROOT_DIR = Path(__file__).resolve().parents[1]
if str(ROOT_DIR) not in sys.path:
    sys.path.insert(0, str(ROOT_DIR))

from reaper_py.gemini_agent import GeminiAgentError, GeminiNotConfiguredError, plan_tool_calls
from reaper_py.preview import render_preview_text
from reaper_py.validate import suggestion_for_error, validate_tool_plan


def _response(
    *,
    ok: bool,
    needs_clarification: bool = False,
    clarification_question: str | None = None,
    error: str | None = None,
    preview: str = "",
    tool_calls: list[dict[str, Any]] | None = None,
) -> dict[str, Any]:
    return {
        "ok": ok,
        "needs_clarification": needs_clarification,
        "clarification_question": clarification_question,
        "error": error,
        "preview": preview,
        "tool_calls": tool_calls or [],
    }


def _safe_json_load(text: str) -> dict[str, Any]:
    payload = json.loads(text)
    if not isinstance(payload, dict):
        raise ValueError("Input JSON must be an object.")
    return payload


def _normalize_target(value: Any) -> str | None:
    if not isinstance(value, str):
        return None
    v = value.strip().lower()
    if v in {"clip", "clips"}:
        return "clips"
    if v in {"track", "tracks"}:
        return "tracks"
    return None


def _normalize_conversation_hint(value: Any) -> dict[str, str] | None:
    if not isinstance(value, dict):
        return None

    hint: dict[str, str] = {}
    for key in ("last_intent", "pending_intent"):
        raw = value.get(key)
        if isinstance(raw, str):
            text = raw.strip()
            if text:
                hint[key] = text
    return hint or None


def _target_error(target: str) -> str:
    if target == "tracks":
        return "No selected tracks. Select a track in REAPER."
    return "No selected clips. Select a clip in REAPER."


def _is_target_selection_error(error: str, target: str) -> bool:
    lowered = error.lower()
    if target == "tracks":
        return "selected track" in lowered
    return "selected clip" in lowered


def _is_target_clarification(question: str) -> bool:
    lowered = question.lower()
    has_clips = "clip" in lowered
    has_tracks = "track" in lowered
    return has_clips and has_tracks


def _ctx_for_target(ctx: dict[str, Any], forced_target: str | None) -> dict[str, Any]:
    planning_ctx = copy.deepcopy(ctx)
    if forced_target == "tracks":
        planning_ctx["selected_items"] = []
    elif forced_target == "clips":
        planning_ctx["selected_tracks"] = []
    if forced_target:
        planning_ctx["forced_target"] = forced_target
    return planning_ctx


def _cmd_for_target(command: str, forced_target: str | None) -> str:
    if forced_target == "tracks":
        return f"{command}\nUser clarified target: selected tracks."
    if forced_target == "clips":
        return f"{command}\nUser clarified target: selected clips."
    return command


def process_payload(payload: dict[str, Any]) -> dict[str, Any]:
    command = payload.get("cmd")
    ctx = payload.get("ctx")

    if not isinstance(command, str) or not command.strip():
        return _response(ok=False, error="Input error: cmd must be a non-empty string.")
    if not isinstance(ctx, dict):
        return _response(ok=False, error="Input error: ctx must be an object.")

    forced_target = _normalize_target(payload.get("forced_target"))
    clarification_answer = _normalize_target(payload.get("clarification_answer"))
    if forced_target is None and clarification_answer is not None:
        forced_target = clarification_answer
    conversation_hint = _normalize_conversation_hint(payload.get("conversation_hint"))

    planning_ctx = _ctx_for_target(ctx, forced_target)
    if conversation_hint:
        planning_ctx["conversation_hint"] = conversation_hint
    planning_cmd = _cmd_for_target(command.strip(), forced_target)

    try:
        plan = plan_tool_calls(planning_cmd, planning_ctx)
    except GeminiNotConfiguredError as exc:
        return _response(ok=False, error=str(exc))
    except GeminiAgentError as exc:
        return _response(ok=False, error=f"Gemini planning error: {exc}")
    except Exception as exc:  # guardrail: always return JSON
        return _response(ok=False, error=f"Unexpected planning error: {exc}")

    if plan["needs_clarification"]:
        if forced_target is not None:
            question = plan.get("clarification_question") or ""
            if isinstance(question, str) and _is_target_clarification(question):
                return _response(ok=False, needs_clarification=False, error=_target_error(forced_target))
            return _response(
                ok=False,
                needs_clarification=False,
                error="Could not resolve command after clarification. Try a more specific command.",
            )
        return _response(
            ok=True,
            needs_clarification=True,
            clarification_question=plan["clarification_question"],
            preview="Clarification needed before generating a preview.",
            tool_calls=[],
        )

    ok, validation_error = validate_tool_plan(plan, planning_ctx)
    if not ok:
        if forced_target is not None:
            if validation_error and _is_target_selection_error(validation_error, forced_target):
                return _response(ok=False, needs_clarification=False, error=_target_error(forced_target))
            return _response(ok=False, error=f"Validation error: {validation_error}")
        clarification = suggestion_for_error(validation_error or "", planning_ctx)
        if clarification:
            return _response(
                ok=True,
                needs_clarification=True,
                clarification_question=clarification,
                preview="Clarification needed before generating a preview.",
                tool_calls=[],
            )
        return _response(ok=False, error=f"Validation error: {validation_error}")

    tool_calls = plan["tool_calls"]
    preview_text = render_preview_text(tool_calls, planning_ctx)
    return _response(ok=True, preview=preview_text, tool_calls=tool_calls)


def _read_input(path: str | None) -> dict[str, Any]:
    if path:
        return _safe_json_load(Path(path).read_text(encoding="utf-8"))
    return _safe_json_load(sys.stdin.read())


def _write_output(data: dict[str, Any], path: str | None) -> None:
    serialized = json.dumps(data, ensure_ascii=False)
    if path:
        Path(path).write_text(serialized, encoding="utf-8")
        return
    sys.stdout.write(serialized)


def main() -> int:
    input_path = None
    output_path = None

    if len(sys.argv) == 3:
        input_path = sys.argv[1]
        output_path = sys.argv[2]
    elif len(sys.argv) != 1:
        fallback = _response(ok=False, error="Usage: python3 -m reaper_py.bridge <input.json> <output.json>")
        _write_output(fallback, None)
        return 1

    try:
        payload = _read_input(input_path)
        response = process_payload(payload)
    except json.JSONDecodeError as exc:
        response = _response(ok=False, error=f"Invalid JSON input: {exc}")
    except FileNotFoundError as exc:
        response = _response(ok=False, error=f"Input file error: {exc}")
    except Exception as exc:  # guardrail: always return JSON
        response = _response(ok=False, error=f"Bridge failure: {exc}")

    try:
        _write_output(response, output_path)
    except Exception:
        if output_path:
            sys.stdout.write(json.dumps(_response(ok=False, error="Bridge failed to write output.")))
            return 1
        return 1
    return 0 if response.get("ok") else 1


if __name__ == "__main__":
    raise SystemExit(main())
