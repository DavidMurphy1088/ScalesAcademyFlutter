import 'midi/midi_input.dart';
import 'pitch/pitch_source.dart';
import 'recording/audio_recorder.dart';
import 'sound/soloud_sound_player.dart';
import 'sound/sound_player.dart';

/// The only place the app reaches platform-specific code. Everything else in the app uses these
/// interfaces and never needs to know whether it is running on Android, iOS or the web.
///
///  - [pitch]: microphone pitch readings (Android: Kotlin YIN; iOS: AudioKit as in Scales Academy,
///    or YIN; web: JavaScript YIN)
///  - [sound]: piano notes and metronome (flutter_soloud on all three platforms; iOS audio session in Swift)
///  - [midi]: MIDI keyboard input (placeholder until Stage 4)
///  - [recorder]: recording and playback (placeholder until Stage 6)
class PlatformServices {
  final PitchSource? pitch;
  final SoundPlayer sound;
  final MidiInput midi;
  final AudioRecorder recorder;

  PlatformServices._({required this.pitch, required this.sound, required this.midi, required this.recorder});

  /// The services for the platform the app is running on
  static final PlatformServices instance = PlatformServices._(
    pitch: PitchSource.forThisPlatform(),
    sound: SoloudSoundPlayer(),
    midi: NoMidiInput(),
    recorder: NoAudioRecorder(),
  );
}
