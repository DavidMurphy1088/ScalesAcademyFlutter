package nz.co.musicmastereducation.scales_academy_flutter

/** Overtone check: a longer delay must score under this fraction of the first dip's score */
private const val OVERTONE_RATIO = 0.7f

/** Overtone check only runs when the first dip's score is above this (not already a near-perfect match) */
private const val OVERTONE_MIN_FIRST = 0.05f

/**
 * YIN pitch detection (de Cheveigné & Kawahara, 2002), limited to the piano's range.
 * Plays the role of AudioKit's pitch tracker in Scales Academy: one frequency estimate per block.
 */
class Yin(private val sampleRate: Int, bufferSize: Int, private val threshold: Float = 0.15f) {

    data class Result(val frequency: Float, val clarity: Float)

    private val window = bufferSize / 2
    // Lowest piano note A0 = 27.5 Hz, highest C8 = 4186 Hz
    private val maxTau = minOf(window, (sampleRate / 26.0).toInt())
    private val minTau = maxOf(2, (sampleRate / 4500.0).toInt())
    private val d = FloatArray(maxTau)

    /** Returns frequency in Hz (-1 if no clear pitch) and clarity 0..1 (1 = very clear) */
    fun detect(buffer: FloatArray): Result {
        // 1. Difference function
        d[0] = 0f
        for (tau in 1 until maxTau) {
            var sum = 0f
            for (i in 0 until window) {
                val delta = buffer[i] - buffer[i + tau]
                sum += delta * delta
            }
            d[tau] = sum
        }

        // 2. Cumulative mean normalised difference
        d[0] = 1f
        var runningSum = 0f
        for (tau in 1 until maxTau) {
            runningSum += d[tau]
            d[tau] = if (runningSum == 0f) 1f else d[tau] * tau / runningSum
        }

        // 3. First dip below the threshold, then follow it down to its minimum
        var tauEstimate = -1
        var tau = minTau
        while (tau < maxTau) {
            if (d[tau] < threshold) {
                while (tau + 1 < maxTau && d[tau + 1] < d[tau]) tau++
                tauEstimate = tau
                break
            }
            tau++
        }
        if (tauEstimate == -1) return Result(-1f, 0f)

        // 3b. Overtone check (same in Yin.kt, pitch.js and YinPitch.swift): a piano note's overtones repeat
        //     2x or 3x faster than the note, so the first dip found can be an overtone (e.g. E4's 3rd harmonic is B5).
        //     Only when the first dip is not already a near-perfect match (score above 0.05): if 2 or 3 times this
        //     delay lines up clearly better (score under 70% of it), the note is that lower one.
        //     (Tuned on synthetic piano tones: fixes E4 read as B5, and changes no correctly detected note.)
        //     A real higher note also lines up at 2x and 3x its delay, but no better, so it is left unchanged.
        val firstDip = tauEstimate
        if (d[firstDip] > OVERTONE_MIN_FIRST) for (multiple in 2..3) {
            val from = firstDip * multiple - multiple   // allow for the period not being a whole number of samples
            val to = firstDip * multiple + multiple
            if (to >= maxTau) break
            var tMin = from
            for (t in from..to) if (d[t] < d[tMin]) tMin = t
            if (d[tMin] < d[firstDip] * OVERTONE_RATIO && d[tMin] < d[tauEstimate]) tauEstimate = tMin
        }

        // 4. Parabolic interpolation for a more exact period
        var betterTau = tauEstimate.toFloat()
        if (tauEstimate > 0 && tauEstimate < maxTau - 1) {
            val s0 = d[tauEstimate - 1]
            val s1 = d[tauEstimate]
            val s2 = d[tauEstimate + 1]
            val denominator = 2f * (2f * s1 - s2 - s0)
            if (denominator != 0f) betterTau = tauEstimate + (s2 - s0) / denominator
        }
        val clarity = (1f - d[tauEstimate]).coerceIn(0f, 1f)
        return Result(sampleRate / betterTau, clarity)
    }
}
