import AVFoundation
import Accelerate

/// The same method as the Android (Yin.kt) and web (pitch.js) versions:
/// Apple's AVAudioEngine microphone input, collected into 4096-sample blocks, loudness (RMS) and YIN pitch.
final class YinPitchDetector: PitchDetecting {
    let name = "YIN (same as Android and web)"
    private static let blockSize = 4096

    private let engine = AVAudioEngine()
    private let queue = DispatchQueue(label: "nz.co.musicmastereducation.saf.yin")
    private let lock = NSLock()

    // Only used on the background queue
    private var block = [Float](repeating: 0, count: YinPitchDetector.blockSize)
    private var filled = 0
    private var yin: Yin?

    // Shared between threads, protected by lock
    private var onReading: ((Float, Float, Float) -> Void)?
    private var running = false
    /// Blocks waiting for analysis. If analysis falls behind, new sound is skipped rather than queued,
    /// so readings stay current and Stop never has to wait for a backlog.
    private var pendingBlocks = 0

    func start(onReading: @escaping (Float, Float, Float) -> Void) throws {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw PitchDetectorError.noMicrophone }

        yin = Yin(sampleRate: Float(format.sampleRate), bufferSize: YinPitchDetector.blockSize)
        filled = 0
        lock.lock()
        self.onReading = onReading
        running = true
        pendingBlocks = 0
        lock.unlock()

        // Keep the engine running without the microphone being heard (volume 0, like SA's "silencer")
        engine.connect(input, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 0

        input.installTap(onBus: 0, bufferSize: AVAudioFrameCount(YinPitchDetector.blockSize), format: format) { [weak self] buffer, _ in
            guard let self = self, let channel = buffer.floatChannelData?[0] else { return }
            self.lock.lock()
            let ok = self.running && self.pendingBlocks < 2
            if ok { self.pendingBlocks += 1 }
            self.lock.unlock()
            guard ok else { return }   // analysis is behind: skip this sound
            // iOS may deliver a different number of samples than requested, so collect them into exact 4096 blocks
            let samples = Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
            self.queue.async {
                self.collect(samples)
                self.lock.lock()
                self.pendingBlocks -= 1
                self.lock.unlock()
            }
        }
        engine.prepare()
        try engine.start()
    }

    /// Returns at once: never waits for analysis still in progress
    func stop() {
        lock.lock()
        running = false
        onReading = nil
        lock.unlock()
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }

    /// Runs on the background queue
    private func collect(_ samples: [Float]) {
        for sample in samples {
            block[filled] = sample
            filled += 1
            if filled == YinPitchDetector.blockSize {
                analyse()
                filled = 0
            }
        }
    }

    private func analyse() {
        lock.lock()
        let callback = running ? onReading : nil
        lock.unlock()
        guard let yin = yin, let callback = callback else { return }
        var meanSquare: Float = 0
        vDSP_measqv(block, 1, &meanSquare, vDSP_Length(block.count))
        let amplitude = meanSquare.squareRoot()
        let result = yin.detect(block)
        callback(result.frequency, amplitude, result.clarity)
    }
}

/// YIN pitch detection (de Cheveigné & Kawahara, 2002), limited to the piano's range.
/// A line-for-line copy of the Android Yin.kt.
final class Yin {
    private let sampleRate: Float
    private let threshold: Float
    private let window: Int
    private let maxTau: Int
    private let minTau: Int
    private var d: [Float]

    init(sampleRate: Float, bufferSize: Int, threshold: Float = 0.15) {
        self.sampleRate = sampleRate
        self.threshold = threshold
        window = bufferSize / 2
        maxTau = min(window, Int(sampleRate / 26.0))      // lowest piano note A0 = 27.5 Hz
        minTau = max(2, Int(sampleRate / 4500.0))         // highest piano note C8 = 4186 Hz
        d = [Float](repeating: 0, count: maxTau)
    }

    /// Returns frequency in Hz (-1 if no clear pitch) and clarity 0..1
    func detect(_ buffer: [Float]) -> (frequency: Float, clarity: Float) {
        // 1. Difference function: d(tau) = sum over i of (x[i] - x[i+tau])^2
        //    = sum x[i]^2 + sum x[i+tau]^2 - 2 * sum x[i]*x[i+tau]
        //    Computed with Apple's Accelerate (vDSP), which is fast even in debug builds. Same result as Yin.kt.
        d[0] = 0
        buffer.withUnsafeBufferPointer { b in
            guard let base = b.baseAddress else { return }
            let n = vDSP_Length(window)
            var energyStart: Float = 0
            vDSP_svesq(base, 1, &energyStart, n)                 // sum x[i]^2, i = 0..<window
            for tau in 1..<maxTau {
                var energyShifted: Float = 0
                vDSP_svesq(base + tau, 1, &energyShifted, n)     // sum x[i+tau]^2 (computed exactly each time)
                var cross: Float = 0
                vDSP_dotpr(base, 1, base + tau, 1, &cross, n)     // sum x[i]*x[i+tau]
                d[tau] = max(0, energyStart + energyShifted - 2 * cross)
            }
        }
        // 2. Cumulative mean normalised difference
        d[0] = 1
        var runningSum: Float = 0
        for tau in 1..<maxTau {
            runningSum += d[tau]
            d[tau] = runningSum == 0 ? 1 : d[tau] * Float(tau) / runningSum
        }
        // 3. First dip below the threshold, followed down to its minimum
        var tauEstimate = -1
        var tau = minTau
        while tau < maxTau {
            if d[tau] < threshold {
                while tau + 1 < maxTau && d[tau + 1] < d[tau] { tau += 1 }
                tauEstimate = tau
                break
            }
            tau += 1
        }
        if tauEstimate == -1 { return (-1, 0) }
        // 3b. Overtone check (same in Yin.kt, pitch.js and YinPitch.swift): a piano note's overtones repeat
        //     2x or 3x faster than the note, so the first dip found can be an overtone (e.g. E4's 3rd harmonic is B5).
        //     Only when the first dip is not already a near-perfect match (score above 0.05): if 2 or 3 times this
        //     delay lines up clearly better (score under 70% of it), the note is that lower one.
        //     (Tuned on synthetic piano tones: fixes E4 read as B5, and changes no correctly detected note.)
        //     A real higher note also lines up at 2x and 3x its delay, but no better, so it is left unchanged.
        let overtoneRatio: Float = 0.7, overtoneMinFirst: Float = 0.05
        let firstDip = tauEstimate
        for multiple in 2...3 where d[firstDip] > overtoneMinFirst {
            let from = firstDip * multiple - multiple   // allow for the period not being a whole number of samples
            let to = firstDip * multiple + multiple
            if to >= maxTau { break }
            var tMin = from
            for t in from...to where d[t] < d[tMin] { tMin = t }
            if d[tMin] < d[firstDip] * overtoneRatio && d[tMin] < d[tauEstimate] { tauEstimate = tMin }
        }
        // 4. Parabolic interpolation for a more exact period
        var betterTau = Float(tauEstimate)
        if tauEstimate > 0 && tauEstimate < maxTau - 1 {
            let s0 = d[tauEstimate - 1], s1 = d[tauEstimate], s2 = d[tauEstimate + 1]
            let denominator = 2 * (2 * s1 - s2 - s0)
            if denominator != 0 { betterTau = Float(tauEstimate) + (s2 - s0) / denominator }
        }
        let clarity = min(1, max(0, 1 - d[tauEstimate]))
        return (sampleRate / betterTau, clarity)
    }
}
