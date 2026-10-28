import '../platform/pitch/pitch_reading.dart';
import '../music/midi.dart';

/// A note the detector has accepted: the same information Scales Academy sends to the exercise
/// as a MIDIMessage (noteOn, midi, velocity = amplitude).
class NoteEvent {
  final int midi;
  final double amplitude;

  /// True when this is a different note from the last accepted one
  /// (Scales Academy only highlights the keyboard/staff when the note changes)
  final bool changed;

  const NoteEvent({required this.midi, required this.amplitude, required this.changed});
}

enum ReadingStatus { accepted, belowAmplitudeFilter, countTooLow, noPitch }

/// What happened to one reading (for showing on screen while testing)
class ReadingResult {
  final PitchReading reading;
  final int midi;
  final ReadingStatus status;
  final NoteEvent? note;

  const ReadingResult(this.reading, this.midi, this.status, this.note);
}

/// The rules Scales Academy applies to each microphone reading
/// (AcousticSoundEventHandler.tapUpdate in SoundEventHandler.swift):
///  1. Ignore readings quieter than the amplitude filter (resets the run count).
///  2. Convert the frequency to a MIDI note.
///  3. Only accept a note once the same note name (C, D... ignoring octave) has been heard in
///     [requiredCount] readings in a row.
///  4. Each accepted reading produces a NoteEvent.
class NoteDetector {
  /// Scales Academy default is 0.03 (AudioKit amplitude). Android RMS loudness is on a different
  /// scale, so this needs setting by testing next to a piano.
  double amplitudeFilter;

  /// Scales Academy default is 2
  static const int defaultRequiredCount = 2;
  int requiredCount;

  int _consecutiveCount = 0;
  int? _lastPlayedMidi;
  int? _lastHighlightedMidi;

  NoteDetector({this.amplitudeFilter = 0.03, this.requiredCount = defaultRequiredCount});

  void reset() {
    _consecutiveCount = 0;
    _lastPlayedMidi = null;
    _lastHighlightedMidi = null;
  }

  ReadingResult process(PitchReading reading) {
    // Difference from Scales Academy: AudioKit always gives a frequency; Android YIN reports -1 when
    // there is no clear pitch. Treat that as "no note" and restart the count.
    if (!reading.hasPitch) {
      _consecutiveCount = 0;
      _lastPlayedMidi = null;
      return ReadingResult(reading, 0, ReadingStatus.noPitch, null);
    }

    final midi = frequencyToMidi(reading.frequency);
    var status = ReadingStatus.accepted;

    if (reading.amplitude >= amplitudeFilter) {
      final last = _lastPlayedMidi;
      if (last != null) {
        if (midi % 12 == last % 12) {
          _consecutiveCount += 1;
        } else {
          _consecutiveCount = 0;
        }
      }
      if (_consecutiveCount < requiredCount - 1) {
        status = ReadingStatus.countTooLow;
      }
      _lastPlayedMidi = midi;
    } else {
      status = ReadingStatus.belowAmplitudeFilter;
      _consecutiveCount = 0;
    }

    NoteEvent? note;
    if (status == ReadingStatus.accepted) {
      final changed = midi != _lastHighlightedMidi;
      _lastHighlightedMidi = midi;
      note = NoteEvent(midi: midi, amplitude: reading.amplitude, changed: changed);
    }
    return ReadingResult(reading, midi, status, note);
  }
}
