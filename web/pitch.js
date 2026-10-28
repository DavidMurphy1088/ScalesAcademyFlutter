// SA Flutter - web microphone pitch detection.
// Called from Dart (lib/platform/pitch/web_pitch_source.dart) through window.flPitchStart / window.flPitchStop.
//
//  1. Opens the microphone with the browser's call processing turned OFF
//     (echo cancellation, noise suppression, auto gain) - the web equivalent of Android's UNPROCESSED source.
//  2. pitch_worklet.js collects 4096-sample blocks on the audio thread.
//  3. Each block: loudness (RMS) and pitch (YIN - same method and settings as the Android Yin.kt),
//     then onReading(frequency, amplitude, clarity) is called in Dart.

(function () {
  let context = null;
  let stream = null;
  let sourceNode = null;
  let workletNode = null;
  let silentGain = null;

  // ---------- YIN pitch detection (a copy of android/.../Yin.kt) ----------
  function makeYin(sampleRate, bufferSize, threshold) {
    const windowSize = bufferSize / 2;
    const maxTau = Math.min(windowSize, Math.floor(sampleRate / 26.0));   // lowest piano note A0 = 27.5 Hz
    const minTau = Math.max(2, Math.floor(sampleRate / 4500.0));      // highest piano note C8 = 4186 Hz
    const d = new Float32Array(maxTau);

    return function detect(buffer) {
      // 1. Difference function
      d[0] = 0;
      for (let tau = 1; tau < maxTau; tau++) {
        let sum = 0;
        for (let i = 0; i < windowSize; i++) {
          const delta = buffer[i] - buffer[i + tau];
          sum += delta * delta;
        }
        d[tau] = sum;
      }
      // 2. Cumulative mean normalised difference
      d[0] = 1;
      let runningSum = 0;
      for (let tau = 1; tau < maxTau; tau++) {
        runningSum += d[tau];
        d[tau] = runningSum === 0 ? 1 : (d[tau] * tau) / runningSum;
      }
      // 3. First dip below the threshold, followed down to its minimum
      let tauEstimate = -1;
      for (let tau = minTau; tau < maxTau; tau++) {
        if (d[tau] < threshold) {
          while (tau + 1 < maxTau && d[tau + 1] < d[tau]) tau++;
          tauEstimate = tau;
          break;
        }
      }
      if (tauEstimate === -1) return { frequency: -1, clarity: 0 };
      // 3b. Overtone check (same in Yin.kt, pitch.js and YinPitch.swift): a piano note's overtones repeat
      //     2x or 3x faster than the note, so the first dip found can be an overtone (e.g. E4's 3rd harmonic is B5).
      //     Only when the first dip is not already a near-perfect match (score above 0.05): if 2 or 3 times this
      //     delay lines up clearly better (score under 70% of it), the note is that lower one.
      //     (Tuned on synthetic piano tones: fixes E4 read as B5, and changes no correctly detected note.)
      //     A real higher note also lines up at 2x and 3x its delay, but no better, so it is left unchanged.
      const OVERTONE_RATIO = 0.7, OVERTONE_MIN_FIRST = 0.05;
      const firstDip = tauEstimate;
      for (let multiple = 2; multiple <= 3 && d[firstDip] > OVERTONE_MIN_FIRST; multiple++) {
        const from = firstDip * multiple - multiple;   // allow for the period not being a whole number of samples
        const to = firstDip * multiple + multiple;
        if (to >= maxTau) break;
        let tMin = from;
        for (let t = from; t <= to; t++) if (d[t] < d[tMin]) tMin = t;
        if (d[tMin] < d[firstDip] * OVERTONE_RATIO && d[tMin] < d[tauEstimate]) tauEstimate = tMin;
      }
      // 4. Parabolic interpolation for a more exact period
      let betterTau = tauEstimate;
      if (tauEstimate > 0 && tauEstimate < maxTau - 1) {
        const s0 = d[tauEstimate - 1], s1 = d[tauEstimate], s2 = d[tauEstimate + 1];
        const denominator = 2 * (2 * s1 - s2 - s0);
        if (denominator !== 0) betterTau = tauEstimate + (s2 - s0) / denominator;
      }
      const clarity = Math.min(1, Math.max(0, 1 - d[tauEstimate]));
      return { frequency: sampleRate / betterTau, clarity: clarity };
    };
  }

  function stop() {
    try { if (workletNode) { workletNode.port.onmessage = null; workletNode.disconnect(); } } catch (e) {}
    try { if (sourceNode) sourceNode.disconnect(); } catch (e) {}
    try { if (silentGain) silentGain.disconnect(); } catch (e) {}
    if (stream) stream.getTracks().forEach(function (t) { t.stop(); });
    if (context) context.close().catch(function () {});
    context = null; stream = null; sourceNode = null; workletNode = null; silentGain = null;
  }

  // Returns a JSON string: {"started": true/false, "detail": "..."}
  window.flPitchStart = async function (onReading) {
    stop();
    try {
      if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia || !window.AudioWorkletNode) {
        return JSON.stringify({ started: false, detail: 'This browser can\'t use the microphone here (it needs a modern browser and HTTPS or localhost).' });
      }
      // Create the audio context first, while still inside the button tap (browsers, Safari especially, require this)
      context = new AudioContext();

      stream = await navigator.mediaDevices.getUserMedia({
        audio: { echoCancellation: false, noiseSuppression: false, autoGainControl: false, channelCount: 1 }
      });

      await context.audioWorklet.addModule('pitch_worklet.js');
      sourceNode = context.createMediaStreamSource(stream);
      workletNode = new AudioWorkletNode(context, 'fl-pitch-processor', { numberOfInputs: 1, numberOfOutputs: 1 });

      const yin = makeYin(context.sampleRate, 4096, 0.15);
      workletNode.port.onmessage = function (event) {
        const block = event.data;
        let sumSquares = 0;
        for (let i = 0; i < block.length; i++) sumSquares += block[i] * block[i];
        const amplitude = Math.sqrt(sumSquares / block.length);
        const pitch = yin(block);
        onReading(pitch.frequency, amplitude, pitch.clarity);
      };

      // The worklet must be connected through to the output to keep running; volume 0 so the
      // microphone is never heard (same idea as the "silencer" in Scales Academy's AudioManager)
      silentGain = context.createGain();
      silentGain.gain.value = 0;
      sourceNode.connect(workletNode);
      workletNode.connect(silentGain);
      silentGain.connect(context.destination);

      if (context.state === 'suspended') await context.resume();

      const s = stream.getAudioTracks()[0].getSettings();
      const processing = [];
      if (s.echoCancellation) processing.push('echo cancellation');
      if (s.noiseSuppression) processing.push('noise suppression');
      if (s.autoGainControl) processing.push('auto gain');
      const detail = 'Browser microphone, ' + context.sampleRate + ' Hz, ' +
        (processing.length === 0 ? 'no call processing' : 'browser still applying: ' + processing.join(', '));
      return JSON.stringify({ started: true, detail: detail });
    } catch (e) {
      stop();
      const name = e && e.name ? e.name : '';
      const msg = name === 'NotAllowedError' ? 'Microphone permission was not given' :
                  name === 'NotFoundError' ? 'No microphone was found' :
                  'Could not start the microphone: ' + (e && e.message ? e.message : e);
      return JSON.stringify({ started: false, detail: msg });
    }
  };

  window.flPitchStop = function () {
    stop();
  };
})();
