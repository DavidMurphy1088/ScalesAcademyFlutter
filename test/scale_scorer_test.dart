import 'package:flutter_test/flutter_test.dart';

import 'package:scales_academy_flutter/music/midi.dart';
import 'package:scales_academy_flutter/exercise/scale_scorer.dart';

void main() {
  final cMajor = buildMajorScale(startMidi: 60, octaves: 2);

  test('two-octave C major from C4 is built as SA builds it', () {
    expect(cMajor.length, 29);
    expect(cMajor.sublist(0, 8), [60, 62, 64, 65, 67, 69, 71, 72]);
    expect(cMajor[14], 84); // top C6, once
    expect(cMajor[15], 83); // back down from B5
    expect(cMajor.last, 60);
  });

  test('playing the whole scale correctly completes it', () {
    final scorer = ScaleScorer(cMajor);
    for (final midi in cMajor) {
      expect(scorer.judge(midi).kind, VerdictKind.correct);
    }
    expect(scorer.completed, isTrue);
    expect(scorer.totalCorrect, 29);
    expect(scorer.judge(60).ignoredReason, IgnoredReason.afterEnd);
  });

  test('held correct note: later readings are ignored as the same note name', () {
    final scorer = ScaleScorer(cMajor);
    expect(scorer.judge(60).kind, VerdictKind.correct);
    final v = scorer.judge(60);
    expect(v.ignoredReason, IgnoredReason.sameAsLastCorrect);
    expect(ScoredLine(Verdict(60, VerdictKind.correct)).absorbs(v), isTrue);
    expect(scorer.progress, 1);
  });

  test('wrong note after a correct note, and held wrong readings', () {
    final scorer = ScaleScorer(cMajor);
    scorer.judge(60);
    expect(scorer.judge(66).kind, VerdictKind.wrong); // F#4, expected D4/E4
    expect(scorer.judge(66).kind, VerdictKind.wrong);
    expect(scorer.wrongReadings, 2);
    expect(scorer.judge(62).kind, VerdictKind.correct);
  });

  test('wrong notes before the first correct note are not judged', () {
    final scorer = ScaleScorer(cMajor);
    expect(scorer.judge(66).ignoredReason, IgnoredReason.beforeFirstCorrect);
  });

  test('one missed note is skipped over by the lookahead', () {
    final scorer = ScaleScorer(cMajor);
    scorer.judge(60);
    final v = scorer.judge(64); // E4, D4 missed
    expect(v.kind, VerdictKind.correct);
    expect(v.skipped, [62]);
    expect(scorer.progress, 3);
  });

  test('an octave of the expected note counts as correct', () {
    final scorer = ScaleScorer(cMajor);
    scorer.judge(60);
    final v = scorer.judge(74); // D5 for D4
    expect(v.kind, VerdictKind.correct);
    expect(v.matchedMidi, 62);
  });

  test('notes far outside the scale are ignored', () {
    final scorer = ScaleScorer(cMajor);
    expect(scorer.judge(40).ignoredReason, IgnoredReason.outOfRange);
    expect(scorer.judge(57).ignoredReason, isNot(IgnoredReason.outOfRange)); // 3 below C4 is still in range
  });

  test('1 and 3 octave scales', () {
    final one = buildMajorScale(startMidi: 60, octaves: 1);
    expect(one.length, 15);
    expect(one[7], 72);
    final three = buildMajorScale(startMidi: 48, octaves: 3);
    expect(three.length, 43);
    expect(three.first, 48);
    expect(three[21], 84); // top C6
    expect(three.last, 48);
  });

  test('letter-name distance between notes (letter only, B and C are neighbours)', () {
    expect(letterDistance(60, 62), 1); // C -> D
    expect(letterDistance(71, 72), 1); // B -> C
    expect(letterDistance(72, 71), 1); // C -> B
    expect(letterDistance(67, 69), 1); // G -> A
    expect(letterDistance(69, 67), 1); // A -> G
    expect(letterDistance(65, 69), 2); // F -> A: flagged
    expect(letterDistance(60, 64), 2); // C -> E: flagged
    expect(letterDistance(60, 72), 0); // C4 -> C5: same letter
    expect(letterDistance(60, 61), 0); // C -> C#: same letter
    expect(letterDistance(60, 65), 3); // C -> F
  });
}
