import '../music/scale.dart';
import '../music/scale_spelling.dart';
import 'score_spec.dart';

/// The score of a scale as SA draws it (Stage 3): SA's key signature, the hands shown (right hand stave first),
/// each note spelled (lib/music/scale_spelling.dart) with SA's note values, and SA's left-hand clef switching
/// unless the scale turns it off.
ScoreSpec scoreSpecForScale(Scale scale) {
  final key = keySignatureFor(scale);
  final spelling = spellScale(scale);
  final staves = <ScoreStave>[
    for (final hand in [0, 1])
      if (scale.hands.contains(hand))
        ScoreStave(
          hand: hand == 0 ? Hand.right : Hand.left,
          notes: [for (final s in spelling[hand]) s.name],
          values: [for (final n in scale.notesOf(hand)) n.value],
        ),
  ];
  return ScoreSpec(
    id: scale.identificationKey,
    name: scale.title,
    tempo: scale.minTempo,
    keyFifths: key.fifths,
    keyMode: key.mode,
    time: [scale.timeSignature.top, scale.timeSignature.bottom],
    clefSwitch: scale.scaleCustomisation?.clefSwitch ?? true,
    staves: staves,
  );
}
