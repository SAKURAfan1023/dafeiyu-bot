"""Offline MLX Qwen worker: incremental PCM on stdout; diagnostics on stderr."""

import base64
import contextlib
import json
import sys
from pathlib import Path
from time import monotonic


def main():
    model_path = Path(sys.argv[1])
    voice = json.loads(Path(sys.argv[2]).read_text()) if len(sys.argv) > 2 else {}
    with contextlib.redirect_stdout(sys.stderr):
        import mlx.core as mx
        import numpy as np
        from mlx_audio.tts.utils import load_model

        model = load_model(str(model_path))
        design = model.config.tts_model_type == "voice_design"
        generate = model.generate_voice_design if design else model.generate_custom_voice
        options = {
            "instruct": voice.get(
                "instruct", "清晰、轻快、亲切的年轻中文女声，自然聊天，语速适中，句间自然停顿。"
            ),
            "language": "Chinese",
            "stream": True,
            "streaming_interval": 0.32,
            "verbose": False,
        }
        if not design:
            options["speaker"] = voice.get("speaker", "Vivian")
        # Compile the first codec/talker step before accepting speech, without playing audio.
        warm = generate(
            text="你好。",
            max_tokens=32,
            **options,
        )
        first = next(warm)
        mx.eval(first.audio)
        warm.close()
    print(json.dumps({"type": "ready", "protocol": 2, "sample_rate": 24000}), flush=True)
    for line in sys.stdin:
        request = json.loads(line)
        key = request["id"]
        if len(key) != 32 or any(c not in "0123456789abcdef" for c in key):
            raise ValueError("Invalid utterance identity")
        started = monotonic()
        count = samples = tokens = 0
        peak = 0.0
        try:
            with contextlib.redirect_stdout(sys.stderr):
                if voice.get("seed") is not None:
                    mx.random.seed(voice["seed"])
                generated = generate(
                    text=request["text"],
                    max_tokens=720,
                    temperature=0.85,
                    top_p=0.95,
                    **options,
                )
            while True:
                with contextlib.redirect_stdout(sys.stderr):
                    result = next(generated, None)
                if result is None:
                    break
                wave = np.asarray(result.audio, dtype=np.float32)
                if result.sample_rate != 24000 or wave.ndim != 1 or not np.isfinite(wave).all():
                    raise ValueError("Invalid waveform")
                if not 0 < len(wave) <= 16384:
                    raise ValueError("Unbounded chunk")
                peak = max(peak, float(np.max(np.abs(wave))))
                samples += len(wave)
                tokens += result.token_count
                if samples >= 58 * 24000 or tokens >= 720:
                    raise ValueError("Speech limit reached")
                # Fixed gain across chunks; never independently normalize each packet.
                pcm = (np.clip(wave * 0.9, -0.98, 0.98) * 32767).astype("<i2").tobytes()
                print(
                    json.dumps(
                        {
                            "id": key,
                            "type": "chunk",
                            "index": count,
                            "pcm": base64.b64encode(pcm).decode(),
                            "sample_rate": 24000,
                        }
                    ),
                    flush=True,
                )
                count += 1
            if not count or peak < 1e-5:
                raise ValueError("Empty speech")
            terminal = {
                "id": key,
                "type": "end",
                "ok": True,
                "chunks": count,
                "seconds": samples / 24000,
                "synthesis_seconds": monotonic() - started,
            }
        except Exception:
            terminal = {"id": key, "type": "end", "ok": False}
        print(json.dumps(terminal), flush=True)


if __name__ == "__main__":
    main()
