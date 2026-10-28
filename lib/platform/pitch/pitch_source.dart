import 'package:flutter/foundation.dart';

import 'native_pitch_source.dart';
import 'pitch_reading.dart';
// The web version is only compiled into the web app
import 'web_pitch_source_stub.dart' if (dart.library.js_interop) 'web_pitch_source.dart';

/// Result of starting the microphone
class PitchSourceStartResult {
  final bool started;

  /// e.g. the detector and audio source used, or an error message
  final String detail;

  const PitchSourceStartResult(this.started, this.detail);
}

/// A pitch detection method the user can choose
class PitchDetectorOption {
  final String id;
  final String label;

  /// Starting loudness filter for this detector (each detector measures loudness differently)
  final double defaultAmplitudeFilter;

  const PitchDetectorOption(this.id, this.label, {this.defaultAmplitudeFilter = 0.03});
}

/// YIN on every platform (Android, iOS, web): loudness filter starts at 0.
/// YIN's loudness (plain RMS) is about 10x lower than AudioKit's for the same note: in tests correct notes
/// peaked at only 0.004-0.019 (iPhone, web) and 0.010 (Samsung), so AudioKit's 0.03 would block them.
const yinDetector = PitchDetectorOption('yin', 'YIN', defaultAmplitudeFilter: 0.0);
const audioKitDetector = PitchDetectorOption('audiokit', 'AudioKit (SA)');

/// Something that listens to the microphone and produces pitch readings.
/// Each platform has its own implementation:
///  - Android: NativePitchSource -> Kotlin AudioRecord + YIN (android/app/src/main/kotlin)
///  - iOS: NativePitchSource -> Swift, choice of AudioKit (Scales Academy's method) or YIN (ios/Runner)
///  - Web: WebPitchSource (web/pitch.js + web/pitch_worklet.js), YIN
abstract class PitchSource {
  /// The detectors available on this platform (first = default)
  List<PitchDetectorOption> get detectors;

  /// Readings, about 10 per second while listening
  Stream<PitchReading> get readings;

  Future<PitchSourceStartResult> start({required String detectorId});

  Future<void> stop();

  /// The pitch source for the platform the app is running on, or null if not available
  static PitchSource? forThisPlatform() {
    if (kIsWeb) return createWebPitchSource();
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return NativePitchSource(detectors: const [yinDetector]);
      case TargetPlatform.iOS:
        return NativePitchSource(detectors: const [audioKitDetector, yinDetector]);
      default:
        return null;
    }
  }
}
