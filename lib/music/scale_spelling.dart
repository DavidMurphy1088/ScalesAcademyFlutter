// Key signature and note spelling for a scale's score, 30 Oct 2026.
// Key signature: as SA (ScalesModel.createScore + MusicStaff/Model/KeySignature.swift).
// Spelling: SA works it out from a staff-position table (StaffClef NoteOffsetsInScaleByKey) with special cases; SAF
// spells notes the musical way instead (each scale step its own letter, arpeggios by chord note) and the chromatic as SA
// does. tool/check_scales.dart compares the result with SA's own spellings (test/sa_reference/abrsm_grade5.json).

import 'scale.dart';

/// A key signature: [count] sharps or flats
class KeySignature {
  final int count;
  final bool flats;

  /// 'major' or 'minor' (SA StaffKey type)
  final String mode;

  const KeySignature(this.count, {required this.flats, required this.mode});

  /// MusicXML fifths: sharps positive, flats negative
  int get fifths => flats ? -count : count;
}

/// A note's spelling: letter (step), alteration (-2..2) and octave, e.g. E#5 = ('E', 1, 5)
class NoteSpelling {
  final String step;
  final int alter;
  final int octave;

  const NoteSpelling(this.step, this.alter, this.octave);

  /// e.g. "E#5", "Ab3", "Fx4" (the names assets/score/score.js reads)
  String get name {
    final accidental = switch (alter) { -2 => 'bb', -1 => 'b', 1 => '#', 2 => 'x', _ => '' };
    return '$step$accidental$octave';
  }

  @override
  String toString() => name;
}

const _steps = ['C', 'D', 'E', 'F', 'G', 'A', 'B'];
const _pitchClass = [0, 2, 4, 5, 7, 9, 11];

/// SA's key for the scale's score: major keys for major-type scales, minor keys for the others;
/// chromatic scales and diminished 7th arpeggios in C (ScalesModel.createScore)
KeySignature keySignatureFor(Scale scale) {
  const majorTypes = [
    ScaleType.major,
    ScaleType.arpeggioMajor,
    ScaleType.arpeggioDominantSeventh,
    ScaleType.arpeggioMajorSeventh,
    ScaleType.chromatic,
    ScaleType.brokenChordMajor,
    ScaleType.trinityBrokenTriad,
  ];
  if (scale.scaleType == ScaleType.chromatic || scale.scaleType == ScaleType.arpeggioDiminishedSeventh) {
    return const KeySignature(0, flats: false, mode: 'major'); // SA: KeySignature(keyName: "C", keyType: .major)
  }
  final keyName = scale.scaleRoot.name;
  if (majorTypes.contains(scale.scaleType)) {
    return switch (keyName) {
      'G' => const KeySignature(1, flats: false, mode: 'major'),
      'F' => const KeySignature(1, flats: true, mode: 'major'),
      'D' => const KeySignature(2, flats: false, mode: 'major'),
      'B♭' => const KeySignature(2, flats: true, mode: 'major'),
      'A' => const KeySignature(3, flats: false, mode: 'major'),
      'E♭' => const KeySignature(3, flats: true, mode: 'major'),
      'E' => const KeySignature(4, flats: false, mode: 'major'),
      'A♭' => const KeySignature(4, flats: true, mode: 'major'),
      'B' => const KeySignature(5, flats: false, mode: 'major'),
      'D♭' => const KeySignature(5, flats: true, mode: 'major'),
      'G♭' => const KeySignature(6, flats: true, mode: 'major'),
      'F#' => const KeySignature(6, flats: false, mode: 'major'),
      _ => const KeySignature(0, flats: false, mode: 'major'),
    };
  }
  return switch (keyName) {
    'E' => const KeySignature(1, flats: false, mode: 'minor'),
    'D' => const KeySignature(1, flats: true, mode: 'minor'),
    'B' => const KeySignature(2, flats: false, mode: 'minor'),
    'G#' => const KeySignature(5, flats: false, mode: 'minor'),
    'G' => const KeySignature(2, flats: true, mode: 'minor'),
    'F#' => const KeySignature(3, flats: false, mode: 'minor'),
    'C' => const KeySignature(3, flats: true, mode: 'minor'),
    'C#' => const KeySignature(4, flats: false, mode: 'minor'),
    'F' => const KeySignature(4, flats: true, mode: 'minor'),
    'B♭' => const KeySignature(5, flats: true, mode: 'minor'),
    'E♭' => const KeySignature(6, flats: true, mode: 'minor'),
    'A♭' => const KeySignature(7, flats: true, mode: 'minor'),
    _ => const KeySignature(0, flats: false, mode: 'minor'), // A minor (and SA's default)
  };
}

/// The root's letter (0-6 for C-B) and alteration from SA's root name: "F#" -> (3, +1), "D♭" -> (1, -1)
(int, int) _rootLetter(String rootName) {
  final letter = _steps.indexOf(rootName[0]);
  var alter = 0;
  for (final ch in rootName.substring(1).split('')) {
    if (ch == '#') alter++;
    if (ch == '♭' || ch == 'b') alter--;
  }
  return (letter, alter);
}

/// How many letters above the root a note is, from its distance above the root in semitones (0-11)
Map<int, int> _lettersAboveRoot(ScaleType type) {
  switch (type) {
    case ScaleType.major:
      return const {0: 0, 2: 1, 4: 2, 5: 3, 7: 4, 9: 5, 11: 6};
    case ScaleType.naturalMinor || ScaleType.harmonicMinor || ScaleType.melodicMinor:
      // melodic minor: raised 6th and 7th going up (9, 11), lowered coming down (8, 10)
      return const {0: 0, 2: 1, 3: 2, 5: 3, 7: 4, 8: 5, 9: 5, 10: 6, 11: 6};
    default:
      // Arpeggios, broken chords: root, 3rd, 5th, 7th (diminished 7th = 9 semitones, a 7th)
      return const {0: 0, 3: 2, 4: 2, 6: 4, 7: 4, 8: 4, 9: 6, 10: 6, 11: 6};
  }
}

NoteSpelling _spell(int midi, int letter) {
  final natural = _pitchClass[letter];
  var alter = (midi - natural) % 12;
  if (alter > 6) alter -= 12;
  final octave = (midi - alter - natural) ~/ 12 - 1;
  return NoteSpelling(_steps[letter], alter, octave);
}

/// SA's chromatic spellings (the key of C column of NoteOffsetsInScaleByKey): letters above C and accidental
/// for each pitch class: C, D♭, D, D#, E, F, F#, G, A♭, A, B♭, B
const _chromaticDefault = [
  (0, 0), (1, -1), (1, 0), (1, 1), (2, 0), (3, 0), (3, 1), (4, 0), (5, -1), (5, 0), (6, -1), (6, 0),
];

/// The spelling of each note of each hand (index 0 right, 1 left) for the scale's score.
/// Chromatic (as SA ScalesModel.createScore adjustNotePlacementForChromatic): the first accidental drawn - right hand
/// first when it is shown - decides sharps or flats for the whole score.
List<List<NoteSpelling>> spellScale(Scale scale) {
  final result = <List<NoteSpelling>>[[], []];
  if (scale.scaleType == ScaleType.chromatic) {
    final order = [if (scale.hands.contains(0)) 0, if (scale.hands.contains(1)) 1];
    int? firstAccidental;
    for (final hand in order) {
      for (final note in scale.notesOf(hand)) {
        final accidental = _chromaticDefault[note.midi % 12].$2;
        if (accidental != 0) {
          firstAccidental = accidental;
          break;
        }
      }
      if (firstAccidental != null) break;
    }
    for (final hand in [0, 1]) {
      for (final note in scale.notesOf(hand)) {
        var (letter, accidental) = _chromaticDefault[note.midi % 12];
        if (accidental != 0 && firstAccidental != null && accidental != firstAccidental) {
          letter = accidental == -1 ? letter - 1 : letter + 1;
        }
        result[hand].add(_spell(note.midi, letter % 7));
      }
    }
    return result;
  }

  final (rootLetter, rootAlter) = _rootLetter(scale.scaleRoot.name);
  final rootPitchClass = (_pitchClass[rootLetter] + rootAlter) % 12;
  final letters = _lettersAboveRoot(scale.scaleType);
  for (final hand in [0, 1]) {
    for (final note in scale.notesOf(hand)) {
      final above = (note.midi - rootPitchClass) % 12;
      final steps = letters[above];
      if (steps == null) {
        throw StateError('${scale.identificationKey}: no letter for a note $above semitones above the root');
      }
      result[hand].add(_spell(note.midi, (rootLetter + steps) % 7));
    }
  }
  return result;
}
