import 'dart:async';

import '../exercise/note_detector.dart';
import '../platform/midi/midi_input.dart';
import '../platform/pitch/pitch_source.dart';

/// Where a played note came from
enum NoteSource {
  microphone,
  midi,

  /// The keyboard on the screen
  screen;

  String get label => switch (this) { microphone => 'mic', midi => 'MIDI', screen => 'screen' };
}

/// A note played by the user, from any source (Stage 4). Exercises (Stage 5) will listen to these.
class PlayedNote {
  final int midi;

  /// Key down (true) or up. The microphone only gives key downs: a note is heard when it starts.
  final bool on;

  /// MIDI velocity 1-127 (MIDI, screen); 0 for the microphone
  final int velocity;

  /// Microphone loudness (0 for the other sources)
  final double amplitude;
  final NoteSource source;

  /// Since [NoteInput] was made (one clock for every source)
  final Duration time;

  const PlayedNote({
    required this.midi,
    required this.on,
    required this.source,
    required this.time,
    this.velocity = 0,
    this.amplitude = 0,
  });
}

/// What the app listens to for played notes ("Listen with"). The keyboard on the screen always counts too.
enum ListenWith { nothing, microphone, midi }

/// One stream of played notes from the microphone, a MIDI keyboard and the keyboard on the screen.
class NoteInput {
  final PitchSource? pitch;
  final MidiInput midi;

  NoteInput({required this.pitch, required this.midi});

  final _clock = Stopwatch()..start();
  final _notes = StreamController<PlayedNote>.broadcast();
  final NoteDetector _detector = NoteDetector();
  StreamSubscription<dynamic>? _subscription;
  ListenWith _listenWith = ListenWith.nothing;

  Stream<PlayedNote> get notes => _notes.stream;
  ListenWith get listenWith => _listenWith;
  Duration get now => _clock.elapsed;

  /// The keyboard on the screen: a key pressed or released
  void addFromScreen(int midi, {required bool on}) {
    _notes.add(PlayedNote(midi: midi, on: on, velocity: on ? 64 : 0, source: NoteSource.screen, time: now));
  }

  /// Listen to the microphone with SA's note rules (NoteDetector). A note is reported each time it changes,
  /// as SA highlights a note when it changes. Returns the microphone's start message.
  Future<String> listenWithMicrophone() async {
    await stop();
    final source = pitch;
    if (source == null) return 'No microphone pitch detection on this platform';
    final detector = source.detectors.first;
    _detector
      ..amplitudeFilter = detector.defaultAmplitudeFilter
      ..requiredCount = NoteDetector.defaultRequiredCount
      ..reset();
    _subscription = source.readings.listen((reading) {
      final note = _detector.process(reading).note;
      if (note != null && note.changed) {
        _notes.add(PlayedNote(
            midi: note.midi, on: true, amplitude: note.amplitude, source: NoteSource.microphone, time: now));
      }
    });
    final result = await source.start(detectorId: detector.id);
    if (!result.started) {
      await _subscription?.cancel();
      _subscription = null;
      return 'Microphone did not start: ${result.detail}';
    }
    _listenWith = ListenWith.microphone;
    return 'Listening with the microphone (${detector.label}, loudness filter ${detector.defaultAmplitudeFilter}): '
        '${result.detail}';
  }

  /// Listen to [device]
  Future<String> listenWithMidi(MidiDeviceInfo device) async {
    await stop();
    await midi.connect(device);
    _subscription = midi.messages.listen((m) {
      _notes.add(PlayedNote(midi: m.midi, on: m.isNoteOn, velocity: m.velocity, source: NoteSource.midi, time: now));
    });
    _listenWith = ListenWith.midi;
    return 'Listening with $device';
  }

  /// Stop listening to the microphone or MIDI keyboard (the keyboard on the screen still counts)
  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    final was = _listenWith;
    _listenWith = ListenWith.nothing;
    if (was == ListenWith.microphone) await pitch?.stop();
    if (was == ListenWith.midi) await midi.disconnect();
  }
}
