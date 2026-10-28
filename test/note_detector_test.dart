import 'package:flutter_test/flutter_test.dart';

import 'package:scales_academy_flutter/music/midi.dart';
import 'package:scales_academy_flutter/exercise/note_detector.dart';
import 'package:scales_academy_flutter/platform/pitch/pitch_reading.dart';

PitchReading r(double hz, double amp) => PitchReading(frequency: hz, amplitude: amp);

void main() {
  test('frequency to MIDI matches Scales Academy', () {
    expect(frequencyToMidi(440), 69);
    expect(frequencyToMidi(261.63), 60);
    expect(frequencyToMidi(27.5), 21); // A0
    expect(frequencyToMidi(-1), 0);
    expect(midiName(60), 'C4');
    expect(midiName(69), 'A4');
  });

  test('a note needs 2 readings in a row', () {
    final d = NoteDetector();
    expect(d.process(r(261.63, 0.1)).status, ReadingStatus.countTooLow);
    final second = d.process(r(261.63, 0.1));
    expect(second.status, ReadingStatus.accepted);
    expect(second.note!.midi, 60);
    expect(second.note!.changed, isTrue);
    final third = d.process(r(261.63, 0.1));
    expect(third.status, ReadingStatus.accepted);
    expect(third.note!.changed, isFalse);
  });

  test('quiet readings are ignored but the last note is remembered (as in Scales Academy)', () {
    final d = NoteDetector();
    d.process(r(261.63, 0.1)); // C4, first reading
    expect(d.process(r(261.63, 0.01)).status, ReadingStatus.belowAmplitudeFilter);
    // SA resets the count but keeps the last note heard, so the same note is accepted at once
    expect(d.process(r(261.63, 0.1)).status, ReadingStatus.accepted);
    // A different note after a quiet reading still needs 2 in a row
    d.process(r(261.63, 0.01));
    expect(d.process(r(293.66, 0.1)).status, ReadingStatus.countTooLow); // D4
    expect(d.process(r(293.66, 0.1)).status, ReadingStatus.accepted);
  });

  test('same note name in another octave counts as a repeat', () {
    final d = NoteDetector();
    d.process(r(261.63, 0.1)); // C4
    final result = d.process(r(523.25, 0.1)); // C5
    expect(result.status, ReadingStatus.accepted);
    expect(result.note!.midi, 72);
  });

  test('a different note restarts the count', () {
    final d = NoteDetector();
    d.process(r(261.63, 0.1)); // C4
    expect(d.process(r(293.66, 0.1)).status, ReadingStatus.countTooLow); // D4
    expect(d.process(r(293.66, 0.1)).status, ReadingStatus.accepted);
  });

  test('no pitch restarts the count', () {
    final d = NoteDetector();
    d.process(r(261.63, 0.1));
    expect(d.process(r(-1, 0.1)).status, ReadingStatus.noPitch);
    expect(d.process(r(261.63, 0.1)).status, ReadingStatus.countTooLow);
  });
}
