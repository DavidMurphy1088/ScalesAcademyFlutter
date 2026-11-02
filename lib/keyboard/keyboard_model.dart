import 'dart:async';

import 'package:flutter/foundation.dart';

import '../music/scale.dart';

/// SA PianoKeyHilightType: a key's background colour
enum KeyHighlight { none, followThisNote, middleOfKeyboard, wasWrongNote, playedCorrectly }

/// SA HandType for a key (a joined contrary-motion keyboard has keys for both hands)
enum KeyHand { left, right }

/// One key of a keyboard (SA PianoKeyModel)
class PianoKey {
  final KeyboardModel keyboard;

  /// Position on the keyboard, from 0 at the lowest key (SA keyOffsetFromLowestKey)
  final int keyIndex;

  /// The MIDI note the key was made for (0 for the filler keys of a joined keyboard: SA quirk, see [noteMidi])
  final int midi;
  final KeyHand hand;

  /// The scale note this key plays at the moment, if any (it changes between ascending and descending)
  ScaleNoteState? scaleNoteState;

  /// The key was just played and its note is sounding: a ring in the finger colour (red outside the scale)
  bool isSounding = false;
  KeyHighlight highlight = KeyHighlight.none;

  /// A finger is on the key on the screen
  bool touchDown = false;

  PianoKey(this.keyboard, this.keyIndex, this.midi, this.hand);

  /// The note the key sounds (SA noteMidiNumber): the keyboard's first key plus the key's position
  int get noteMidi => keyboard.firstKeyMidi + keyIndex;

  bool get isNatural => const [0, 2, 4, 5, 7, 9, 11].contains(noteMidi % 12);

  /// SA finger number text: the scale note's finger, or '' (fingers over 5 are markers, not shown)
  String get fingerText {
    final state = scaleNoteState;
    if (state == null) return '';
    return state.finger > 5 ? '' : '${state.finger}';
  }
}

/// A keyboard for one hand, or both hands joined (contrary motion) - SA PianoKeyboardModel.
/// The view repaints when it notifies.
class KeyboardModel extends ChangeNotifier {
  final String name;

  /// SA keyboardNumber: 1 right hand, 2 left hand, 30 joined (lowest value 1, as SA)
  final int keyboardNumber;

  final List<PianoKey> keys = [];
  final Map<int, int> _midiToKeyIndex = {};
  int firstKeyMidi = 60;

  /// SA numberOfKeys. For a joined keyboard this leaves out the filler keys (SA quirk: the top keys of the
  /// joined keyboard are then not relinked when the direction changes)
  int numberOfKeys = 18;

  /// Red ring for a played note that isn't in the scale (SA: turned off while the scale is played to the user)
  bool hilightNotesOutsideScale = true;

  /// SA scaleDirection: 0 colours fingers by the upward break, otherwise by the downward break
  int scaleDirection = 0;

  KeyboardModel(this.name, this.keyboardNumber);

  /// 0 right hand, 1 left hand, other values (joined keyboard) neither - SA ClassicStyle's hand
  int get hand => keyboardNumber - 1;

  int get naturalKeyCount => keys.where((k) => k.isNatural).length;

  /// SA getKeyIndexForMidi
  int? keyIndexForMidi(int midi) => _midiToKeyIndex[midi];

  /// SA getKeyBoardStartAndSize: the first key (a C or an F below the scale) and how many keys to show
  static (int, int) startAndSize(Scale scale, KeyHand handType) {
    final hand = handType == KeyHand.right ? 0 : 1;
    final int lowestIndex;
    if (handType == KeyHand.right) {
      lowestIndex = 0;
    } else {
      // For contrary motion the left hand starts high and goes low: the lowest note is in the middle
      lowestIndex = scale.scaleMotion == ScaleMotion.contraryMotion ? scale.scaleNoteState[1].length ~/ 2 : 0;
    }
    var lowestKeyMidi = scale.scaleNoteState[hand][lowestIndex].midi;
    final startMidi = scale.scaleNoteState[hand][0].midi % 12;
    const keyDelta = [0, 1, 2, 3, 4, 0, 1, 2, 3, 4, 5, 6];
    lowestKeyMidi -= keyDelta[startMidi];
    var numKeys = scale.octaves * 12 + 1;
    numKeys += 2;
    // E, G, A, A♭, E♭
    if (const [4, 7, 9, 8, 3].contains(startMidi)) numKeys += 4;
    // B, B♭
    if (const [11, 10].contains(startMidi)) numKeys += 6;
    if (scale.scaleType.isBrokenChord) numKeys += 4;
    return (lowestKeyMidi, numKeys);
  }

  /// SA configureKeyboardForExercise
  void configureForExercise(Scale scale, KeyHand handType, {int scaleSegment = 0}) {
    final (first, count) = startAndSize(scale, handType);
    firstKeyMidi = first;
    numberOfKeys = count;
    keys.clear();
    _midiToKeyIndex.clear();
    for (var i = 0; i < numberOfKeys; i++) {
      final midi = firstKeyMidi + i;
      keys.add(PianoKey(this, i, midi, handType));
      _midiToKeyIndex[midi] = i;
    }
    linkScaleFingersToKeys(scale, scaleSegment, handType, 0);
  }

  /// SA joinKeyboard: this (left hand) keyboard and [rightHand]'s keys above the left hand's highest scale note,
  /// on one keyboard, for hands-together contrary motion
  KeyboardModel joinedWith(KeyboardModel rightHand) {
    final merged = KeyboardModel('merged', (keyboardNumber + rightHand.keyboardNumber) * 10);
    PianoKey? lowestRhInScale;
    for (final key in rightHand.keys) {
      if (key.scaleNoteState != null) {
        lowestRhInScale = key;
        break;
      }
    }
    PianoKey? highestLhInScale;
    for (final key in keys.reversed) {
      if (key.scaleNoteState != null) {
        highestLhInScale = key;
        break;
      }
    }
    if (lowestRhInScale == null || highestLhInScale == null) return this;

    var offset = 0;
    var keyCount = 0;
    PianoKey? lastKey;
    for (final key in keys) {
      if (key.midi >= lowestRhInScale.midi) break;
      final newKey = PianoKey(merged, offset++, key.midi, key.hand)..scaleNoteState = key.scaleNoteState;
      merged.keys.add(newKey);
      lastKey = newKey;
      keyCount++;
    }
    // Fill the gap if the right hand doesn't start where the left hand's scale ends (e.g. Grade 5 chromatic:
    // left hand starts on C, right hand on E)
    if (highestLhInScale.midi != lowestRhInScale.midi && lastKey != null) {
      final missingKeys = lowestRhInScale.midi - lastKey.midi - 1;
      for (var i = 0; i < missingKeys; i++) {
        merged.keys.add(PianoKey(merged, offset++, 0, KeyHand.right));
      }
    }
    for (final key in rightHand.keys) {
      if (key.midi < lowestRhInScale.midi) continue;
      merged.keys.add(PianoKey(merged, offset++, key.midi, key.hand)..scaleNoteState = key.scaleNoteState);
      keyCount++;
    }
    merged.numberOfKeys = keyCount;
    merged.firstKeyMidi = firstKeyMidi;
    for (var i = 0; i < merged.numberOfKeys; i++) {
      merged._midiToKeyIndex[merged.firstKeyMidi + i] = i;
    }
    return merged;
  }

  /// SA resetLinkScaleFingersToKeyboardKeys
  void resetLinks() {
    for (var i = 0; i < numberOfKeys && i < keys.length; i++) {
      keys[i].scaleNoteState = null;
    }
  }

  /// SA linkScaleFingersToKeyboardKeys: link each key to its scale note in [scaleSegment], if it has one.
  /// The links change with direction: e.g. the melodic minor's notes differ going down.
  void linkScaleFingersToKeys(Scale scale, int scaleSegment, KeyHand handType, int direction) {
    scaleDirection = direction;
    for (var i = 0; i < numberOfKeys && i < keys.length; i++) {
      final key = keys[i];
      final state = stateForMidi(scale, handType, key.midi, scaleSegment);
      if (state != null) key.scaleNoteState = state;
    }
  }

  /// SA Scale.getStateForMidi
  static ScaleNoteState? stateForMidi(Scale scale, KeyHand handType, int midi, int scaleSegment) {
    final hand = handType == KeyHand.right ? 0 : 1;
    for (final state in scale.scaleNoteState[hand]) {
      if (state.segments.contains(scaleSegment) && state.midi == midi) return state;
    }
    return null;
  }

  /// SA setKeyPlaying: the key's ring shows for [duration] (SA keySoundingSeconds 0.8 s)
  void setKeyPlaying(int keyIndex, {Duration duration = const Duration(milliseconds: 800)}) {
    if (keyIndex < 0 || keyIndex >= keys.length) return;
    final key = keys[keyIndex];
    key.isSounding = true;
    // As SA: each play clears the ring after its own time, even if the key was played again meanwhile
    Timer(duration, () {
      key.isSounding = false;
      redraw();
    });
    redraw();
  }

  /// Turns a key's ring on or off with no timer (playing the scale to the user: legato, until the next note)
  void setKeySounding(int keyIndex, bool on) {
    if (keyIndex < 0 || keyIndex >= keys.length) return;
    keys[keyIndex].isSounding = on;
    redraw();
  }

  void clearSounding() {
    for (final key in keys) {
      key.isSounding = false;
    }
    redraw();
  }

  /// SA clearKeyHilights(ofType:)
  void clearHighlights(KeyHighlight type) {
    for (var i = 0; i < numberOfKeys && i < keys.length; i++) {
      if (keys[i].highlight == type) keys[i].highlight = KeyHighlight.none;
    }
  }

  bool _disposed = false;

  void redraw() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
