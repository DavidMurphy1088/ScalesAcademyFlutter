import 'package:flutter/foundation.dart';

/// A note message from a MIDI keyboard
class MidiNoteMessage {
  final int midi;

  /// 0 for note off
  final int velocity;

  bool get isNoteOn => velocity > 0;

  const MidiNoteMessage(this.midi, this.velocity);
}

/// A MIDI keyboard (or other MIDI source) the app can listen to
class MidiDeviceInfo {
  final String id;
  final String name;

  /// e.g. "Bluetooth", "USB", "Web MIDI"
  final String kind;

  const MidiDeviceInfo(this.id, this.name, this.kind);

  @override
  String toString() => '$name ($kind)';
}

/// How this platform finds Bluetooth MIDI keyboards
enum BluetoothFinding {
  /// None (web: the computer connects the keyboard; on a Mac in Audio MIDI Setup)
  none,

  /// iOS: Apple's Bluetooth MIDI screen (as SA). Once a keyboard is tapped there, it is listed with the others.
  appleScreen,

  /// Android: the app scans for Bluetooth MIDI keyboards for a few seconds
  scan,
}

/// What arrived from the keyboard during a Check (SA MIDIManager CheckCounts)
class MidiCheckCounts {
  int messages = 0;

  /// Timing clock and "active sensing": the link is alive, but these aren't key presses
  int background = 0;
  int noteOns = 0;

  /// Including note-ons with velocity 0
  int noteOffs = 0;

  /// Pedal, controllers, pitch bend, SysEx...
  int other = 0;

  void reset() {
    messages = 0;
    background = 0;
    noteOns = 0;
    noteOffs = 0;
    other = 0;
  }

  @override
  String toString() => messages == 0
      ? 'nothing at all arrived from the keyboard'
      : '$messages messages: $noteOns note-ons, $noteOffs note-offs, $background timing/active-sensing, '
          '$other other (pedal, controllers...)';
}

/// MIDI keyboard input (Stage 4): Bluetooth MIDI on Android and iOS, Web MIDI in Chrome and Edge (Safari has none).
/// USB keyboards are listed too but aren't tested.
abstract class MidiInput {
  /// Whether this platform can use MIDI at all
  bool get isSupported;

  BluetoothFinding get bluetoothFinding;

  /// The MIDI keyboards available now
  Future<List<MidiDeviceInfo>> devices();

  /// Fires when keyboards appear, disappear or connect
  Stream<void> get devicesChanged;

  /// iOS: shows Apple's Bluetooth MIDI screen and completes when it is closed.
  /// Android: scans for [scanFor]. Returns a line for the test log.
  Future<String> findBluetoothKeyboards({Duration scanFor = const Duration(seconds: 10)});

  /// Listen to [device] only (any other is disconnected)
  Future<void> connect(MidiDeviceInfo device);

  Future<void> disconnect();

  /// The keyboard being listened to
  MidiDeviceInfo? get connected;

  /// Notes from the connected keyboard
  Stream<MidiNoteMessage> get messages;

  /// Counts of everything that arrived from the connected keyboard since the last reset (for Check)
  MidiCheckCounts get counts;

  /// Lines from the MIDI package about finding and connecting keyboards, for the test log
  set log(void Function(String line)? log);
}

/// No MIDI (platforms without it, e.g. widget tests)
class NoMidiInput implements MidiInput {
  @override
  bool get isSupported => false;
  @override
  BluetoothFinding get bluetoothFinding => BluetoothFinding.none;
  @override
  Future<List<MidiDeviceInfo>> devices() async => const [];
  @override
  Stream<void> get devicesChanged => const Stream.empty();
  @override
  Future<String> findBluetoothKeyboards({Duration scanFor = const Duration(seconds: 10)}) async =>
      'MIDI is not available here';
  @override
  Future<void> connect(MidiDeviceInfo device) async {}
  @override
  Future<void> disconnect() async {}
  @override
  MidiDeviceInfo? get connected => null;
  @override
  Stream<MidiNoteMessage> get messages => const Stream.empty();
  @override
  final MidiCheckCounts counts = MidiCheckCounts();
  @override
  set log(void Function(String line)? log) {}
}

/// Where MIDI can be used: Android, iOS, and browsers with Web MIDI (Chrome, Edge - not Safari)
bool get midiPlatformSupported =>
    kIsWeb || defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS;
