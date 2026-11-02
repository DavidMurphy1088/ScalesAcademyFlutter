import 'package:flutter_test/flutter_test.dart';
import 'package:scales_academy_flutter/keyboard/exercise_keyboards.dart';
import 'package:scales_academy_flutter/music/abrsm_grade5.dart';
import 'package:scales_academy_flutter/music/midi.dart';

/// Stage 4: SA's keyboards for every Grade 5 exercise and hand choice (98) have a key for every note of the scale,
/// and in each part of the scale (up, down, ...) every note's key is linked to that note (so it shows its finger).
void main() {
  test('Every scale note has a linked key in every part of the scale', () {
    final problems = <String>[];
    var checked = 0;
    for (final exercise in abrsmGrade5()) {
      final handChoices = exercise.isHandsTogether ? [exercise.hands, const [0], const [1]] : [exercise.hands];
      for (final hands in handChoices) {
        final scale = hands.length == exercise.hands.length ? exercise : exercise.withHands(hands);
        final keyboards = ExerciseKeyboards(scale);
        final (lo, hi) = keyboards.minMaxSegments;
        checked++;
        for (var segment = lo; segment <= hi; segment++) {
          keyboards.selectSegment(segment);
          for (final hand in scale.hands) {
            final keyboard = keyboards.keyboardFor(hand);
            for (final note in scale.notesOf(hand)) {
              if (!note.segments.contains(segment)) continue;
              final index = keyboard.keyIndexForMidi(note.midi);
              if (index == null) {
                problems.add('${scale.title}: ${midiName(note.midi)} is not on the keyboard');
              } else if (keyboard.keys[index].scaleNoteState == null) {
                problems.add('${scale.title}: part $segment, ${midiName(note.midi)} has no finger');
              }
            }
          }
        }
        keyboards.dispose();
      }
    }
    expect(checked, 98);
    expect(problems, isEmpty);
  });

  test('Contrary motion hands together is one joined keyboard; similar motion is two', () {
    final grade5 = abrsmGrade5();
    final contrary = grade5.firstWhere((s) => s.title.startsWith('D♭ Major Contrary Motion, hands together'));
    expect(ExerciseKeyboards(contrary).shown.length, 1);
    final similar = grade5.firstWhere((s) => s.title == 'A Major, hands together');
    expect(ExerciseKeyboards(similar).shown.length, 2);
  });
}
