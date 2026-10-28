// SA Flutter - web microphone capture.
// Runs on the browser's audio thread. Collects microphone samples into blocks of 4096
// (the same block size Scales Academy uses with AudioKit, and the Android version uses)
// and sends each full block to the page, where pitch.js analyses it.
// The analysis is done on the page, not here, so this audio thread is never held up.

class FLPitchProcessor extends AudioWorkletProcessor {
  constructor() {
    super();
    this.blockSize = 4096;
    this.block = new Float32Array(this.blockSize);
    this.filled = 0;
  }

  process(inputs) {
    const input = inputs[0];
    if (input && input.length > 0) {
      const channel = input[0]; // mono: first channel
      for (let i = 0; i < channel.length; i++) {
        this.block[this.filled++] = channel[i];
        if (this.filled === this.blockSize) {
          // Hand the full block to the page and start a new one
          this.port.postMessage(this.block, [this.block.buffer]);
          this.block = new Float32Array(this.blockSize);
          this.filled = 0;
        }
      }
    }
    return true; // keep running
  }
}

registerProcessor('fl-pitch-processor', FLPitchProcessor);
