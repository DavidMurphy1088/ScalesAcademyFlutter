/// A note message from a MIDI keyboard
class MidiNoteMessage {
  final int midi;

  /// 0 for note off
  final int velocity;

  bool get isNoteOn => velocity > 0;

  const MidiNoteMessage(this.midi, this.velocity);
}

/// A connected MIDI keyboard or other MIDI source
class MidiDeviceInfo {
  final String id;
  final String name;

  const MidiDeviceInfo(this.id, this.name);
}

/// MIDI keyboard input. Each platform offers what it supports (Stage 4): USB/Bluetooth MIDI on
/// Android and iOS, Web MIDI in Chrome and Edge. Safari has no MIDI.
abstract class MidiInput {
  /// Whether this platform can use MIDI at all
  bool get isSupported;

  Future<List<MidiDeviceInfo>> devices();

  Future<void> connect(MidiDeviceInfo device);

  Future<void> disconnect();

  /// Notes from the connected device
  Stream<MidiNoteMessage> get messages;
}

/// Placeholder until Stage 4: no MIDI
class NoMidiInput implements MidiInput {
  @override
  bool get isSupported => false;
  @override
  Future<List<MidiDeviceInfo>> devices() async => const [];
  @override
  Future<void> connect(MidiDeviceInfo device) async {}
  @override
  Future<void> disconnect() async {}
  @override
  Stream<MidiNoteMessage> get messages => const Stream.empty();
}
