import '../platform/sound/sound_player.dart';
import 'tempo_clock.dart';

/// What happens on one tick (one note's time) of a [ScalePlan]
class TickEvents {
  final bool click;
  final int? noteOff;
  final int? noteOn;

  /// Index in the scale of [noteOn]
  final int? noteIndex;
  final bool finished;

  const TickEvents({this.click = false, this.noteOff, this.noteOn, this.noteIndex, this.finished = false});
}

/// How a scale is played, as in Scales Academy (Metronome / HearScalePlayer):
///  - [tempo] is crotchet beats per minute (SA's "♩ = 120")
///  - each scale note is a quaver: [notesPerBeat] = 2 (3 for triplets, e.g. SA's broken chords)
///  - each note sounds until the next one starts (legato); the last note is held for one beat
///  - an optional count-in of [leadInBeats] clicks (SA: 4, or 3 in compound time)
///  - with [metronome] on, a click on every beat while the scale plays
/// With no [notes], it is just a metronome that runs until stopped.
class ScalePlan {
  final List<int> notes;
  final int tempo;
  final int notesPerBeat;
  final int leadInBeats;
  final bool metronome;

  const ScalePlan({
    required this.notes,
    required this.tempo,
    this.notesPerBeat = 2,
    this.leadInBeats = 4,
    this.metronome = true,
  });

  /// Metronome only, clicking every beat
  const ScalePlan.metronomeOnly({required this.tempo})
      : notes = const [],
        notesPerBeat = 1,
        leadInBeats = 0,
        metronome = true;

  Duration get tickLength => Duration(microseconds: (60000000 / tempo / notesPerBeat).round());
  int get leadInTicks => leadInBeats * notesPerBeat;

  /// The tick on which the last note is released and playing ends (null for metronome only)
  int? get endTick => notes.isEmpty ? null : leadInTicks + notes.length - 1 + notesPerBeat;

  TickEvents eventsAt(int tick) {
    if (notes.isEmpty) return const TickEvents(click: true);
    final end = endTick!;
    if (tick >= end) return TickEvents(noteOff: notes.last, finished: true);
    final onBeat = tick % notesPerBeat == 0;
    final inLeadIn = tick < leadInTicks;
    final i = tick - leadInTicks;
    return TickEvents(
      click: onBeat && (inLeadIn || metronome),
      noteOff: i >= 1 && i < notes.length ? notes[i - 1] : null,
      noteOn: i >= 0 && i < notes.length ? notes[i] : null,
      noteIndex: i >= 0 && i < notes.length ? i : null,
    );
  }
}

/// Plays a [ScalePlan] through a [SoundPlayer]. Same Dart code on every platform.
class ScalePlayer {
  final SoundPlayer sound;
  final TempoClock clock = TempoClock();
  ScalePlan? _plan;

  /// Called as each scale note starts
  void Function(int index, int midi)? onNote;

  /// Called when the scale has finished (not when stopped)
  void Function()? onFinished;

  ScalePlayer(this.sound);

  bool get isPlaying => clock.isRunning;

  void play(ScalePlan plan) {
    stop();
    _plan = plan;
    clock.start(plan.tickLength, _onTick);
  }

  void _onTick(int tick) {
    final events = _plan!.eventsAt(tick);
    if (events.noteOff != null) sound.noteOff(events.noteOff!);
    if (events.click) sound.click();
    if (events.noteOn != null) {
      sound.noteOn(events.noteOn!);
      onNote?.call(events.noteIndex!, events.noteOn!);
    }
    if (events.finished) {
      clock.stop();
      onFinished?.call();
    }
  }

  void stop() {
    clock.stop();
    sound.allNotesOff();
  }
}
