// Port of Scales Academy's scale model (SA ScalesAcademy/Model/Scale.swift, ScaleRoot.swift), 30 Oct 2026.
// Kept as close to SA as possible - including its quirks - so SAF plays, scores and fingers every scale exactly as SA.
// Plain Dart (no Flutter), so it can be checked with `dart run tool/check_scales.dart`.

/// SA ScaleType
enum ScaleType {
  all,
  major,
  naturalMinor,
  harmonicMinor,
  melodicMinor,
  arpeggioMajor,
  arpeggioMinor,
  arpeggioDiminished,
  arpeggioDominantSeventh,
  arpeggioMajorSeventh,
  arpeggioMinorSeventh,
  arpeggioDiminishedSeventh,
  arpeggioHalfDiminished,
  brokenChordMajor,
  brokenChordMinor,
  chromatic,
  trinityBrokenTriad;

  bool get isMajor =>
      this == major ||
      this == arpeggioMajor ||
      this == arpeggioDominantSeventh ||
      this == arpeggioMajorSeventh ||
      this == chromatic ||
      this == brokenChordMajor;

  bool get isBrokenChord => this == brokenChordMajor || this == brokenChordMinor;

  String get description => switch (this) {
        all => 'All',
        major => 'Major',
        naturalMinor => 'Natural Minor',
        harmonicMinor => 'Harmonic Minor',
        melodicMinor => 'Melodic Minor',
        arpeggioMajor => 'Major Arpeggio',
        arpeggioMinor => 'Minor Arpeggio',
        arpeggioDiminished => 'Diminished Arpeggio',
        arpeggioDominantSeventh => 'Dom 7th Arpeggio',
        arpeggioMajorSeventh => 'Major 7th Arpeggio',
        arpeggioMinorSeventh => 'Minor 7th Arpeggio',
        arpeggioDiminishedSeventh => 'Diminished 7th Arpeggio',
        arpeggioHalfDiminished => 'Half Dim Arpeggio',
        chromatic => 'Chromatic',
        brokenChordMajor => 'Major Broken Chord',
        brokenChordMinor => 'Minor Broken Chord',
        trinityBrokenTriad => 'Broken Triad',
      };
}

/// SA ScaleMotion
enum ScaleMotion {
  similarMotion,
  contraryMotion,
  all;

  String get description => switch (this) {
        all => 'All',
        similarMotion => 'Similar Motion',
        contraryMotion => 'Contrary Motion',
      };
}

/// SA DynamicType
enum DynamicType {
  p,
  mf,
  f;

  String get description => switch (this) { mf => 'Mezzo-Forte', p => 'Piano', f => 'Forte' };
  String get descriptionShort => name;
}

/// SA ArticulationType
enum ArticulationType {
  legato,
  staccato;

  String get description => name;
}

/// SA KeyboardColourType: how a keyboard key's finger number is coloured
/// (fingeringSequenceBreak = the orange finger after a thumb crossing / new hand position)
enum KeyboardColourType { none, fingeringSequenceBreak, bySegment }

/// SA ScaleShape (for fingering)
enum ScaleShape { none, scale, arpeggio, arpeggio4Note, brokenChord }

/// SA ScaleCustomisation: per-scale exceptions
class ScaleCustomisation {
  final int? startMidiRH;
  final int? startMidiLH;
  final bool? clefSwitch;
  final int? maxAccidentalLookback;
  final String? customScaleName;
  final String? customScaleNameWheel;
  final String? customScaleNameRH;
  final String? customScaleNameLH;
  final bool? removeKeySig;

  /// Some harmonic scales (e.g. ABRSM G4 contrary harmonic) must remain in the practice when melodic is set
  final bool? retainWithMelodicSwitch;

  const ScaleCustomisation({
    this.startMidiRH,
    this.startMidiLH,
    this.clefSwitch,
    this.maxAccidentalLookback,
    this.customScaleName,
    this.customScaleNameWheel,
    this.customScaleNameRH,
    this.customScaleNameLH,
    this.removeKeySig,
    this.retainWithMelodicSwitch,
  });
}

/// SA ScaleNoteState: one note of one hand's scale
class ScaleNoteState {
  final int sequence;
  int midi;

  /// In crotchets: 0.5 = quaver (SA StaffNote.VALUE_QUAVER), 1.0 = crotchet
  double value;
  int finger = 0;
  KeyboardColourType keyboardFingerColourTypeUp = KeyboardColourType.none;
  KeyboardColourType keyboardFingerColourTypeDown = KeyboardColourType.none;

  /// Which part of the scale the note is in (0 = first way up, 1 = first way down, ...);
  /// the top note of a scale is in both
  List<int> segments;

  ScaleNoteState({required this.sequence, required this.midi, required this.value, required List<int> segment})
      : segments = List.of(segment);

  bool get isWhiteKey => const [0, 2, 4, 5, 7, 9, 11].contains(midi % 12);
}

/// SA TimeSignature (top/bottom only)
class TimeSignature {
  final int top;
  final int bottom;
  const TimeSignature(this.top, this.bottom);
}

/// SA ScaleRoot: the scale's key note name, as SA writes it: "C", "F#", "D♭", "B♭", ...
class ScaleRoot {
  final String name;
  const ScaleRoot(this.name);
}

const double valueQuaver = 0.5; // SA StaffNote.VALUE_QUAVER
const double valueTriplet = 0.333333333333333333333; // SA StaffNote.VALUE_TRIPLET

/// SA Scale: the notes of a scale or arpeggio for both hands (always both, whatever [hands] says), with their
/// note values, fingering, finger-break colours and segments.
class Scale {
  final ScaleRoot scaleRoot;
  final ScaleType scaleType;
  final ScaleMotion scaleMotion;
  final int octaves;

  /// 0 = right hand, 1 = left hand: [0], [1] or [0, 1] (hands together)
  final List<int> hands;
  final int minTempo;
  final List<DynamicType> dynamicTypes;
  final List<ArticulationType> articulationTypes;
  final ScaleCustomisation? scaleCustomisation;
  late final TimeSignature timeSignature;
  ScaleShape scaleShapeForFingering = ScaleShape.none;
  int notesPerSegment = 0;

  /// [0] right hand, [1] left hand
  final List<List<ScaleNoteState>> scaleNoteState = [];

  Scale({
    required this.scaleRoot,
    required this.scaleType,
    required this.scaleMotion,
    required this.octaves,
    required this.hands,
    required this.minTempo,
    this.dynamicTypes = const [],
    this.articulationTypes = const [ArticulationType.legato],
    this.scaleCustomisation,
  }) {
    _build();
  }

  /// The same exercise for other hands (SA SelectHandForPractice: "Practise Left Hand" etc.)
  Scale withHands(List<int> newHands) => Scale(
        scaleRoot: scaleRoot,
        scaleType: scaleType,
        scaleMotion: scaleMotion,
        octaves: octaves,
        hands: newHands,
        minTempo: minTempo,
        dynamicTypes: dynamicTypes,
        articulationTypes: articulationTypes,
        scaleCustomisation: scaleCustomisation,
      );

  void _build() {
    timeSignature = scaleType.isBrokenChord ? const TimeSignature(3, 8) : const TimeSignature(4, 4);

    // Scale start note (https://musescore.com/user/27091525/scores/6509601)
    var firstMidi = scaleCustomisation?.startMidiRH ?? 0;
    if (firstMidi == 0) {
      firstMidi = switch (scaleRoot.name) {
        'C' => 60,
        'C#' => 61,
        'D♭' => 61,
        'D' => 62,
        'D#' => 63,
        'E♭' => 63,
        'E' => 64,
        'F' => 65,
        'F#' => 66,
        'G♭' => 66,
        'G' => 67,
        'G#' => 68,
        'A♭' => 68,
        'A' => 69,
        'A#' => 70 - 12,
        'B♭' => 70 - 12,
        'B' => 71 - 12,
        _ => 60,
      };
    }

    if (const [ScaleType.major, ScaleType.naturalMinor, ScaleType.harmonicMinor, ScaleType.melodicMinor]
        .contains(scaleType)) {
      scaleShapeForFingering = ScaleShape.scale;
      notesPerSegment = (octaves * 7) + 1;
    }
    if (const [ScaleType.arpeggioMajor, ScaleType.arpeggioMinor, ScaleType.arpeggioDiminished].contains(scaleType)) {
      scaleShapeForFingering = ScaleShape.arpeggio;
      notesPerSegment = (octaves * 3) + 1;
    }
    if (scaleType.isBrokenChord) {
      notesPerSegment = 3;
      scaleShapeForFingering = ScaleShape.brokenChord;
    }
    if (const [
      ScaleType.arpeggioMajorSeventh,
      ScaleType.arpeggioMinorSeventh,
      ScaleType.arpeggioDominantSeventh,
      ScaleType.arpeggioDiminishedSeventh
    ].contains(scaleType)) {
      notesPerSegment = (octaves * 4) + 1;
      scaleShapeForFingering = ScaleShape.arpeggio4Note;
    }
    if (scaleType == ScaleType.chromatic) notesPerSegment = (octaves * 12) + 1;
    if (scaleType == ScaleType.trinityBrokenTriad) notesPerSegment = 3;

    // MIDI values, going up
    final scaleOffsets = getScaleOffsets(scaleType);
    final scaleNoteValue = scaleType.isBrokenChord ? valueTriplet : valueQuaver;

    int getSegment(int hand) {
      final totalValue = getTotalNoteValueInScale(hand);
      var seg = (totalValue / scaleNoteValue) / notesPerSegment.toDouble();
      if (scaleNoteValue != scaleNoteValue.truncateToDouble()) {
        // truncating... total value 4.9999999 should be segment 5, not 4
        seg += 0.0001;
      }
      if (seg.isNaN || seg.isInfinite) return 0;
      return seg.toInt();
    }

    for (final handIndex in [0, 1]) {
      var sequence = 0;
      var nextMidi = getStartMidi(handIndex, firstMidi);
      scaleNoteState.add([]);
      final notes = scaleNoteState[handIndex];
      if (scaleType == ScaleType.trinityBrokenTriad) {
        notes.add(ScaleNoteState(sequence: 0, midi: nextMidi, value: 0.5, segment: [0]));
        notes.add(ScaleNoteState(sequence: 1, midi: nextMidi + 4, value: 0.5, segment: [0]));
        notes.add(ScaleNoteState(sequence: 2, midi: nextMidi + 7, value: 0.5, segment: [0, 1]));
        notes.add(ScaleNoteState(sequence: 3, midi: nextMidi + 4, value: 0.5, segment: [1]));
        notes.add(ScaleNoteState(sequence: 4, midi: nextMidi, value: 0.5, segment: [1]));
        continue;
      }
      for (var oct = 0; oct < octaves; oct++) {
        for (var i = 0; i < scaleOffsets.length; i++) {
          var noteValue = scaleNoteValue;
          if (scaleType.isBrokenChord && sequence == 9) noteValue *= 3;
          if (oct == 0) {
            final segment = getSegment(handIndex);
            notes.add(ScaleNoteState(sequence: sequence, midi: nextMidi, value: noteValue, segment: [segment]));
            nextMidi += scaleOffsets[i];
          } else {
            final segment = getSegment(handIndex);
            notes.add(ScaleNoteState(
                sequence: sequence,
                midi: notes[i % scaleOffsets.length].midi + (oct * 12),
                value: noteValue,
                segment: [segment]));
          }
          sequence++;
        }
        // The top note
        if (oct == octaves - 1) {
          var noteValue = scaleNoteValue;
          if (scaleType.isBrokenChord && sequence == 9) noteValue *= 3;
          final segment = getSegment(handIndex);
          // The top note is in the upward and downward segment, i.e. it shows in both
          final segments = scaleType.isBrokenChord ? [segment] : [segment, segment + 1];
          notes.add(ScaleNoteState(
              sequence: sequence, midi: notes[0].midi + octaves * 12, value: noteValue, segment: segments));
          sequence++;
        }
      }
    }

    // Coming down: mirror the notes going up. (SA: ctr is not reset between the hands)
    final up = [for (final hand in scaleNoteState) List.of(hand)];
    var ctr = 0;
    var lastMidi = 0;
    final downHands = scaleType == ScaleType.trinityBrokenTriad ? <int>[] : [0, 1];
    for (final handIndex in downHands) {
      var sequence = 0;
      for (var i = up[handIndex].length - 2; i >= 0; i--) {
        var downMidi = up[handIndex][i].midi;
        final downValue = up[handIndex][i].value;
        if (scaleType == ScaleType.melodicMinor) {
          if (i > 0) {
            if (ctr % 7 == 0) downMidi -= 1;
            if (ctr % 7 == 1) downMidi -= 1;
          }
        }
        final segment = getSegment(handIndex);
        scaleNoteState[handIndex].add(ScaleNoteState(sequence: sequence, midi: downMidi, value: downValue, segment: [segment]));
        lastMidi = downMidi;
        ctr++;
        sequence++;
      }
      if (scaleType.isBrokenChord) {
        final segment = getSegment(handIndex);
        scaleNoteState[handIndex]
            .add(ScaleNoteState(sequence: sequence, midi: lastMidi + 7, value: scaleNoteValue * 3, segment: [segment]));
      }
    }

    // Contrary motion: the left hand starts on the right hand's start pitch and goes down then up,
    // so its two halves are swapped
    if (scaleMotion == ScaleMotion.contraryMotion) {
      const leftHand = 1;
      final left = scaleNoteState[leftHand];
      final middleIndex = (left.length ~/ 2) + 1;
      final firstPart = left.sublist(0, middleIndex);
      final secondPart = left.sublist(left.length - middleIndex);
      final segmentsOfBottomNote = List.of(left[middleIndex - 1].segments);

      final newLeft = <ScaleNoteState>[];
      // For octaves > 1 the top of the left hand scale is higher than the start of the right hand scale: remove that overlap
      final leftOverlapWithRight = octaves == 1 ? 0 : 12;
      for (final state in secondPart) {
        newLeft.add(ScaleNoteState(sequence: 0, midi: state.midi - leftOverlapWithRight, value: state.value, segment: [0]));
      }
      for (var i = 1; i < firstPart.length; i++) {
        newLeft.add(ScaleNoteState(
            sequence: 0, midi: firstPart[i].midi - leftOverlapWithRight, value: firstPart[i].value, segment: [1]));
      }
      scaleNoteState[leftHand] = newLeft;
      // The last note value is now in the middle of the scale ... so exchange it
      final lastNoteValue = newLeft[middleIndex - 1].value;
      final firstNoteValue = newLeft[0].value;
      newLeft[middleIndex - 1].value = firstNoteValue;
      newLeft[newLeft.length - 1].value = lastNoteValue;
      // The highest note had segments 1 and 2: they move to the new lowest note (the turnaround)
      newLeft[middleIndex - 1].segments = segmentsOfBottomNote;
    }

    // The last note is a crotchet
    for (final handIndex in [0, 1]) {
      if (scaleNoteState[handIndex].isNotEmpty) scaleNoteState[handIndex].last.value = 1.0;
    }

    // Fingering
    for (final hand in [0, 1]) {
      _setFingers(hand);
      if (scaleType.isBrokenChord) {
        // Broken chords colour the chord arpeggios by segment
        for (final handStates in scaleNoteState) {
          for (final state in handStates) {
            state.keyboardFingerColourTypeUp = KeyboardColourType.bySegment;
            state.keyboardFingerColourTypeDown = KeyboardColourType.bySegment;
          }
        }
      } else {
        _setFingerBreaks(hand);
      }
    }
  }

  /// The start MIDI for the scale and hand (it may be set by the scale's customisation)
  int getStartMidi(int hand, int midi) {
    var startMidi = midi;
    final c = scaleCustomisation;
    if (c != null) {
      if (hand == 0 && c.startMidiRH != null) return c.startMidiRH!;
      if (hand == 1 && c.startMidiLH != null) return c.startMidiLH!;
    }
    if (hand == 1) {
      startMidi = midi - 12;
      if (scaleMotion == ScaleMotion.similarMotion) {
        if (startMidi >= 53) startMidi -= 12;
      }
    }
    if (octaves > 1) {
      if (hand == 0) {
        if (startMidi >= 65) startMidi -= 12;
      }
    }
    return startMidi;
  }

  static List<int> getScaleOffsets(ScaleType scaleType) => switch (scaleType) {
        ScaleType.all => const [],
        ScaleType.major => const [2, 2, 1, 2, 2, 2, 1],
        ScaleType.naturalMinor => const [2, 1, 2, 2, 1, 2, 2],
        ScaleType.harmonicMinor => const [2, 1, 2, 2, 1, 3, 1],
        ScaleType.melodicMinor => const [2, 1, 2, 2, 2, 2, 1],
        ScaleType.arpeggioMajor => const [4, 3, 4],
        ScaleType.arpeggioMinor => const [3, 4, 4],
        ScaleType.arpeggioDiminished => const [3, 3, 6],
        ScaleType.arpeggioDominantSeventh => const [4, 3, 3, 2],
        ScaleType.arpeggioMajorSeventh => const [4, 3, 4, 1],
        ScaleType.arpeggioMinorSeventh => const [3, 4, 3, 2],
        ScaleType.arpeggioHalfDiminished => const [3, 3, 4, 2],
        ScaleType.arpeggioDiminishedSeventh => const [3, 3, 3, 3],
        ScaleType.chromatic => const [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
        ScaleType.brokenChordMajor => const [4, 3, -3, 3, 5, -5, 5, 4, -4],
        ScaleType.brokenChordMinor => const [3, 4, -4, 4, 5, -5, 5, 3, -3],
        ScaleType.trinityBrokenTriad => const [4, 3, -3, -4, 0],
      };

  double getTotalNoteValueInScale(int handIndex) {
    var total = 0.0;
    for (final state in scaleNoteState[handIndex]) {
      total += state.value;
    }
    return total;
  }

  /// SA getHighPointIndex: note that SA reads the right hand's notes for either hand
  int getHighPointIndex(int hand) {
    var maxMidi = 0;
    var highPointIndex = 0;
    for (var i = 0; i < scaleNoteState[hand].length; i++) {
      final noteState = scaleNoteState[0][i];
      if (noteState.midi > maxMidi) {
        maxMidi = noteState.midi;
        highPointIndex = i;
      }
    }
    return highPointIndex;
  }

  /// Finger sequence breaks (SA setFingerBreaks); descending is the key one below the ascending break key
  void _setFingerBreaks(int hand) {
    final notes = scaleNoteState[hand];
    for (final note in notes) {
      note.keyboardFingerColourTypeUp = KeyboardColourType.none;
      note.keyboardFingerColourTypeDown = KeyboardColourType.none;
    }
    final highPointIndex = getHighPointIndex(hand);
    if (hand == 0) {
      for (var i = 0; i < notes.length; i++) {
        if (notes[i].finger == 1) {
          if (i <= highPointIndex) {
            if (i > 0) notes[i].keyboardFingerColourTypeUp = KeyboardColourType.fingeringSequenceBreak;
          }
          if (i >= highPointIndex) {
            // The last note of a scale is never a finger break
            if (i < notes.length - 1) notes[i + 1].keyboardFingerColourTypeDown = KeyboardColourType.fingeringSequenceBreak;
          }
        }
      }
    } else {
      for (var i = 0; i < notes.length; i++) {
        if (notes[i].finger == 1) {
          if (i <= highPointIndex) {
            // Contrary motion logic needed since LH is reversed in contrary
            if (scaleMotion == ScaleMotion.contraryMotion) {
              if (i > 0) notes[i].keyboardFingerColourTypeUp = KeyboardColourType.fingeringSequenceBreak;
            } else {
              notes[i + 1].keyboardFingerColourTypeUp = KeyboardColourType.fingeringSequenceBreak;
            }
          }
          if (i >= highPointIndex) {
            if (scaleMotion == ScaleMotion.contraryMotion) {
              if (i < notes.length - 1) notes[i + 1].keyboardFingerColourTypeDown = KeyboardColourType.fingeringSequenceBreak;
            } else {
              // not >= : any finger on the highest note cannot be a break on the direction switch to down
              if (i > highPointIndex) notes[i].keyboardFingerColourTypeDown = KeyboardColourType.fingeringSequenceBreak;
            }
          }
        }
      }
    }
  }

  static int _stringIndexToInt(int index, String fingers) {
    if (fingers.isEmpty) return 0;
    final i = index % fingers.length;
    return int.tryParse(fingers[i]) ?? 0;
  }

  /// SA setFingers (Alfred's page 88). RH read left to right, LH read right to left.
  void _setFingers(int hand) {
    var fingers = '';
    // For LH: the finger jump between scale notes 0 and 1 (Alfred's arpeggio LH: difference between the leftmost two fingers)
    var leftHandLastFingerJump = 1;
    // For RH: the finger jump for the highest note
    var rightHandLastFingerJump = 1;
    List<int>? fingeringSpecifiedByNote;
    const defaultFingers = '1231234';
    final rh = hand == 0;

    if (scaleShapeForFingering == ScaleShape.scale) {
      // For LH the given pattern goes from high to low notes (reversed)
      switch (scaleRoot.name) {
        case 'B':
          fingers = rh ? '1231234' : '1234123';
        case 'F':
          fingers = rh ? '1234123' : '1231234';
        case 'F#':
          if (scaleType == ScaleType.major) {
            fingers = rh ? '2341231' : '4123123';
          } else if (scaleType == ScaleType.harmonicMinor) {
            fingers = rh ? '3412312' : '4123123';
          } else if (rh) {
            fingeringSpecifiedByNote = [2, 3, 1, 2, 3, 4, 1, 2, 3, 1, 2, 3, 4, 1, 3, 2, 1, 3, 2, 1, 4, 3, 2, 1, 3, 2, 1, 3, 2];
          } else {
            fingers = '4123123';
          }
        case 'G♭':
          if (scaleType == ScaleType.major) {
            fingers = rh ? '2341231' : '4123123';
          } else {
            fingers = rh ? '2312341' : '4123123';
          }
        case 'G#':
          fingers = rh ? '3412312' : '212341231234123';
          if (scaleType == ScaleType.melodicMinor) {
            // The melodic down direction changes white note to black and forces a new fingering throughout the descending
            if (!rh) {
              fingeringSpecifiedByNote = [3, 2, 1, 4, 3, 2, 1, 3, 2, 1, 4, 3, 2, 1, 2, 3, 1, 2, 3, 1, 2, 3, 4, 1, 2, 3, 1, 2, 3];
            }
          }
          leftHandLastFingerJump = 0;
        case 'B♭':
          if (scaleType == ScaleType.major) {
            fingers = rh ? '4123123' : '3123412';
          } else {
            fingers = rh ? '4123123' : '2341231';
          }
        case 'E♭':
          if (scaleType == ScaleType.major) {
            fingers = rh ? '3123412' : '3123412';
          } else {
            fingers = rh ? '3123412' : '2312341';
          }
        case 'A♭':
          fingers = rh ? '3412312' : '3123412';
        case 'C#' || 'D♭':
          if (scaleType == ScaleType.major) {
            fingers = rh ? '2312341' : '3123412';
          } else {
            fingers = rh ? '2312341' : '3123412';
            if (rh) {
              if (scaleType == ScaleType.melodicMinor) {
                fingeringSpecifiedByNote = [2, 3, 1, 2, 3, 4, 1, 2, 3, 1, 2, 3, 4, 1, 3, 2, 1, 3, 2, 1, 4, 3, 2, 1, 3, 2, 1, 3, 2];
              } else {
                fingeringSpecifiedByNote = [2, 3, 1, 2, 3, 1, 2, 3, 4, 1, 2, 3, 1, 2, 3, 2, 1, 3, 2, 1, 4, 3, 2, 1, 3, 2, 1, 3, 2];
              }
            }
          }
        default:
          fingers = '';
      }
    }
    if (fingers.isEmpty) fingers = defaultFingers;

    // Three note arpeggio
    if (scaleShapeForFingering == ScaleShape.arpeggio) {
      final major = scaleType == ScaleType.major || scaleType == ScaleType.arpeggioMajor;
      switch (scaleRoot.name) {
        case 'C' || 'G':
          if (scaleType == ScaleType.arpeggioMinor) {
            fingers = rh ? '123' : '124';
          } else {
            fingers = '123';
            leftHandLastFingerJump = 2;
          }
        case 'D' || 'A' || 'E' || 'B':
          if (major) {
            leftHandLastFingerJump = 2;
            fingers = '123';
          } else {
            fingers = rh ? '123' : '124';
          }
        case 'F':
          fingers = rh ? '123' : '124';
        case 'F#':
          if (major) {
            fingers = '123';
            leftHandLastFingerJump = 2;
          }
          if (scaleType == ScaleType.arpeggioMinor) {
            fingeringSpecifiedByNote = rh ? [2, 1, 2, 4, 1, 2, 4, 2, 1, 4, 2, 1, 2] : [2, 1, 4, 2, 1, 4, 2, 4, 1, 2, 4, 1, 2];
          }
        case 'C#' || 'G#':
          fingers = rh ? '412' : '241';
        case 'B♭':
          if (major) {
            fingeringSpecifiedByNote = rh ? [2, 1, 2, 4, 1, 2, 4, 2, 1, 4, 2, 1, 2] : [3, 2, 1, 3, 2, 1, 2, 1, 2, 3, 1, 2, 3];
          } else {
            rightHandLastFingerJump = 0; // Match Trinity for Gr 5
            fingers = rh ? '231' : '312';
          }
        case 'E♭':
          if (major) {
            fingers = rh ? '412' : '241';
          } else {
            fingers = rh ? '123' : '124';
          }
        case 'A♭' || 'D♭':
          fingers = rh ? '412' : '241';
        default:
          fingers = '123';
      }
    }

    // Four note arpeggio
    if (scaleShapeForFingering == ScaleShape.arpeggio4Note) {
      fingers = switch (scaleRoot.name) {
        'B♭' => rh ? '4123' : '2312',
        'E♭' => rh ? '4124' : (scaleType == ScaleType.arpeggioMajorSeventh ? '4123' : '2341'),
        'A♭' => rh ? '4124' : '2341',
        'D♭' => rh ? '4123' : '2341',
        _ => '1234',
      };
    }

    if (scaleType.isBrokenChord) fingers = rh ? '135125135' : '531531521';

    final notes = scaleNoteState[hand];

    void applyFingerPatternToScaleStart(int halfway) {
      var f = 0;
      // The ascending section
      for (var i = 0; i < halfway; i++) {
        notes[i].finger = _stringIndexToInt(i, fingers);
        f++;
      }
      f--;
      var highNoteFinger = _stringIndexToInt(fingers.length - 1, fingers) + 1;
      if (scaleShapeForFingering == ScaleShape.arpeggio) {
        if (highNoteFinger < 5) highNoteFinger += rightHandLastFingerJump;
      }
      notes[halfway].finger = highNoteFinger;
      // The descending section
      for (var i = halfway + 1; i < notes.length; i++) {
        notes[i].finger = _stringIndexToInt(f, fingers);
        f--;
      }
    }

    void applyFingerPatternToScaleMiddle(int halfway) {
      // LH: start at the start of the LH scale then count forwards through the finger pattern, working backwards down
      // the scale and mirroring the fingering around the high note
      var f = 0;
      for (var i = halfway; i >= 0; i--) {
        notes[i].finger = _stringIndexToInt(f, fingers);
        if (!scaleType.isBrokenChord) notes[i + 2 * f].finger = _stringIndexToInt(f, fingers);
        f++;
      }
      if (leftHandLastFingerJump > 0) {
        // Adjust the last note played
        final nextToLastFinger = _stringIndexToInt(fingers.length - 1, fingers);
        notes[0].finger = nextToLastFinger + leftHandLastFingerJump;
        notes[notes.length - 1].finger = nextToLastFinger + leftHandLastFingerJump;
      }
    }

    void applyChromaticFingers() {
      for (final noteState in notes) {
        if (noteState.isWhiteKey) {
          if (rh) {
            noteState.finger = const [0, 5].contains(noteState.midi % 12) ? 2 : 1;
          } else {
            noteState.finger = const [4, 11].contains(noteState.midi % 12) ? 2 : 1;
          }
        } else {
          noteState.finger = 3;
        }
      }
    }

    void applyBrokenChordFingers() {
      final halfway = (notes.length ~/ 2) - 1;
      for (var i = 0; i < halfway; i++) {
        notes[i].finger = _stringIndexToInt(i, fingers);
      }
      notes[halfway].finger = _stringIndexToInt(halfway - 2, fingers);
      final fingersReversed = fingers.split('').reversed.join();
      var ctr = 0;
      for (var i = halfway + 1; i < notes.length; i++) {
        notes[i].finger = _stringIndexToInt(ctr, fingersReversed);
        ctr++;
      }
    }

    // Set the fingering from the finger sequence
    var handled = false;
    if (scaleType == ScaleType.chromatic) {
      applyChromaticFingers();
      handled = true;
    }
    if (scaleType.isBrokenChord) {
      applyBrokenChordFingers();
      handled = true;
    }
    if (scaleType == ScaleType.trinityBrokenTriad) {
      fingeringSpecifiedByNote = [1, 2, 4, 2, 1];
      handled = true;
    }

    // Fingering given note by note
    final byNote = fingeringSpecifiedByNote;
    if (byNote != null) {
      if (byNote.length != notes.length) {
        throw StateError('Wrong fingering count. Specified:${byNote.length} scale:${notes.length}');
      }
      for (var f = 0; f < byNote.length; f++) {
        notes[f].finger = byNote[f];
      }
      handled = true;
    }

    if (!handled) {
      // The regular finger patterns for ascending and descending (the pattern is for the right hand ascending).
      // LH: applied from the middle of the LH scale; LH contrary motion: from the start (the highest note)
      final halfway = notes.length ~/ 2;
      if (rh) applyFingerPatternToScaleStart(halfway);
      if (!rh) {
        if (scaleMotion == ScaleMotion.similarMotion) applyFingerPatternToScaleMiddle(halfway);
        if (scaleMotion == ScaleMotion.contraryMotion) applyFingerPatternToScaleStart(halfway);
      }

      var hasAWhiteKey = false;
      for (var n = 0; n < scaleNoteState[0].length - 1; n++) {
        if (notes[n].isWhiteKey) {
          hasAWhiteKey = true;
          break;
        }
      }

      // Scales starting on a black note: the first and last finger are 2
      if (hasAWhiteKey) {
        if (rh || scaleMotion == ScaleMotion.contraryMotion) {
          // All RH scales and arpeggios starting on a black note have first finger 2, but only the first;
          // after that the regular fingering from the pattern
          for (var n = 0; n < scaleNoteState[0].length - 1; n++) {
            final state = notes[n];
            if (state.isWhiteKey) break;
            state.finger = 2 + n;
            notes[notes.length - n - 1].finger = 2 + n;
          }
        }
        if (!rh && scaleMotion != ScaleMotion.contraryMotion) {
          // All LH scales and arpeggios highest on a black note have finger 2 on that high note
          if (!notes[halfway].isWhiteKey) notes[halfway].finger = 2;
        }
      }
    }
  }

  // ---------------------------------------------------------------- names (SA Scale.swift)

  bool get isHandsTogether => hands.length > 1;

  /// e.g. "Diminished 7th Arpeggio on B" (custom name) or "F Melodic Minor" (SA getScaleName())
  String get scaleName {
    final custom = scaleCustomisation?.customScaleName;
    if (custom != null && custom.isNotEmpty) return custom;
    return '${scaleRoot.name} ${scaleType.description}';
  }

  /// "Right Hand", "Left Hand" or "hands together" (SA getScaleDescriptionParts(hands: true))
  String get handsDescription {
    if (hands.length == 1) {
      return switch (hands[0]) { 0 => 'Right Hand', 1 => 'Left Hand', _ => 'Hands Together' };
    }
    return 'hands together';
  }

  /// SA's scale screen title: "F Melodic Minor, Right Hand"
  String get title => '$scaleName, $handsDescription';

  /// SA getScaleIdentificationKey: e.g. "D♭_Major_Oct_2_Similar_Motion_BothHands"
  String get identificationKey {
    final handsName = hands.isEmpty ? '' : (hands.length == 2 ? 'BothHands' : (hands[0] == 1 ? 'LeftHand' : 'RightHand'));
    var key = '${scaleRoot.name}_${scaleType.description}_Oct_$octaves'
        '_${scaleMotion.description}_$handsName';
    key = key.replaceAll('#', 'Sharp').replaceAll(' ', '_').replaceAll(',', '');
    return key;
  }

  /// SA getRequiredValuePerBar
  int get requiredValuePerBar => scaleType.isBrokenChord ? 1 : 4;

  /// The notes of one hand (0 right, 1 left)
  List<ScaleNoteState> notesOf(int hand) => scaleNoteState[hand];
}
