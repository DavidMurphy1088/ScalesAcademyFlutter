/// A piano sound the user can choose
class PianoSound {
  final String id;
  final String label;

  /// Folder of note files, one per MIDI note: `<folder>/<midi>.ogg`
  final String assetFolder;

  const PianoSound(this.id, this.label, this.assetFolder);
}

/// Plays piano notes and metronome clicks. The rest of the app only uses this interface.
abstract class SoundPlayer {
  /// The piano sounds available
  List<PianoSound> get pianos;

  /// The piano sound in use
  PianoSound get piano;

  /// True once [init] has finished
  bool get isReady;

  /// Start sound and load the piano (on the web this must follow a tap, as browsers only allow sound after one).
  /// Returns how long it took.
  Future<Duration> init({String? pianoId});

  /// Switch piano sound. Returns how long loading took.
  Future<Duration> selectPiano(String pianoId);

  /// Piano volume, 0-1
  double get pianoVolume;
  set pianoVolume(double value);

  /// Metronome click volume, 0-1
  double get clickVolume;
  set clickVolume(double value);

  /// Start a note (key down)
  void noteOn(int midi);

  /// Release a note (key up): it fades out like a released piano key
  void noteOff(int midi);

  void allNotesOff();

  /// A metronome click; [accent] uses the higher click
  void click({bool accent = false});

  Future<void> dispose();
}

/// Placeholder: makes no sound (used where no sound engine is available, e.g. widget tests)
class SilentSoundPlayer implements SoundPlayer {
  static const _piano = PianoSound('none', 'None', '');
  @override
  List<PianoSound> get pianos => const [_piano];
  @override
  PianoSound get piano => _piano;
  @override
  bool get isReady => false;
  @override
  Future<Duration> init({String? pianoId}) async => Duration.zero;
  @override
  Future<Duration> selectPiano(String pianoId) async => Duration.zero;
  @override
  double pianoVolume = 1;
  @override
  double clickVolume = 0.5;
  @override
  void noteOn(int midi) {}
  @override
  void noteOff(int midi) {}
  @override
  void allNotesOff() {}
  @override
  void click({bool accent = false}) {}
  @override
  Future<void> dispose() async {}
}
