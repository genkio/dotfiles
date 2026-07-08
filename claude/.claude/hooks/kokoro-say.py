#!/Users/ji/.venvs/kokoro-tts/bin/python
# Speaks the text file given as argv[1]. execv so this pid IS the player:
# the shh alias and speak-reply's supersede-kill only track one pid.
# Any failure falls back to plain `say` on the same file.
#
# New machine setup (venv + weights are machine-local, not in dotfiles):
#   uv venv --python 3.12 ~/.venvs/kokoro-tts
#   VIRTUAL_ENV=~/.venvs/kokoro-tts uv pip install kokoro-onnx soundfile
#   model.onnx + voices.bin -> ~/.local/share/kokoro
#   (github.com/thewh1teagle/kokoro-onnx releases, model-files-v1.0)
import os
import sys
import tempfile

text_path = sys.argv[1]

try:
    import soundfile as sf
    from kokoro_onnx import Kokoro

    share = os.path.expanduser("~/.local/share/kokoro")
    kokoro = Kokoro(f"{share}/model.onnx", f"{share}/voices.bin")
    with open(text_path) as f:
        text = f.read()
    samples, sr = kokoro.create(
        text,
        voice=os.environ.get("CLAUDE_TTS_KOKORO_VOICE", "af_heart"),
        speed=float(os.environ.get("CLAUDE_TTS_KOKORO_SPEED", "1.1")),
    )
    wav = os.path.join(tempfile.gettempdir(), "claude-tts.wav")
    sf.write(wav, samples, sr)
    os.execv("/usr/bin/afplay", ["afplay", wav])
except Exception:
    os.execv(
        "/usr/bin/say",
        [
            "say",
            "-v", os.environ.get("CLAUDE_TTS_VOICE", "Samantha"),
            "-r", os.environ.get("CLAUDE_TTS_RATE", "200"),
            "-f", text_path,
        ],
    )
