// SA's ABRSM Grade 5 exercises, in SA's order (SA MusicBoardAndGrade.scalesABRSM, grade 5), 30 Oct 2026.

import 'scale.dart';

/// The ABRSM Grade 5 scales and arpeggios as SA lists them (38). Hands-together ones can also be practised
/// with one hand: [Scale.withHands] (SA's Select Hands screen).
List<Scale> abrsmGrade5() {
  const minTempo = 120;
  const arpeggioTempo = 88;
  const octaves = 2;
  const dynamicTypes = <DynamicType>[]; // SA ABRSM: none
  const legato = [ArticulationType.legato];
  final scales = <Scale>[];

  Scale scale(String root, ScaleType type,
          {ScaleMotion motion = ScaleMotion.similarMotion,
          List<int> hands = const [0, 1],
          int tempo = minTempo,
          List<ArticulationType> articulation = legato,
          ScaleCustomisation? customisation}) =>
      Scale(
        scaleRoot: ScaleRoot(root),
        scaleType: type,
        scaleMotion: motion,
        octaves: octaves,
        hands: hands,
        minTempo: tempo,
        dynamicTypes: dynamicTypes,
        articulationTypes: articulation,
        scaleCustomisation: customisation,
      );

  // Both hands
  for (final root in ['A', 'E', 'B', 'F#', 'D♭']) {
    scales.add(scale(root, ScaleType.major));
  }

  // Staccato
  for (final hand in [0, 1]) {
    scales.add(scale('A♭', ScaleType.major, hands: [hand], articulation: const [ArticulationType.staccato]));
    for (final minorType in [ScaleType.harmonicMinor, ScaleType.melodicMinor]) {
      scales.add(scale('F', minorType, hands: [hand], articulation: const [ArticulationType.staccato]));
    }
  }

  // Contrary motion
  scales.add(scale('D♭', ScaleType.major,
      motion: ScaleMotion.contraryMotion,
      customisation: const ScaleCustomisation(customScaleName: 'D♭ Major Contrary Motion')));
  scales.add(scale('C#', ScaleType.harmonicMinor,
      motion: ScaleMotion.contraryMotion,
      customisation: const ScaleCustomisation(
          customScaleName: 'C# Harmonic Minor Contrary Motion', retainWithMelodicSwitch: true)));

  // Chromatic
  scales.add(scale('F#', ScaleType.chromatic,
      motion: ScaleMotion.contraryMotion,
      customisation: const ScaleCustomisation(
          startMidiRH: 70, startMidiLH: 54, customScaleName: 'F#(LH)/A#(RH) Chromatic Contrary Motion')));

  // Minors
  for (final minorType in [ScaleType.harmonicMinor, ScaleType.melodicMinor]) {
    for (final root in ['F#', 'C#', 'G#', 'E♭', 'B♭']) {
      scales.add(scale(root, minorType));
    }
  }

  // Arpeggios
  for (final root in ['A', 'E', 'B', 'F#', 'A♭', 'D♭']) {
    scales.add(scale(root, ScaleType.arpeggioMajor, tempo: arpeggioTempo));
  }
  for (final root in ['F#', 'C#', 'G#', 'E♭', 'F', 'B♭']) {
    scales.add(scale(root, ScaleType.arpeggioMinor, tempo: arpeggioTempo));
  }
  for (final hand in [0, 1]) {
    scales.add(scale('B', ScaleType.arpeggioDiminishedSeventh,
        hands: [hand],
        tempo: arpeggioTempo,
        customisation: const ScaleCustomisation(customScaleName: 'Diminished 7th Arpeggio on B')));
  }
  return scales;
}
