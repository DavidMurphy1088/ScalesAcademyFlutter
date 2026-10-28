import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'pitch_reading.dart';
import 'pitch_source.dart';

// JavaScript functions defined in web/pitch.js
@JS('flPitchStart')
external JSPromise<JSString> _jsPitchStart(JSFunction onReading);

@JS('flPitchStop')
external void _jsPitchStop();

/// Web microphone pitch readings, from web/pitch.js + web/pitch_worklet.js
/// (browser microphone, 4096-sample blocks, YIN - the same method as the Android version).
class WebPitchSource implements PitchSource {
  @override
  List<PitchDetectorOption> get detectors => const [yinDetector];

  final _controller = StreamController<PitchReading>.broadcast();

  @override
  Stream<PitchReading> get readings => _controller.stream;

  @override
  Future<PitchSourceStartResult> start({required String detectorId}) async {
    // Called straight from the Start button tap: the JavaScript starts audio before any 'await',
    // which browsers (Safari especially) require.
    void onReading(JSNumber frequency, JSNumber amplitude, JSNumber clarity) {
      _controller.add(PitchReading(
        frequency: frequency.toDartDouble,
        amplitude: amplitude.toDartDouble,
        clarity: clarity.toDartDouble,
      ));
    }

    try {
      final json = (await _jsPitchStart(onReading.toJS).toDart).toDart;
      final result = jsonDecode(json) as Map<String, dynamic>;
      return PitchSourceStartResult(result['started'] == true, '${result['detail']}');
    } catch (e) {
      return PitchSourceStartResult(false, 'Could not start the microphone: $e');
    }
  }

  @override
  Future<void> stop() async {
    _jsPitchStop();
  }
}

PitchSource? createWebPitchSource() => WebPitchSource();
