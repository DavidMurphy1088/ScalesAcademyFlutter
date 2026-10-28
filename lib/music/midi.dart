import 'dart:math' as math;

/// Same as Scales Academy Util.frequencyToMIDI: nearest MIDI note number (A4 = 440 Hz = 69).
/// Returns 0 if the frequency isn't valid.
int frequencyToMidi(double frequency) {
  if (frequency <= 0) return 0;
  final midi = 69 + 12 * (math.log(frequency / 440.0) / math.ln2);
  if (midi.isNaN || midi.isInfinite) return 0;
  return midi.round();
}

const _noteNames = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];

/// e.g. 60 -> "C4", 69 -> "A4"
String midiName(int midi) => '${_noteNames[midi % 12]}${midi ~/ 12 - 1}';

/// Letter name of a note as 0-6 for C D E F G A B, ignoring the octave
/// (sharps share their letter: C#4 counts as C, as in [midiName]).
int letterOf(int midi) {
  const letterOfPitchClass = [0, 0, 1, 1, 2, 3, 3, 4, 4, 5, 5, 6];
  return letterOfPitchClass[midi % 12];
}

/// How many letter names apart two notes are, comparing only the letter (not the octave) and
/// wrapping round from B to C, so it is 0-3: whether they sit side by side on the keyboard.
/// C-D = 1, B-C = 1, G-A = 1, C-C (any octave) = 0, F-A = 2, C-F = 3.
int letterDistance(int midiA, int midiB) {
  final d = (letterOf(midiA) - letterOf(midiB)).abs();
  return d < 7 - d ? d : 7 - d;
}
