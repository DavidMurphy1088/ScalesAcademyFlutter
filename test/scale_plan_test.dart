import 'package:flutter_test/flutter_test.dart';

import 'package:scales_academy_flutter/playback/scale_player.dart';

void main() {
  test('tempo 120 with quavers: a note every 250 ms (as SA)', () {
    const plan = ScalePlan(notes: [60, 62, 64], tempo: 120);
    expect(plan.tickLength, const Duration(milliseconds: 250));
    expect(const ScalePlan(notes: [60], tempo: 88).tickLength.inMicroseconds, 340909);
  });

  test('count-in of 4 beats: clicks on beats only, then the scale starts', () {
    const plan = ScalePlan(notes: [60, 62, 64], tempo: 120, metronome: false);
    expect(plan.leadInTicks, 8);
    for (var t = 0; t < 8; t++) {
      final e = plan.eventsAt(t);
      expect(e.click, t.isEven, reason: 'tick $t');
      expect(e.noteOn, isNull);
    }
    expect(plan.eventsAt(8).noteOn, 60);
    expect(plan.eventsAt(8).click, isFalse); // metronome off during the scale
  });

  test('legato: each note is released as the next starts; last note held one beat', () {
    const plan = ScalePlan(notes: [60, 62, 64], tempo: 120, leadInBeats: 0);
    expect(plan.eventsAt(0).noteOn, 60);
    expect(plan.eventsAt(1).noteOff, 60);
    expect(plan.eventsAt(1).noteOn, 62);
    expect(plan.eventsAt(2).noteOn, 64);
    expect(plan.eventsAt(3).noteOn, isNull);
    expect(plan.endTick, 4);
    expect(plan.eventsAt(4).noteOff, 64);
    expect(plan.eventsAt(4).finished, isTrue);
  });

  test('metronome on: a click on every beat while the scale plays', () {
    const plan = ScalePlan(notes: [60, 62, 64, 65], tempo: 120, leadInBeats: 0);
    expect([for (var t = 0; t < 5; t++) plan.eventsAt(t).click], [true, false, true, false, true]);
  });

  test('metronome only: clicks every beat and never finishes', () {
    const plan = ScalePlan.metronomeOnly(tempo: 60);
    expect(plan.tickLength, const Duration(seconds: 1));
    expect(plan.endTick, isNull);
    expect(plan.eventsAt(1000).click, isTrue);
    expect(plan.eventsAt(1000).finished, isFalse);
  });
}
