import 'package:flutter/services.dart';

import 'pitch_reading.dart';
import 'pitch_source.dart';

/// Android and iOS microphone pitch readings, through platform channels:
///  - Android: MainActivity / PitchListener / Yin (Kotlin)
///  - iOS: PitchChannel.swift (AudioKit, as in Scales Academy) and YinPitch.swift (YIN)
class NativePitchSource implements PitchSource {
  static const _control = MethodChannel('fl/pitch/control');
  static const _readings = EventChannel('fl/pitch/readings');

  @override
  final List<PitchDetectorOption> detectors;

  NativePitchSource({required this.detectors});

  Stream<PitchReading>? _stream;

  @override
  Stream<PitchReading> get readings => _stream ??= _readings.receiveBroadcastStream().map((event) {
        final m = event as Map;
        return PitchReading(
          frequency: (m['frequency'] as num).toDouble(),
          amplitude: (m['amplitude'] as num).toDouble(),
          clarity: (m['clarity'] as num? ?? 0).toDouble(),
        );
      });

  @override
  Future<PitchSourceStartResult> start({required String detectorId}) async {
    try {
      final result = await _control.invokeMapMethod<String, dynamic>('start', {'detector': detectorId});
      if (result?['started'] == true) {
        final rate = result?['sampleRate'];
        return PitchSourceStartResult(true, '${result?['source']}${rate != null ? ', $rate Hz' : ''}');
      }
      return PitchSourceStartResult(false, '${result?['error'] ?? 'Could not start the microphone'}');
    } on PlatformException catch (e) {
      return PitchSourceStartResult(false, e.message ?? e.code);
    }
  }

  @override
  Future<void> stop() => _control.invokeMethod('stop');
}
