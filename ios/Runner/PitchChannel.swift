import Flutter
import AVFoundation
import AudioKit
import AudioKitEX      // Fader (as in Scales Academy AudioManager)
import SoundpipeAudioKit

/// Something that listens to the microphone and reports (frequency Hz, amplitude, clarity) about 10 times a second.
protocol PitchDetecting: AnyObject {
    var name: String { get }
    func start(onReading: @escaping (Float, Float, Float) -> Void) throws
    func stop()
}

enum PitchDetectorError: LocalizedError {
    case noMicrophone
    var errorDescription: String? { "No microphone input is available" }
}

/// Connects iOS microphone pitch detection to Dart, using the same channels as Android:
///  - MethodChannel "fl/pitch/control": "start" {detector: "audiokit" | "yin"} / "stop"
///  - EventChannel  "fl/pitch/readings": {frequency, amplitude, clarity} per 4096-sample block
/// Two detectors can be chosen in the app:
///  - "audiokit": Scales Academy's own method - AudioKit PitchTap (AudioKitPitchDetector below)
///  - "yin": the same YIN method as the Android and web versions (YinPitch.swift)
final class PitchChannel: NSObject, FlutterStreamHandler {
    private var eventSink: FlutterEventSink?
    private var detector: PitchDetecting?

    init(messenger: FlutterBinaryMessenger) {
        super.init()
        FlutterEventChannel(name: "fl/pitch/readings", binaryMessenger: messenger).setStreamHandler(self)
        FlutterMethodChannel(name: "fl/pitch/control", binaryMessenger: messenger).setMethodCallHandler { [weak self] call, result in
            guard let self = self else { return }
            switch call.method {
            case "start":
                let args = call.arguments as? [String: Any]
                let detectorName = args?["detector"] as? String ?? "audiokit"
                self.start(detectorName: detectorName, result: result)
            case "stop":
                self.stop()
                result(nil)
            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        eventSink = events
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        return nil
    }

    private func start(detectorName: String, result: @escaping FlutterResult) {
        stop()
        PitchChannel.requestMicrophonePermission { [weak self] granted in
            guard let self = self else { return }
            guard granted else {
                result(["started": false, "error": "Microphone permission was not given. Turn it on in Settings > SA Flutter."])
                return
            }
            do {
                try PitchChannel.configureAudioSession()
                let newDetector: PitchDetecting = detectorName == "yin" ? YinPitchDetector() : AudioKitPitchDetector()
                try newDetector.start { [weak self] frequency, amplitude, clarity in
                    // Readings arrive on audio threads; Flutter channels must be used on the main thread
                    DispatchQueue.main.async {
                        self?.eventSink?(["frequency": Double(frequency), "amplitude": Double(amplitude), "clarity": Double(clarity)])
                    }
                }
                self.detector = newDetector
                let rate = Int(AVAudioSession.sharedInstance().sampleRate)
                result(["started": true, "source": "\(newDetector.name), \(rate) Hz"])
            } catch {
                result(["started": false, "error": "Couldn't start the microphone: \(error.localizedDescription)"])
            }
        }
    }

    private func stop() {
        detector?.stop()
        detector = nil
    }

    /// Calls back on the main thread
    private static func requestMicrophonePermission(_ completion: @escaping (Bool) -> Void) {
        if #available(iOS 17.0, *) {
            AVAudioApplication.requestRecordPermission { granted in
                DispatchQueue.main.async { completion(granted) }
            }
        } else {
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                DispatchQueue.main.async { completion(granted) }
            }
        }
    }

    /// Same audio session as Scales Academy (AudioManager.setSession):
    /// .playAndRecord, mode .default, [.defaultToSpeaker], hardware asked for 48 kHz.
    /// See Scales Academy Notes/AudioSession_iPadPlaybackScratch.md for why 48 kHz.
    private static func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try session.setPreferredSampleRate(48_000)
        try session.setActive(true)
    }
}

/// Scales Academy's method: AudioKit PitchTap on the microphone (as in SA AudioManager / installTapHandler).
final class AudioKitPitchDetector: PitchDetecting {
    let name = "AudioKit PitchTap (Scales Academy)"
    private var engine: AudioEngine?
    private var tappable: Fader?
    private var silencer: Fader?
    private var pitchTap: PitchTap?

    func start(onReading: @escaping (Float, Float, Float) -> Void) throws {
        // Same as SA (Fix 1 in the audio session notes): AudioKit runs at 48 kHz to match the hardware
        if let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2) {
            AudioKit.Settings.audioFormat = format
        }
        let engine = AudioEngine()
        guard let mic = engine.input else { throw PitchDetectorError.noMicrophone }
        // As in SA: mic -> Fader (tapped) -> Fader at volume 0 (the "silencer") -> output,
        // so the engine runs but the microphone is never heard
        let tappable = Fader(mic)
        let silencer = Fader(tappable, gain: 0)
        engine.output = silencer

        let pitchTap = PitchTap(tappable, bufferSize: 4096) { pitch, amplitude in
            // As in SA AcousticSoundEventHandler.tapUpdate: use the louder of the two channels.
            // AudioKit gives no clarity value, so 0 is sent.
            if amplitude[0] > amplitude[1] {
                onReading(pitch[0], amplitude[0], 0)
            } else {
                onReading(pitch[1], amplitude[1], 0)
            }
        }
        pitchTap.start()
        try engine.start()

        self.engine = engine
        self.tappable = tappable
        self.silencer = silencer
        self.pitchTap = pitchTap
    }

    func stop() {
        pitchTap?.stop()
        engine?.stop()
        pitchTap = nil
        silencer = nil
        tappable = nil
        engine = nil
    }
}
