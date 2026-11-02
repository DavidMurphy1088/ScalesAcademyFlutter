import 'package:flutter/material.dart';

import '../music/scale.dart';
import 'keyboard_model.dart';

/// SA's colours (FigmaColors in CommonUI.swift)
class SaColors {
  static const green = Color(0xFF9CD762);
  static const blueShade6 = Color(0xFFC0EAEF);
  static const pink = Color(0xFFFF536C);

  /// Finger numbers and rings: purple on the key, orange where the thumb goes under or a finger crosses over
  static const fingerOnKey = Color(0xFF786A85);
  static const fingerOverUnder = Color(0xFFFAA248);
}

/// Where each key is drawn (SA ClassicStyle.layout), shared by the painter, the hand icon and touch handling
class KeyboardLayout {
  final Size size;
  final double naturalWidth;

  /// Indexed by key index
  final List<Rect> keyRects;

  /// The natural key that shows the hand icon, if any
  final int? handIconKey;

  const KeyboardLayout._(this.size, this.naturalWidth, this.keyRects, this.handIconKey);

  /// SA ClassicStyle: naturalKeySpace 1, black keys 0.65 of a white key's width and 0.60 of its height
  static const naturalKeySpace = 1.0;
  static const sfKeyWidthMultiplier = 0.65;
  static const sfKeyHeightMultiplier = 0.60;

  factory KeyboardLayout.of(KeyboardModel model, Size size) {
    final keys = model.keys;
    final naturalCount = model.naturalKeyCount;
    final naturalWidth =
        naturalCount == 0 ? 0.0 : (size.width - naturalKeySpace * (naturalCount - 1)) / naturalCount;
    final rects = List<Rect>.filled(keys.length, Rect.zero);
    int? handIconKey;
    var x = 0.0;
    for (var i = 0; i < keys.length; i++) {
      if (!keys[i].isNatural) continue;
      rects[i] = Rect.fromLTWH(x, 0, naturalWidth, size.height);
      // SA: the hand icon goes in the outermost white key - the lowest for the left hand, the highest for the right
      if (handIconKey == null) {
        if (model.hand == 1 && (i == 0 || i == 1)) handIconKey = i;
        if (model.hand == 0 && i >= keys.length - 2) handIconKey = i;
      }
      x += naturalWidth + naturalKeySpace;
    }
    final sfWidth = naturalWidth * sfKeyWidthMultiplier;
    final sfHeight = size.height * sfKeyHeightMultiplier;
    x = 0;
    for (var i = 0; i < keys.length; i++) {
      if (keys[i].isNatural) {
        x += naturalWidth + naturalKeySpace;
        continue;
      }
      rects[i] = Rect.fromLTWH(x - sfWidth / 2, 0, sfWidth, sfHeight);
    }
    return KeyboardLayout._(size, naturalWidth, rects, handIconKey);
  }

  /// SA getKeyContaining: a black key wins over the white keys beside it
  int? keyAt(Offset point, KeyboardModel model) {
    int? found;
    for (var i = 0; i < keyRects.length && i < model.keys.length; i++) {
      if (keyRects[i].contains(point)) {
        found = i;
        if (!model.keys[i].isNatural) break;
      }
    }
    return found;
  }
}

/// SA's keyboard, drawn as SA's ClassicStyle: white and black keys, finger numbers (purple, or orange where the
/// fingering crosses), a ring on a sounding key, and the hand icon in the outermost key.
/// With [onKeyDown] / [onKeyUp] the keys can be played with several fingers at once.
class PianoKeyboard extends StatefulWidget {
  final KeyboardModel model;
  final Scale scale;
  final bool showFingers;

  /// Called with the MIDI note when a key is pressed or released on the screen; null = not playable
  final void Function(int midi)? onKeyDown;
  final void Function(int midi)? onKeyUp;

  const PianoKeyboard({
    super.key,
    required this.model,
    required this.scale,
    this.showFingers = true,
    this.onKeyDown,
    this.onKeyUp,
  });

  @override
  State<PianoKeyboard> createState() => _PianoKeyboardState();
}

class _PianoKeyboardState extends State<PianoKeyboard> {
  final Map<int, Offset> _pointers = {};
  KeyboardLayout? _layout;

  bool get _playable => widget.onKeyDown != null;

  @override
  void didUpdateWidget(PianoKeyboard old) {
    super.didUpdateWidget(old);
    if (!identical(old.model, widget.model)) _releaseAll(old.model);
  }

  @override
  void dispose() {
    _releaseAll(widget.model);
    super.dispose();
  }

  void _releaseAll(KeyboardModel model) {
    _pointers.clear();
    for (final key in model.keys) {
      if (key.touchDown) {
        key.touchDown = false;
        widget.onKeyUp?.call(key.noteMidi);
      }
    }
  }

  /// SA updateKeysForUpDown (latch off): every key under a finger is down, every other key up
  void _updateKeys() {
    final layout = _layout;
    final model = widget.model;
    if (layout == null) return;
    final down = List<bool>.filled(model.keys.length, false);
    for (final p in _pointers.values) {
      final index = layout.keyAt(p, model);
      if (index != null) down[index] = true;
    }
    var changed = false;
    for (var i = 0; i < model.keys.length; i++) {
      final key = model.keys[i];
      if (key.touchDown == down[i]) continue;
      key.touchDown = down[i];
      if (down[i]) {
        widget.onKeyDown?.call(key.noteMidi);
      } else {
        widget.onKeyUp?.call(key.noteMidi);
      }
      model.setKeyPlaying(i);
      changed = true;
    }
    if (changed) model.redraw();
  }

  @override
  Widget build(BuildContext context) {
    final phone = MediaQuery.sizeOf(context).shortestSide < 600;
    return LayoutBuilder(builder: (context, constraints) {
      final size = Size(constraints.maxWidth, constraints.maxHeight);
      return ListenableBuilder(
        listenable: widget.model,
        builder: (context, _) {
          final layout = KeyboardLayout.of(widget.model, size);
          _layout = layout;
          final iconKey = layout.handIconKey;
          return Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: _playable
                ? (e) {
                    _pointers[e.pointer] = e.localPosition;
                    _updateKeys();
                  }
                : null,
            onPointerMove: _playable
                ? (e) {
                    _pointers[e.pointer] = e.localPosition;
                    _updateKeys();
                  }
                : null,
            onPointerUp: _playable
                ? (e) {
                    _pointers.remove(e.pointer);
                    _updateKeys();
                  }
                : null,
            onPointerCancel: _playable
                ? (e) {
                    _pointers.remove(e.pointer);
                    _updateKeys();
                  }
                : null,
            child: Stack(
              children: [
                // The hand icon sits under the black keys' layer but over the white key (SA draws it with the
                // white keys)
                CustomPaint(
                  size: size,
                  painter: _WhiteKeysPainter(widget.model, widget.scale, layout, widget.showFingers, phone),
                ),
                if (iconKey != null) _handIcon(layout, iconKey),
                CustomPaint(
                  size: size,
                  painter: _BlackKeysPainter(widget.model, widget.scale, layout, widget.showFingers, phone),
                ),
              ],
            ),
          );
        },
      );
    });
  }

  /// SA: hand_left_solid / hand_right_solid in SA green, half a white key wide, near the bottom of the key
  Widget _handIcon(KeyboardLayout layout, int keyIndex) {
    final rect = layout.keyRects[keyIndex];
    final left = widget.model.hand == 1;
    final width = layout.naturalWidth * 0.5;
    // The PNGs' aspect ratios (SA's images): left 349x449, right 344x449
    final height = width * (left ? 449 / 349 : 449 / 344);
    return Positioned(
      left: rect.center.dx - width / 2,
      top: rect.height - height * 1.25,
      width: width,
      height: height,
      child: IgnorePointer(
        child: Image.asset(
          left ? 'assets/images/hand_left_solid.png' : 'assets/images/hand_right_solid.png',
          color: SaColors.green,
          colorBlendMode: BlendMode.srcIn,
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}

/// Shared parts of SA ClassicStyle
mixin _ClassicStyle {
  KeyboardModel get model;
  Scale get scale;
  KeyboardLayout get layout;
  bool get phone;

  double get cornerRadius => layout.size.width * 0.008;

  /// SA: a ring of this diameter on a sounding key
  double get playingMidiRadius => layout.naturalWidth * (scale.octaves > 1 ? 0.5 : 0.3);

  /// SA getFingerColor: by the upward fingering breaks when going up (direction 0), the downward ones otherwise
  Color fingerColour(ScaleNoteState state) {
    final type = model.scaleDirection == 0 ? state.keyboardFingerColourTypeUp : state.keyboardFingerColourTypeDown;
    return type == KeyboardColourType.fingeringSequenceBreak ? SaColors.fingerOverUnder : SaColors.fingerOnKey;
  }

  Color? highlightColour(KeyHighlight h) => switch (h) {
        KeyHighlight.followThisNote => SaColors.blueShade6,
        KeyHighlight.middleOfKeyboard => SaColors.green,
        KeyHighlight.wasWrongNote => SaColors.pink,
        KeyHighlight.playedCorrectly => SaColors.green,
        KeyHighlight.none => null,
      };

  void drawRing(Canvas canvas, PianoKey key, Offset centre) {
    if (!key.isSounding) return;
    final state = key.scaleNoteState;
    final Color colour;
    if (state != null) {
      colour = fingerColour(state);
    } else {
      if (!model.hilightNotesOutsideScale) return;
      colour = Colors.red;
    }
    canvas.drawCircle(
      centre,
      playingMidiRadius / 2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = colour,
    );
  }

  /// SA: .title3 bold on phones, .title on larger screens
  void drawFinger(Canvas canvas, String text, Color colour, Offset centre) {
    if (text.isEmpty) return;
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: colour, fontSize: phone ? 20 : 28, fontWeight: FontWeight.bold),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, centre - Offset(painter.width / 2, painter.height / 2));
  }
}

class _WhiteKeysPainter extends CustomPainter with _ClassicStyle {
  @override
  final KeyboardModel model;
  @override
  final Scale scale;
  @override
  final KeyboardLayout layout;
  final bool showFingers;
  @override
  final bool phone;

  _WhiteKeysPainter(this.model, this.scale, this.layout, this.showFingers, this.phone);

  @override
  void paint(Canvas canvas, Size size) {
    final r = Radius.circular(cornerRadius);
    for (var i = 0; i < model.keys.length; i++) {
      final key = model.keys[i];
      if (!key.isNatural) continue;
      final rect = layout.keyRects[i];
      final path = RRect.fromRectAndRadius(rect, r);
      final h = highlightColour(key.highlight);
      final fill = Paint();
      if (h != null) {
        fill.shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [h, Colors.white],
        ).createShader(rect);
      } else {
        fill.color = Colors.white;
      }
      canvas.drawRRect(path, fill);
      canvas.drawRRect(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = Colors.grey,
      );
      final centre = Offset(rect.center.dx, rect.top + rect.height * 0.70);
      drawRing(canvas, key, centre);
      final state = key.scaleNoteState;
      if (showFingers && state != null && state.finger > 0) {
        drawFinger(canvas, key.fingerText, fingerColour(state), centre);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class _BlackKeysPainter extends CustomPainter with _ClassicStyle {
  @override
  final KeyboardModel model;
  @override
  final Scale scale;
  @override
  final KeyboardLayout layout;
  final bool showFingers;
  @override
  final bool phone;

  _BlackKeysPainter(this.model, this.scale, this.layout, this.showFingers, this.phone);

  static Color naturalColour(bool down) => down ? const Color(0xFF666666) : const Color(0xFFB3B3B3);

  static Color sharpFlatColour(bool down) => down ? const Color(0xFF666666) : const Color(0xFF999999);

  @override
  void paint(Canvas canvas, Size size) {
    final r = Radius.circular(cornerRadius);
    for (var i = 0; i < model.keys.length; i++) {
      final key = model.keys[i];
      if (key.isNatural) continue;
      final rect = layout.keyRects[i];
      final path = RRect.fromRectAndCorners(rect, bottomLeft: r, bottomRight: r);
      canvas.drawRRect(path, Paint()..color = const Color(0xFF1A1A1A));

      // SA: a lighter inset face, its bottom raised a little less while the key is down. Its top is level with the
      // top of the keys (SA's face went slightly above the white keys; David, 2 Nov 2026: the top edges should align)
      final inset = rect.width * 0.15;
      final insetRect = Rect.fromLTRB(rect.left + inset, rect.top, rect.right - inset,
          rect.bottom - inset - (key.touchDown ? inset : inset * 1.5));
      final ri = Radius.circular(cornerRadius / 2);
      final top = highlightColour(key.highlight) ?? naturalColour(key.touchDown);
      canvas.drawRRect(
        RRect.fromRectAndCorners(insetRect, bottomLeft: ri, bottomRight: ri),
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [top, sharpFlatColour(key.touchDown), sharpFlatColour(key.touchDown)],
          ).createShader(Rect.fromLTWH(rect.left, 0, rect.width, rect.height)),
      );
      canvas.drawRRect(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = Colors.grey,
      );
      final centre = Offset(rect.center.dx, rect.top + rect.height * 0.50);
      drawRing(canvas, key, centre);
      final state = key.scaleNoteState;
      if (showFingers && state != null) {
        drawFinger(canvas, key.fingerText, fingerColour(state), centre);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
