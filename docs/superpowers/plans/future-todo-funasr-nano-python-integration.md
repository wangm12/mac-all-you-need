# Future Todo: Fun-ASR-Nano Python Integration

**Status:** Deferred — implement after SenseVoice (mlx-audio-swift) is shipped and validated.

**Why defer:** Fun-ASR-Nano requires a Python runtime bridge. SenseVoice via mlx-audio-swift gives us non-autoregressive ASR natively with no Python dependency. Ship that first, then evaluate whether the accuracy lift from Fun-ASR-Nano justifies the Python integration complexity.

---

## What Fun-ASR-Nano is

**Fun-ASR-Nano** = SenseVoice encoder (non-autoregressive, fast) + Qwen3-0.6B LLM decoder.

Unlike our AI cleanup which sees only text, the Qwen3 decoder sees **audio embeddings + CTC predictions simultaneously**. It can resolve same-sound ambiguities ("期" vs "其") using acoustic context that a pure text LLM cannot. This makes it fundamentally more accurate than: fast ASR → text LLM cleanup.

Benchmark: 31 languages, better CER than SenseVoice alone on noisy/domain-specific audio. Uses RL to prevent hallucination.

Model: `FunAudioLLM/Fun-ASR-Nano-2512` on ModelScope/HuggingFace (~600MB encoder + ~600MB Qwen3 decoder).

---

## Architecture plan (when ready to implement)

### Option A: Local Python subprocess (recommended)

```
Swift app
  ↓ audio bytes (stdin or temp file)
Python subprocess (funasr server)
  ↓ JSON text response
Swift app → paste
```

1. **Bundle a minimal Python environment** using `python-build-standalone` or require the user to have Python 3.10+ in PATH / brew.
2. **Ship a small `funasr_server.py`** inside the app bundle that:
   - Loads `FunAudioLLM/Fun-ASR-Nano-2512` on first run (model cached to App Group dir)
   - Listens on a local Unix socket or stdio
   - Accepts 16kHz PCM bytes, returns JSON `{text: "...", language: "zh"}`
3. **Swift side**: new `FunASRNanoEngine` actor that spawns/manages the Python subprocess, writes audio, reads JSON response.
4. **Startup cost**: ~3-5s on first run for model load. Keep the subprocess alive between dictations. Restart if it crashes.

### Option B: Run a local funasr-server (user sets up)

User installs `pip install funasr` and runs `funasr-server` manually. App connects to `http://localhost:8000` with OpenAI-compatible API. Zero integration complexity, but requires user setup.

---

## Steps to implement (high level)

1. **Decide Python distribution strategy**: bundle `python-build-standalone` (~50MB) or require system Python. Bundling is cleaner UX but larger app size.

2. **Create `funasr_server.py`** in `Resources/`:
   ```python
   from funasr import AutoModel
   import sys, json, struct

   model = AutoModel(model="FunAudioLLM/Fun-ASR-Nano-2512", device="cpu")

   for line in sys.stdin:
       audio_path = json.loads(line)["path"]
       result = model.generate(input=audio_path, language="auto")
       print(json.dumps({"text": result[0]["text"]}), flush=True)
   ```

3. **Create `FunASRNanoEngine.swift`** actor:
   - On first `transcribe()`: spawn Python subprocess, wait for ready signal
   - Write audio to temp WAV file, send path via stdin JSON
   - Read response JSON, return `VoiceTranscriptionResult`
   - Keep process alive; restart on crash

4. **Add to VoiceASRModelID** as `case funASRNano = "fun-asr-nano"` with runtime `.funASRNano` (Python-backed).

5. **Model management**: model is ~1.2GB, downloaded by the Python script on first use (FunASR's `AutoModel` handles this), cached to `~/Library/Application Support/funasr/`.

6. **Settings UI**: show "Fun-ASR-Nano" in Models picker with "Requires Python 3.10+" label and a "Setup" button that opens a terminal or shows install instructions.

---

## Key unknowns to resolve before implementing

- [ ] Which Python distribution to bundle (python-build-standalone vs system Python vs pyenv)
- [ ] macOS sandboxing — can we spawn a subprocess? (The app currently has `com.apple.security.cs.allow-jit` entitlement; subprocess spawning should work)
- [ ] Cold start latency: can we hide the 3-5s model load in the background while the user speaks?
- [ ] Whether `cpu` inference speed on Apple Silicon is fast enough (~2-5s for 5s clip estimated)
- [ ] Apple Silicon MPS/ANE acceleration for PyTorch — does FunASR use it automatically?

---

## Decision gate

**Implement when:**
- SenseVoice + AI cleanup is shipped and users report accuracy issues on noisy/domain-specific audio
- OR a user explicitly requests higher accuracy at the cost of Python setup

**Skip if:**
- SenseVoice + AI cleanup achieves acceptable accuracy for zh-en dictation
- Python subprocess complexity is not justified by the accuracy delta
