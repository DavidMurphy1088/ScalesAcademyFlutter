package nz.co.musicmastereducation.scales_academy_flutter

import android.annotation.SuppressLint
import android.content.Context
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Build
import kotlin.math.max
import kotlin.math.sqrt

/**
 * Listens to the microphone and produces a pitch reading for every block of BLOCK_SIZE samples,
 * the same block size Scales Academy uses with AudioKit's PitchTap (4096 samples, about 0.09 s).
 *
 * Audio source: UNPROCESSED where the device supports it, otherwise VOICE_RECOGNITION.
 * The default MIC source applies phone-call style automatic gain control and noise suppression,
 * which distort piano notes and their loudness.
 */
class PitchListener(
    private val context: Context,
    private val onReading: (frequency: Float, amplitude: Float, clarity: Float) -> Unit,
) {
    companion object {
        const val SAMPLE_RATE = 44100      // guaranteed to be supported on all Android devices
        const val BLOCK_SIZE = 4096
    }

    @Volatile private var running = false
    private var thread: Thread? = null
    private var record: AudioRecord? = null

    /** Which Android audio source is in use (shown on screen for testing) */
    var sourceName = ""
        private set

    /** Starts capturing. Returns null on success, or an error message. Permission must already be granted. */
    @SuppressLint("MissingPermission")
    fun start(): String? {
        val minBuffer = AudioRecord.getMinBufferSize(SAMPLE_RATE, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
        if (minBuffer <= 0) return "This device can't record at $SAMPLE_RATE Hz"
        val bufferBytes = max(minBuffer, BLOCK_SIZE * 2 * 2)

        var opened: AudioRecord? = null
        for ((source, name) in candidateSources()) {
            opened = createRecord(source, bufferBytes)
            if (opened != null) {
                sourceName = name
                break
            }
        }
        val rec = opened ?: return "Couldn't open the microphone"

        try {
            rec.startRecording()
        } catch (e: Exception) {
            rec.release()
            return "Couldn't start recording: ${e.message}"
        }
        record = rec
        running = true
        thread = Thread({ captureLoop(rec) }, "FLPitchListener").apply {
            priority = Thread.MAX_PRIORITY
            start()
        }
        return null
    }

    fun stop() {
        running = false
        thread?.join(500)
        thread = null
        record?.let {
            try { it.stop() } catch (_: Exception) {}
            it.release()
        }
        record = null
    }

    /** Preferred audio sources, best first */
    private fun candidateSources(): List<Pair<Int, String>> {
        val sources = mutableListOf<Pair<Int, String>>()
        val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N &&
            audioManager.getProperty(AudioManager.PROPERTY_SUPPORT_AUDIO_SOURCE_UNPROCESSED) == "true") {
            sources.add(Pair(MediaRecorder.AudioSource.UNPROCESSED, "UNPROCESSED"))
        }
        sources.add(Pair(MediaRecorder.AudioSource.VOICE_RECOGNITION, "VOICE_RECOGNITION"))
        sources.add(Pair(MediaRecorder.AudioSource.MIC, "MIC"))
        return sources
    }

    @SuppressLint("MissingPermission")
    private fun createRecord(source: Int, bufferBytes: Int): AudioRecord? {
        return try {
            val rec = AudioRecord(source, SAMPLE_RATE, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT, bufferBytes)
            if (rec.state == AudioRecord.STATE_INITIALIZED) rec else {
                rec.release()
                null
            }
        } catch (e: Exception) {
            null
        }
    }

    private fun captureLoop(rec: AudioRecord) {
        val shorts = ShortArray(BLOCK_SIZE)
        val samples = FloatArray(BLOCK_SIZE)
        val yin = Yin(SAMPLE_RATE, BLOCK_SIZE)

        while (running) {
            // Fill one complete block
            var filled = 0
            while (filled < BLOCK_SIZE && running) {
                val n = rec.read(shorts, filled, BLOCK_SIZE - filled)
                if (n <= 0) {
                    Thread.sleep(10)   // read error: don't spin
                    break
                }
                filled += n
            }
            if (!running) break
            if (filled < BLOCK_SIZE) continue

            // Convert to -1..1 and measure loudness (RMS)
            var sumSquares = 0.0
            for (i in 0 until BLOCK_SIZE) {
                val s = shorts[i] / 32768f
                samples[i] = s
                sumSquares += (s * s).toDouble()
            }
            val amplitude = sqrt(sumSquares / BLOCK_SIZE).toFloat()

            val pitch = yin.detect(samples)
            onReading(pitch.frequency, amplitude, pitch.clarity)
        }
    }
}
