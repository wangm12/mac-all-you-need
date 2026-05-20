type VoiceWaveformOptions = {
  silenceDb?: number;
  maxDb?: number;
  voiceThreshold?: number;
  attack?: number;
  release?: number;
};

const clamp = (value: number, min = 0, max = 1) => Math.max(min, Math.min(max, value));

/**
 * Drives the Listening pill waveform from live microphone amplitude.
 * The function only reads amplitude locally for UI animation.
 */
export async function attachVoiceReactiveWaveform(
  pill: HTMLElement,
  stream: MediaStream,
  options: VoiceWaveformOptions = {}
): Promise<() => void> {
  const bars = Array.from(pill.querySelectorAll<HTMLElement>('[data-wave-bar], .voice-bar, .processing-pill__waveform-bar'));
  if (bars.length === 0) {
    throw new Error('No waveform bar elements found. Use [data-wave-bar], .voice-bar, or .processing-pill__waveform-bar.');
  }

  const audioContext = new AudioContext();
  const source = audioContext.createMediaStreamSource(stream);
  const analyser = audioContext.createAnalyser();

  analyser.fftSize = 1024;
  analyser.smoothingTimeConstant = 0.25;
  source.connect(analyser);

  const samples = new Uint8Array(analyser.fftSize);

  const silenceDb = options.silenceDb ?? -60;
  const maxDb = options.maxDb ?? -12;
  const voiceThreshold = options.voiceThreshold ?? 0.16;
  const attack = options.attack ?? 0.42;
  const release = options.release ?? 0.12;

  let envelope = 0;
  let raf = 0;
  let disposed = false;

  function readRmsDb(): number {
    analyser.getByteTimeDomainData(samples);
    let sum = 0;
    for (let i = 0; i < samples.length; i += 1) {
      const centered = (samples[i] - 128) / 128;
      sum += centered * centered;
    }
    const rms = Math.sqrt(sum / samples.length);
    return 20 * Math.log10(Math.max(rms, 0.000001));
  }

  function update(): void {
    const db = readRmsDb();
    const rawAmplitude = clamp((db - silenceDb) / (maxDb - silenceDb));
    const smoothing = rawAmplitude > envelope ? attack : release;
    envelope += (rawAmplitude - envelope) * smoothing;

    const voiceActive = envelope > voiceThreshold;
    pill.dataset.voiceActive = voiceActive ? 'true' : 'false';
    pill.dataset.audioReactive = 'true';

    const base = voiceActive ? 0.22 : 0.16;
    const shape = [0.52, 0.82, 1.0, 0.74, 0.9, 0.58];

    bars.forEach((bar, index) => {
      const multiplier = shape[index % shape.length];
      const scale = clamp(base + envelope * multiplier, 0.18, 1);
      const value = scale.toFixed(3);
      bar.style.setProperty('--bar-scale', value);
      bar.style.setProperty('--bar-opacity', (0.55 + envelope * 0.45).toFixed(3));
      pill.style.setProperty(`--voice-bar-${index + 1}`, value);
    });

    if (!disposed) {
      raf = requestAnimationFrame(update);
    }
  }

  update();

  return () => {
    disposed = true;
    cancelAnimationFrame(raf);
    source.disconnect();
    void audioContext.close();
    pill.dataset.voiceActive = 'false';
  };
}
