import '../music/midi.dart';

/// A one-hand scale as Scales Academy builds it (Scale.swift): up from the start note for
/// [octaves] octaves to the top note, then back down to the start note.
/// Two-octave C major from C4 = 15 notes up (C4..C6) + 14 down (B5..C4) = 29 notes.
List<int> buildMajorScale({required int startMidi, required int octaves}) {
  const offsets = [2, 2, 1, 2, 2, 2, 1];
  final up = <int>[];
  for (var oct = 0; oct < octaves; oct++) {
    var midi = startMidi + oct * 12;
    for (final step in offsets) {
      up.add(midi);
      midi += step;
    }
  }
  up.add(startMidi + octaves * 12);
  // As SA: down from the note below the top, back to the start
  final down = [for (var i = up.length - 2; i >= 0; i--) up[i]];
  return [...up, ...down];
}

enum VerdictKind {
  /// Matched an expected note: SA marks the key "played correctly" and counts it
  correct,

  /// SA marks the key as a wrong note
  wrong,

  /// SA receives the note but neither credits nor penalises it
  ignored,
}

/// Why SA ignored a note
enum IgnoredReason {
  /// More than 3 semitones outside the scale's lowest/highest note (ExerciseHandler.notifiedOfSound)
  outOfRange,

  /// Same note name as the last correct note, e.g. the same key still sounding (notifyPlayedKey)
  sameAsLastCorrect,

  /// No note has been correct yet, so SA doesn't test for wrong notes (notifyPlayedKey)
  beforeFirstCorrect,

  /// An octave of the lowest expected note (testForErrorAndHilightIt)
  octaveOfExpected,

  /// The exercise has ended
  afterEnd,
}

/// SA's judgement of one note it received
class Verdict {
  final int midi;
  final VerdictKind kind;
  final IgnoredReason? ignoredReason;

  /// The notes SA was expecting next when this note arrived
  final List<int> expected;

  /// For a correct note: the expected note it matched (may be an octave away),
  /// plus any expected notes it skipped over
  final int? matchedMidi;
  final List<int> skipped;

  const Verdict(this.midi, this.kind,
      {this.ignoredReason, this.expected = const [], this.matchedMidi, this.skipped = const []});

  String get description {
    final name = midiName(midi);
    final exp = expected.map(midiName).join('/');
    switch (kind) {
      case VerdictKind.correct:
        final parts = <String>[];
        if (matchedMidi != null && matchedMidi != midi) parts.add('octave of ${midiName(matchedMidi!)}');
        if (skipped.isNotEmpty) parts.add('skipped ${skipped.map(midiName).join(', ')}');
        return parts.isEmpty ? '$name correct' : '$name correct (${parts.join('; ')})';
      case VerdictKind.wrong:
        return '$name wrong (expected $exp)';
      case VerdictKind.ignored:
        switch (ignoredReason!) {
          case IgnoredReason.outOfRange:
            return '$name ignored: outside the scale range';
          case IgnoredReason.sameAsLastCorrect:
            return '$name ignored: same note name as the last correct note';
          case IgnoredReason.beforeFirstCorrect:
            return '$name ignored: no correct note yet (expected $exp)';
          case IgnoredReason.octaveOfExpected:
            return '$name ignored: octave of expected $exp';
          case IgnoredReason.afterEnd:
            return '$name ignored: exercise finished';
        }
    }
  }
}

/// Scales Academy's decision on each note, for a one-hand exercise with acoustic (microphone) input.
/// A Dart port of ExerciseHandler: notifiedOfSound -> pressKeyboard (choice of hand only) ->
/// notifyPlayedKey -> testForErrorAndHilightIt / testForEndOfExercise, without the keyboard,
/// staff and badge display. Plain Dart: the same on Android, iOS and web.
class ScaleScorer {
  final List<int> notes;

  /// SA user setting, off by default: also accept a 5th above / 4th below the expected note
  final bool allowHarmonics;

  /// SA has this on (Parameters.continueAfterError = true): wrong notes are counted and the exercise carries on
  static const bool continueAfterError = true;

  late final int _minMidi = notes.reduce((a, b) => a < b ? a : b);
  late final int _maxMidi = notes.reduce((a, b) => a > b ? a : b);

  int _nextIndex = 0;
  int? _lastMatchedMidi;
  bool _lastNoteWasWrong = false;
  int _totalCorrect = 0;
  int _wrongCount = 0;
  bool _completed = false;

  ScaleScorer(this.notes, {this.allowHarmonics = false});

  /// How many scale notes have been passed (matched or skipped over)
  int get progress => _nextIndex;
  int get totalCorrect => _totalCorrect;

  /// SA's wrongNotesPressedCount: every wrong reading counts, so a held wrong note counts many times
  int get wrongReadings => _wrongCount;
  bool get completed => _completed;
  int? get nextExpected => _nextIndex < notes.length ? notes[_nextIndex] : null;

  void reset() {
    _nextIndex = 0;
    _lastMatchedMidi = null;
    _lastNoteWasWrong = false;
    _totalCorrect = 0;
    _wrongCount = 0;
    _completed = false;
  }

  /// SA harmonicsTolerantMidis
  List<int> _allowed(int midi) => allowHarmonics
      ? [midi - 24, midi - 12, midi, midi + 12, midi + 24, midi + 7, midi - 5]
      : [midi - 24, midi - 12, midi, midi + 12, midi + 24];

  /// One noteOn, as SA sends for every accepted microphone reading (about 10 a second)
  Verdict judge(int midi) {
    // SA stops listening when the exercise ends, so nothing more is judged
    if (_completed) return Verdict(midi, VerdictKind.ignored, ignoredReason: IgnoredReason.afterEnd);

    // notifiedOfSound: acoustic input ignores notes far outside the scale
    const margin = 3;
    if (midi < _minMidi - margin || midi > _maxMidi + margin) {
      return Verdict(midi, VerdictKind.ignored, ignoredReason: IgnoredReason.outOfRange);
    }

    // notifyPlayedKey: the expected notes. Look ahead 2 (acoustic), or 1 at the top of the scale
    final atScaleMiddle = _nextIndex == notes.length ~/ 2;
    final lookahead = atScaleMiddle ? 1 : 2;
    final expected = <int>[
      for (var i = 0; i < lookahead; i++)
        if (_nextIndex + i < notes.length) notes[_nextIndex + i],
    ];

    // The first expected note this one matches (an octave or two away is allowed)
    var matchIndex = -1;
    for (var i = 0; i < expected.length; i++) {
      if (_allowed(expected[i]).contains(midi)) {
        matchIndex = i;
        break;
      }
    }

    if (matchIndex >= 0) {
      // Matched: earlier expected notes are passed over too
      final matched = expected.sublist(0, matchIndex + 1);
      _nextIndex += matched.length;
      _lastMatchedMidi = matched.last;
      // Stars: after a wrong note only the note actually played is credited
      _totalCorrect += _lastNoteWasWrong ? 1 : matched.length;
      _lastNoteWasWrong = false;
      _testForEnd();
      return Verdict(midi, VerdictKind.correct,
          expected: expected, matchedMidi: matched.last, skipped: matched.sublist(0, matchIndex));
    }

    // No match
    final lastMatched = _lastMatchedMidi;
    Verdict verdict;
    if (lastMatched == null) {
      verdict = Verdict(midi, VerdictKind.ignored, ignoredReason: IgnoredReason.beforeFirstCorrect, expected: expected);
    } else if (midi % 12 == lastMatched % 12) {
      verdict = Verdict(midi, VerdictKind.ignored, ignoredReason: IgnoredReason.sameAsLastCorrect, expected: expected);
    } else {
      verdict = _testForError(midi, expected);
    }
    if (continueAfterError) _testForEnd();
    return verdict;
  }

  /// SA testForErrorAndHilightIt
  Verdict _testForError(int midi, List<int> expected) {
    if (expected.isEmpty) return Verdict(midi, VerdictKind.ignored, ignoredReason: IgnoredReason.afterEnd);
    final lowest = expected.reduce((a, b) => a < b ? a : b);
    final excused = [...expected, for (var d = -24; d <= 24; d += 12) lowest + d];
    if (excused.contains(midi)) {
      return Verdict(midi, VerdictKind.ignored, ignoredReason: IgnoredReason.octaveOfExpected, expected: expected);
    }
    // Not allowed for the first expected note -> wrong (SA breaks out after the first)
    _lastNoteWasWrong = true;
    _wrongCount++;
    return Verdict(midi, VerdictKind.wrong, expected: expected);
  }

  /// SA testForEndOfExercise
  void _testForEnd() {
    if (_nextIndex >= notes.length) _completed = true;
  }
}

/// One line on screen: consecutive readings of the same note with the same outcome are shown once,
/// with a count. A held correct note's later readings (ignored by SA as the same note name) are
/// folded into its line, since they don't change the score.
class ScoredLine {
  final Verdict verdict;
  int readings = 1;

  /// Loudness of the first reading SA judged for this note (the noteOn "velocity")
  final double firstLoudness;

  /// Loudest of this note's judged readings
  double peakLoudness;

  ScoredLine(this.verdict, {double loudness = 0})
      : firstLoudness = loudness,
        peakLoudness = loudness;

  void addReading(double loudness) {
    readings++;
    if (loudness > peakLoudness) peakLoudness = loudness;
  }

  /// True if [next] is just another reading of this line's note
  bool absorbs(Verdict next) {
    if (next.midi != verdict.midi) return false;
    if (next.kind == verdict.kind && next.ignoredReason == verdict.ignoredReason) return true;
    return verdict.kind == VerdictKind.correct && next.ignoredReason == IgnoredReason.sameAsLastCorrect;
  }
}
