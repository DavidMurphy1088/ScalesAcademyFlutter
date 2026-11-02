import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_midi_command/flutter_midi_command.dart';
import 'package:flutter_midi_command_ble/flutter_midi_command_ble.dart';

import 'midi_input.dart';

/// MIDI keyboards through the flutter_midi_command package:
///  - iOS: CoreMIDI. Bluetooth keyboards are paired on Apple's Bluetooth MIDI screen (as SA: ios/Runner/AppDelegate.swift
///    shows it), after which iOS lists them with the other MIDI sources.
///  - Android: android.media.midi for USB; Bluetooth keyboards found and connected by the package's BLE transport
///    (flutter_midi_command_ble).
///  - Web: Web MIDI (Chrome, Edge). The computer connects the keyboard; the browser asks permission the first time.
class FlutterMidiInput implements MidiInput {
  static const _pairingChannel = MethodChannel('saf/bluetooth_midi');

  MidiCommand? _midi;
  StreamSubscription<MidiPacket>? _packets;
  StreamSubscription<MidiSetupChange>? _setup;
  final _devicesChanged = StreamController<void>.broadcast();
  final _messages = StreamController<MidiNoteMessage>.broadcast();

  /// The package's devices from the last [devices] call, by id (connecting needs the package's own object)
  final Map<String, MidiDevice> _known = {};
  MidiDevice? _connectedDevice;
  MidiDeviceInfo? _connected;

  @override
  final MidiCheckCounts counts = MidiCheckCounts();

  void Function(String line)? _log;

  @override
  set log(void Function(String line)? log) => _log = log;

  bool get _android => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  bool get _ios => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  @override
  bool get isSupported => midiPlatformSupported;

  @override
  BluetoothFinding get bluetoothFinding =>
      _ios ? BluetoothFinding.appleScreen : (_android ? BluetoothFinding.scan : BluetoothFinding.none);

  /// Started on first use, so nothing (e.g. the browser's MIDI permission question) happens until MIDI is chosen
  MidiCommand _start() {
    final existing = _midi;
    if (existing != null) return existing;
    final midi = MidiCommand();
    if (_android) {
      midi.configureBleTransport(UniversalBleMidiTransport());
      midi.configureTransportPolicy(const MidiTransportPolicy(excludedTransports: {MidiTransport.network}));
    } else {
      midi.configureBleTransport(null);
      midi.configureTransportPolicy(
          const MidiTransportPolicy(excludedTransports: {MidiTransport.ble, MidiTransport.network}));
    }
    _packets = midi.onMidiPacketReceived?.listen(_onPacket);
    _setup = midi.onMidiSetupChanged?.listen((change) => _devicesChanged.add(null));
    _midi = midi;
    return midi;
  }

  /// SA MIDIManager.parseMIDIMessage: note on (0x9n, velocity 0 = note off) and note off (0x8n)
  void _onPacket(MidiPacket packet) {
    final device = _connectedDevice;
    if (device == null || packet.device.id != device.id) return;
    final data = packet.data;
    if (data.isEmpty) return;
    counts.messages++;
    final status = data[0];
    if (status == 0xF8 || status == 0xFE) {
      counts.background++;
      return;
    }
    final type = status & 0xF0;
    if ((type == 0x90 || type == 0x80) && data.length >= 3) {
      final note = data[1];
      final velocity = type == 0x80 ? 0 : data[2];
      if (velocity > 0) {
        counts.noteOns++;
      } else {
        counts.noteOffs++;
      }
      _messages.add(MidiNoteMessage(note, velocity));
      return;
    }
    counts.other++;
  }

  String _kind(MidiDeviceType type) => switch (type) {
        MidiDeviceType.ble => 'Bluetooth',
        MidiDeviceType.serial => kIsWeb ? 'Web MIDI' : 'USB',
        MidiDeviceType.virtual => 'Virtual',
        _ => 'MIDI',
      };

  @override
  Future<List<MidiDeviceInfo>> devices() async {
    final midi = _start();
    final List<MidiDevice> found;
    try {
      found = await midi.devices ?? const [];
    } catch (e) {
      if (kIsWeb) throw StateError('This browser has no Web MIDI, or it was not allowed (use Chrome or Edge): $e');
      rethrow;
    }
    _known.clear();
    final result = <MidiDeviceInfo>[];
    for (final d in found) {
      // As SA: leave out Apple's network MIDI session and the app's own virtual ports
      if (d.type == MidiDeviceType.network || d.type == MidiDeviceType.ownVirtual) continue;
      // Listed once each (a device can come from both the system and the Bluetooth transport)
      if (_known.containsKey(d.id)) continue;
      _known[d.id] = d;
      result.add(MidiDeviceInfo(d.id, d.name.isEmpty ? '(no name)' : d.name, _kind(d.type)));
    }
    return result;
  }

  @override
  Stream<void> get devicesChanged => _devicesChanged.stream;

  @override
  Future<String> findBluetoothKeyboards({Duration scanFor = const Duration(seconds: 10)}) async {
    final midi = _start();
    switch (bluetoothFinding) {
      case BluetoothFinding.appleScreen:
        await _pairingChannel.invokeMethod<void>('showPairing');
        _devicesChanged.add(null);
        return "Apple's Bluetooth MIDI screen closed";
      case BluetoothFinding.scan:
        await midi.startBluetooth();
        await midi.waitUntilBluetoothIsInitialized().timeout(const Duration(seconds: 5), onTimeout: () {});
        if (midi.bluetoothState != BluetoothState.poweredOn) {
          return 'Bluetooth is not available: ${midi.bluetoothState.name} '
              '(turn Bluetooth on, and allow "Nearby devices" for SA Flutter)';
        }
        await midi.startScanningForBluetoothDevices();
        await Future<void>.delayed(scanFor);
        midi.stopScanningForBluetoothDevices();
        _devicesChanged.add(null);
        return 'Scanned for Bluetooth MIDI keyboards for ${scanFor.inSeconds} s';
      case BluetoothFinding.none:
        return 'Bluetooth keyboards are connected by the computer here (on a Mac: Audio MIDI Setup)';
    }
  }

  @override
  Future<void> connect(MidiDeviceInfo device) async {
    final midi = _start();
    await disconnect();
    final d = _known[device.id];
    if (d == null) throw StateError('${device.name} is no longer listed');
    counts.reset();
    await midi.connectToDevice(d);
    _connectedDevice = d;
    _connected = device;
    _log?.call('Connected to $device');
  }

  @override
  Future<void> disconnect() async {
    final d = _connectedDevice;
    _connectedDevice = null;
    final was = _connected;
    _connected = null;
    if (d != null) {
      _midi?.disconnectDevice(d);
      _log?.call('Disconnected from $was');
    }
  }

  @override
  MidiDeviceInfo? get connected => _connected;

  @override
  Stream<MidiNoteMessage> get messages => _messages.stream;

  /// Not called: the app keeps MIDI for its whole life
  void dispose() {
    _packets?.cancel();
    _setup?.cancel();
  }
}
