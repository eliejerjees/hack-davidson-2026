from __future__ import annotations

import json
import math
import struct
import sys
import wave
from pathlib import Path

# Ensure direct script execution can import reaper_py package.
ROOT_DIR = Path(__file__).resolve().parents[1]
if str(ROOT_DIR) not in sys.path:
    sys.path.insert(0, str(ROOT_DIR))

from reaper_py.elevenlabs_agent import ElevenLabsError, stt_transcribe, tts_synthesize


def _write_json(path: Path, payload: dict) -> None:
    path.write_text(json.dumps(payload, ensure_ascii=False), encoding="utf-8")


def _analyze_wav_signal(path: Path) -> tuple[bool, str | None]:
    try:
        with wave.open(str(path), "rb") as wav:
            sample_width = wav.getsampwidth()
            frame_rate = wav.getframerate()
            frame_count = wav.getnframes()

            if sample_width <= 0 or frame_rate <= 0 or frame_count <= 0:
                return False, "Recorded audio was empty."

            duration = frame_count / float(frame_rate)
            if duration < 0.25:
                return False, "Recording was too short. Hold recording a bit longer before stopping."

            frames = wav.readframes(frame_count)
    except wave.Error:
        # If it's not parseable WAV, let the remote STT attempt decide.
        return True, None
    except Exception as exc:
        return False, f"Failed to inspect recorded audio: {exc}"

    if not frames:
        return False, "Recorded audio was empty."

    max_abs_value = (1 << (sample_width * 8 - 1)) - 1 if sample_width in {1, 2, 3, 4} else None
    if max_abs_value is None or max_abs_value <= 0:
        return True, None

    try:
        if sample_width == 1:
            samples = [byte - 128 for byte in frames]
        elif sample_width == 2:
            count = len(frames) // 2
            samples = struct.unpack("<" + ("h" * count), frames[: count * 2])
        elif sample_width == 3:
            samples_list = []
            for i in range(0, len(frames) - 2, 3):
                raw = frames[i] | (frames[i + 1] << 8) | (frames[i + 2] << 16)
                if raw & 0x800000:
                    raw -= 1 << 24
                samples_list.append(raw)
            samples = samples_list
        else:  # sample_width == 4
            count = len(frames) // 4
            samples = struct.unpack("<" + ("i" * count), frames[: count * 4])
    except Exception:
        return True, None

    if not samples:
        return False, "Recorded audio was empty."

    abs_samples = [abs(int(sample)) for sample in samples]
    peak = max(abs_samples)
    mean_square = sum(float(sample) * float(sample) for sample in samples) / float(len(samples))
    rms = math.sqrt(mean_square)

    peak_ratio = peak / float(max_abs_value)
    rms_ratio = rms / float(max_abs_value)

    # Skip paid STT call when capture is effectively silent.
    if peak_ratio < 0.0002 and rms_ratio < 0.00005:
        return False, "No speech detected in recording. Check input device and mic permissions."
    return True, None


def _stt(input_wav: Path, output_json: Path) -> int:
    if not input_wav.exists():
        _write_json(output_json, {"ok": False, "text": "", "error": f"Input audio not found: {input_wav}"})
        return 1

    has_signal, signal_error = _analyze_wav_signal(input_wav)
    if not has_signal:
        _write_json(output_json, {"ok": False, "text": "", "error": signal_error or "No usable speech in recording."})
        return 1

    try:
        text = stt_transcribe(str(input_wav))
    except (ElevenLabsError, RuntimeError) as exc:
        _write_json(output_json, {"ok": False, "text": "", "error": str(exc)})
        return 1
    except Exception as exc:
        _write_json(output_json, {"ok": False, "text": "", "error": f"Unexpected STT error: {exc}"})
        return 1

    _write_json(output_json, {"ok": True, "text": text, "error": None})
    return 0


def _tts(input_text_file: Path, output_mp3_path: Path, voice_id: str | None) -> int:
    if not input_text_file.exists():
        sys.stderr.write(f"Input text file not found: {input_text_file}\n")
        return 1

    text = input_text_file.read_text(encoding="utf-8").strip()
    if not text:
        sys.stderr.write("Input text file is empty.\n")
        return 1

    try:
        audio = tts_synthesize(text, voice_id=voice_id)
    except (ElevenLabsError, RuntimeError) as exc:
        sys.stderr.write(f"TTS error: {exc}\n")
        return 1
    except Exception as exc:
        sys.stderr.write(f"Unexpected TTS error: {exc}\n")
        return 1

    output_mp3_path.write_bytes(audio)
    return 0


def main() -> int:
    if len(sys.argv) < 2:
        sys.stderr.write("Usage:\n")
        sys.stderr.write("  python -m reaper_py.speech_bridge stt <input_wav> <output_json>\n")
        sys.stderr.write("  python -m reaper_py.speech_bridge tts <input_text_file> <output_mp3_path> [voice_id]\n")
        return 1

    mode = sys.argv[1].strip().lower()
    if mode == "stt":
        if len(sys.argv) != 4:
            sys.stderr.write("Usage: python -m reaper_py.speech_bridge stt <input_wav> <output_json>\n")
            return 1
        return _stt(Path(sys.argv[2]), Path(sys.argv[3]))

    if mode == "tts":
        if len(sys.argv) not in {4, 5}:
            sys.stderr.write("Usage: python -m reaper_py.speech_bridge tts <input_text_file> <output_mp3_path> [voice_id]\n")
            return 1
        voice_id = sys.argv[4] if len(sys.argv) == 5 else None
        return _tts(Path(sys.argv[2]), Path(sys.argv[3]), voice_id)

    sys.stderr.write(f"Unknown mode: {mode}\n")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
