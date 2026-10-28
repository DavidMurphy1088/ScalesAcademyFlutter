/// Plays piano notes and metronome clicks. Each platform has its own implementation behind this
/// interface (Stage 1: SoundFonts via a native player on Android/iOS, a JavaScript player on the web).
abstract class SoundPlayer {
  /// False until a real implementation exists for this platform
  bool get isAvailable;

  /// Load sounds; call once before playing
  Future<void> init();

  /// Start a note. [velocity] 1-127, as MIDI
  void noteOn(int midi, {int velocity = 90});

  /// Stop a note
  void noteOff(int midi);

  /// A metronome click; [accent] for the first beat of the bar
  void click({bool accent = false});

  Future<void> dispose();
}

/// Placeholder until Stage 1: makes no sound
class SilentSoundPlayer implements SoundPlayer {
  @override
  bool get isAvailable => false;
  @override
  Future<void> init() async {}
  @override
  void noteOn(int midi, {int velocity = 90}) {}
  @override
  void noteOff(int midi) {}
  @override
  void click({bool accent = false}) {}
  @override
  Future<void> dispose() async {}
}
