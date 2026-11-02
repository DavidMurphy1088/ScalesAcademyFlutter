import '../music/scale.dart';
import 'keyboard_model.dart';

/// The keyboards for one exercise, as SA sets them up (ScalesModel.setKeyboardAndScore / configureKeyboards):
///  - one hand: that hand's keyboard
///  - hands together, similar motion: two keyboards, right hand above left (SA ScalesView)
///  - hands together, contrary motion: both hands joined on one keyboard
/// and which part of the scale the fingers show (SA setSelectedScaleSegment: 0 = first way up, 1 = way down, ...).
class ExerciseKeyboards {
  final Scale scale;
  final KeyboardModel rightHand = KeyboardModel('RH', 1);
  final KeyboardModel leftHand = KeyboardModel('LH', 2);
  KeyboardModel? joined;
  int segment = 0;

  ExerciseKeyboards(this.scale) {
    rightHand.configureForExercise(scale, KeyHand.right);
    leftHand.configureForExercise(scale, KeyHand.left);
    selectSegment(0);
    if (scale.scaleMotion == ScaleMotion.contraryMotion && scale.hands.length == 2) {
      joined = leftHand.joinedWith(rightHand);
    }
  }

  /// The keyboards on screen, top to bottom
  List<KeyboardModel> get shown {
    final j = joined;
    if (j != null) return [j];
    if (scale.hands.length > 1) return [rightHand, leftHand];
    return [scale.hands.first == 1 ? leftHand : rightHand];
  }

  /// The keyboard that shows [hand]'s notes (0 right, 1 left) - SA HearScalePlayer.getKeyboard
  KeyboardModel keyboardFor(int hand) => joined ?? (hand == 0 ? rightHand : leftHand);

  /// SA Scale.getMinMaxSegments (from the right hand's notes, as SA)
  (int, int) get minMaxSegments {
    var lo = 1 << 30;
    var hi = -(1 << 30);
    for (final state in scale.scaleNoteState[0]) {
      for (final s in state.segments) {
        if (s < lo) lo = s;
        if (s > hi) hi = s;
      }
    }
    return (lo, hi);
  }

  /// SA directionOfPlay for the segment: true = upwards (reversed for left-hand-only contrary motion)
  bool get isUpwards {
    final reverse = scale.hands.length == 1 && scale.hands.first == 1 && scale.scaleMotion == ScaleMotion.contraryMotion;
    final upward = minMaxSegments.$1 == segment;
    return reverse ? !upward : upward;
  }

  /// SA setSelectedScaleSegment: relink every key to its note in [newSegment] (the fingering and the finger
  /// colours change with direction)
  void selectSegment(int newSegment) {
    segment = newSegment;
    final j = joined;
    if (j != null) {
      j.linkScaleFingersToKeys(scale, newSegment, KeyHand.right, newSegment);
      j.linkScaleFingersToKeys(scale, newSegment, KeyHand.left, newSegment);
      j.redraw();
      return;
    }
    rightHand.resetLinks();
    leftHand.resetLinks();
    rightHand.linkScaleFingersToKeys(scale, newSegment, KeyHand.right, newSegment);
    rightHand.redraw();
    leftHand.linkScaleFingersToKeys(scale, newSegment, KeyHand.left, newSegment);
    leftHand.redraw();
    rightHand.clearHighlights(KeyHighlight.playedCorrectly);
  }

  /// SA SoundEventHandler: show a note that was played (from the microphone, a MIDI keyboard or the screen).
  /// With two keyboards a note may be on both: a note in the scale shows on every keyboard that has it,
  /// a note outside the scale only on the first that has it (left hand first, as SA).
  void showPlayedNote(int midi) {
    final keyboards = scale.hands.length == 1 ? shown : (joined != null ? [joined!] : [leftHand, rightHand]);
    final possible = <(KeyboardModel, int, bool)>[];
    for (final keyboard in keyboards) {
      final index = keyboard.keyIndexForMidi(midi);
      if (index == null) continue;
      // SA: keyboardNumber - 1 == 0 is the right hand, anything else (left, joined) looks in the left hand's notes
      final handType = keyboard.hand == 0 ? KeyHand.right : KeyHand.left;
      final inScale = KeyboardModel.stateForMidi(scale, handType, midi, segment) != null;
      possible.add((keyboard, index, inScale));
    }
    if (possible.isEmpty) return;
    if (keyboards.length == 1) {
      possible.first.$1.setKeyPlaying(possible.first.$2);
      return;
    }
    if (!possible.any((p) => p.$3)) {
      final outOfScale = possible.first;
      outOfScale.$1.setKeyPlaying(outOfScale.$2);
    } else {
      for (final p in possible) {
        p.$1.setKeyPlaying(p.$2);
      }
    }
  }

  /// Red rings for notes outside the scale on or off (SA turns them off while playing the scale to the user)
  set hilightNotesOutsideScale(bool on) {
    for (final k in [rightHand, leftHand, ?joined]) {
      k.hilightNotesOutsideScale = on;
    }
  }

  void clearSounding() {
    for (final k in shown) {
      k.clearSounding();
    }
  }

  void dispose() {
    rightHand.dispose();
    leftHand.dispose();
    joined?.dispose();
  }
}
