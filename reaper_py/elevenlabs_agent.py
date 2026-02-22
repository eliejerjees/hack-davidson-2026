from __future__ import annotations

import importlib
import json
import os
from pathlib import Path

try:
    import requests
except ImportError:  # pragma: no cover - dependency guard
    requests = None


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


class ElevenLabsError(RuntimeError):
    pass


def _require_api_key() -> str:
    api_key = os.getenv("ELEVENLABS_API_KEY", "").strip()
    if not api_key:
        raise ElevenLabsError("Missing ELEVENLABS_API_KEY in environment.")
    return api_key


def _discover_default_voice_id(api_key: str) -> str | None:
    if requests is None:
        return None
    url = "https://api.elevenlabs.io/v1/voices"
    headers = {"xi-api-key": api_key}
    try:
        response = requests.get(url, headers=headers, timeout=15)
    except requests.RequestException:
        return None
    if response.status_code >= 400:
        return None
    try:
        payload = response.json()
    except Exception:
        return None
    if not isinstance(payload, dict):
        return None
    voices = payload.get("voices")
    if not isinstance(voices, list):
        return None
    for voice in voices:
        if not isinstance(voice, dict):
            continue
        voice_id = voice.get("voice_id") or voice.get("id")
        if isinstance(voice_id, str) and voice_id.strip():
            return voice_id.strip()
    return None


def _require_voice_id(voice_id: str | None, api_key: str) -> str:
    value = (voice_id or os.getenv("ELEVENLABS_VOICE_ID", "")).strip()
    if value:
        return value

    discovered = _discover_default_voice_id(api_key)
    if discovered:
        return discovered

    raise ElevenLabsError("Missing ELEVENLABS_VOICE_ID and failed to discover a default ElevenLabs voice.")


def _extract_error_text(response: requests.Response) -> str:
    try:
        payload = response.json()
    except Exception:
        body = response.text.strip()
        return body[:200] if body else "unknown error"

    if isinstance(payload, dict):
        detail = payload.get("detail")
        if isinstance(detail, str) and detail.strip():
            return detail.strip()
        message = payload.get("message")
        if isinstance(message, str) and message.strip():
            return message.strip()
        return json.dumps(payload, ensure_ascii=False)[:200]
    return str(payload)[:200]


def _join_word_tokens(tokens: list[str]) -> str:
    punctuation = {".", ",", "!", "?", ";", ":"}
    pieces: list[str] = []
    for token in tokens:
        value = token.strip()
        if not value:
            continue
        if pieces and value in punctuation:
            pieces[-1] = pieces[-1] + value
        else:
            pieces.append(value)
    return " ".join(pieces).strip()


def _coerce_text(value: object) -> str | None:
    if isinstance(value, str):
        text = value.strip()
        return text or None
    if isinstance(value, list):
        parts: list[str] = []
        for item in value:
            item_text = _coerce_text(item)
            if item_text:
                parts.append(item_text)
        merged = " ".join(parts).strip()
        return merged or None
    if isinstance(value, dict):
        for key in ("text", "word", "token", "value", "content", "transcript"):
            nested = _coerce_text(value.get(key))
            if nested:
                return nested
    return None


def _extract_text_from_words(words: object) -> str | None:
    if not isinstance(words, list):
        return None

    tokens: list[str] = []
    for word in words:
        if isinstance(word, str):
            tokens.append(word)
            continue
        if not isinstance(word, dict):
            continue

        for key in ("text", "word", "token", "value", "content"):
            value = _coerce_text(word.get(key))
            if value:
                tokens.append(value)
                break

    joined = _join_word_tokens(tokens)
    return joined or None


def _extract_text_from_segments(segments: object) -> str | None:
    if not isinstance(segments, list):
        return None

    parts: list[str] = []
    for segment in segments:
        if not isinstance(segment, dict):
            continue
        value = segment.get("text")
        if isinstance(value, str) and value.strip():
            parts.append(value.strip())

    merged = " ".join(parts).strip()
    return merged or None


def _extract_transcript(payload: dict) -> str | None:
    direct_keys = (
        "text",
        "transcript",
        "transcription",
        "normalized_text",
        "raw_text",
        "utterance",
    )
    for key in direct_keys:
        value = _coerce_text(payload.get(key))
        if value:
            return value

    from_words = _extract_text_from_words(payload.get("words"))
    if from_words:
        return from_words

    from_segments = _extract_text_from_segments(payload.get("segments"))
    if from_segments:
        return from_segments

    for nested_key in ("data", "result", "output"):
        nested = payload.get(nested_key)
        if isinstance(nested, dict):
            nested_text = _extract_transcript(nested)
            if nested_text:
                return nested_text

    # Final fallback: recursively search any nested text-like fields.
    generic = _coerce_text(payload)
    if generic:
        return generic

    return None


def stt_transcribe(audio_path: str) -> str:
    if requests is None:
        raise ElevenLabsError("Missing dependency: requests. Install with: pip install -r requirements.txt")

    api_key = _require_api_key()
    path = Path(audio_path)
    if not path.exists():
        raise ElevenLabsError(f"Audio file not found: {audio_path}")

    url = "https://api.elevenlabs.io/v1/speech-to-text"
    headers = {"xi-api-key": api_key}
    data = {"model_id": os.getenv("ELEVENLABS_STT_MODEL", "scribe_v1")}

    try:
        with path.open("rb") as audio_file:
            files = {"file": (path.name, audio_file, "audio/wav")}
            response = requests.post(url, headers=headers, data=data, files=files, timeout=15)
    except requests.RequestException as exc:
        raise ElevenLabsError(f"STT request failed: {exc}") from exc

    if response.status_code >= 400:
        raise ElevenLabsError(f"STT HTTP {response.status_code}: {_extract_error_text(response)}")

    try:
        payload = response.json()
    except Exception as exc:
        raise ElevenLabsError("STT response was not valid JSON.") from exc

    if not isinstance(payload, dict):
        raise ElevenLabsError("STT response JSON was not an object.")

    text = _extract_transcript(payload)
    if text:
        return text

    detail = payload.get("detail")
    if isinstance(detail, str) and detail.strip():
        raise ElevenLabsError(f"STT transcription unavailable: {detail.strip()}")

    message = payload.get("message")
    if isinstance(message, str) and message.strip():
        raise ElevenLabsError(f"STT transcription unavailable: {message.strip()}")

    response_keys = ", ".join(sorted(str(key) for key in payload.keys()))
    raise ElevenLabsError(
        "STT response did not include transcript text. "
        f"Response keys: [{response_keys}]"
    )


def tts_synthesize(text: str, voice_id: str | None = None) -> bytes:
    if requests is None:
        raise ElevenLabsError("Missing dependency: requests. Install with: pip install -r requirements.txt")

    api_key = _require_api_key()
    resolved_voice_id = _require_voice_id(voice_id, api_key)
    spoken_text = text.strip()
    if not spoken_text:
        raise ElevenLabsError("TTS text is empty.")

    url = f"https://api.elevenlabs.io/v1/text-to-speech/{resolved_voice_id}"
    headers = {
        "xi-api-key": api_key,
        "Content-Type": "application/json",
        "Accept": "audio/mpeg",
    }
    payload = {
        "text": spoken_text,
        "model_id": os.getenv("ELEVENLABS_TTS_MODEL", "eleven_multilingual_v2"),
        "voice_settings": {"stability": 0.45, "similarity_boost": 0.75},
    }

    try:
        response = requests.post(url, headers=headers, json=payload, timeout=15)
    except requests.RequestException as exc:
        raise ElevenLabsError(f"TTS request failed: {exc}") from exc

    if response.status_code >= 400:
        raise ElevenLabsError(f"TTS HTTP {response.status_code}: {_extract_error_text(response)}")

    audio = response.content
    if not audio:
        raise ElevenLabsError("TTS response had empty audio content.")
    return audio
