package nz.co.musicmastereducation.scales_academy_flutter

import android.Manifest
import android.content.pm.PackageManager
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * Connects the Android microphone pitch listener (PitchListener) to Dart.
 *
 *  - MethodChannel "fl/pitch/control": "start" / "stop"
 *  - EventChannel  "fl/pitch/readings": one map per 4096-sample block:
 *        {frequency (Hz, -1 = no pitch), amplitude (RMS 0..1), clarity (0..1)}
 *
 * This is the Android equivalent of Scales Academy's AudioKit PitchTap, which gives a
 * (frequency, amplitude) reading for every 4096-sample block of microphone sound.
 */
class MainActivity : FlutterActivity() {
    companion object {
        private const val CONTROL_CHANNEL = "fl/pitch/control"
        private const val READINGS_CHANNEL = "fl/pitch/readings"
        private const val MIC_PERMISSION_REQUEST = 4101
    }

    private var pitchListener: PitchListener? = null
    private var eventSink: EventChannel.EventSink? = null
    private var pendingStartResult: MethodChannel.Result? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        EventChannel(messenger, READINGS_CHANNEL).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                eventSink = events
            }

            override fun onCancel(arguments: Any?) {
                eventSink = null
            }
        })

        MethodChannel(messenger, CONTROL_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> startListening(result)
                "stop" -> {
                    stopListening()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    /** Ask for microphone permission if needed, then start capturing. */
    private fun startListening(result: MethodChannel.Result) {
        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) {
            result.success(beginCapture())
        } else {
            pendingStartResult = result
            requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), MIC_PERMISSION_REQUEST)
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != MIC_PERMISSION_REQUEST) return
        val result = pendingStartResult ?: return
        pendingStartResult = null
        val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
        if (granted) {
            result.success(beginCapture())
        } else {
            result.success(mapOf("started" to false, "error" to "Microphone permission was not given"))
        }
    }

    private fun beginCapture(): Map<String, Any> {
        stopListening()
        val listener = PitchListener(this) { frequency, amplitude, clarity ->
            // Readings are made on the audio thread; Flutter channels must be used on the main thread
            mainHandler.post {
                eventSink?.success(
                    mapOf("frequency" to frequency.toDouble(), "amplitude" to amplitude.toDouble(), "clarity" to clarity.toDouble())
                )
            }
        }
        val error = listener.start()
        if (error != null) {
            return mapOf("started" to false, "error" to error)
        }
        pitchListener = listener
        return mapOf("started" to true, "source" to "YIN, Android audio source ${listener.sourceName}", "sampleRate" to PitchListener.SAMPLE_RATE)
    }

    private fun stopListening() {
        pitchListener?.stop()
        pitchListener = null
    }

    override fun onDestroy() {
        stopListening()
        super.onDestroy()
    }
}
