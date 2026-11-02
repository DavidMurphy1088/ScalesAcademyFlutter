import CoreAudioKit
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  /// Microphone pitch detection channels (see PitchChannel.swift)
  private var pitchChannel: PitchChannel?

  /// Apple's Bluetooth MIDI pairing screen (Stage 4)
  private var bluetoothMidiChannel: BluetoothMidiChannel?

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "FLPitchChannel") {
      pitchChannel = PitchChannel(messenger: registrar.messenger())
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "SAFBluetoothMidi") {
      bluetoothMidiChannel = BluetoothMidiChannel(messenger: registrar.messenger())
    }
  }
}

/// Apple's standard Bluetooth MIDI pairing screen, as SA shows it (SA BluetoothMIDIPairingView).
///
/// iOS never opens a Bluetooth LE MIDI link from Settings > Bluetooth: a piano showing "Connected" there is using its
/// Bluetooth audio link, which carries no MIDI. The MIDI link must be opened from inside an app, and this controller
/// is how Apple intends that to be done. Once the keyboard is tapped here, CoreMIDI adds it as a MIDI source and it is
/// listed with the other MIDI keyboards (flutter_midi_command).
///
/// Dart: MethodChannel('saf/bluetooth_midi').invokeMethod('showPairing') - completes when Done is tapped.
class BluetoothMidiChannel: NSObject {
  private let channel: FlutterMethodChannel
  private var pendingResult: FlutterResult?

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "saf/bluetooth_midi", binaryMessenger: messenger)
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { return }
      switch call.method {
      case "showPairing":
        self.showPairing(result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func topViewController() -> UIViewController? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let window = scenes.flatMap { $0.windows }.first { $0.isKeyWindow } ?? scenes.first?.windows.first
    var top = window?.rootViewController
    while let presented = top?.presentedViewController {
      top = presented
    }
    return top
  }

  private func showPairing(result: @escaping FlutterResult) {
    if pendingResult != nil {
      result(FlutterError(code: "busy", message: "The Bluetooth MIDI screen is already showing", details: nil))
      return
    }
    guard let presenter = topViewController() else {
      result(FlutterError(code: "no_window", message: "No screen to show the Bluetooth MIDI screen on", details: nil))
      return
    }
    let central = CABTMIDICentralViewController()
    central.navigationItem.title = "Bluetooth Piano"
    central.navigationItem.leftBarButtonItem = UIBarButtonItem(
      barButtonSystemItem: .done, target: self, action: #selector(doneTapped))
    let navigation = UINavigationController(rootViewController: central)
    // Full screen, so it can only be closed with Done (and Dart always hears that it closed)
    navigation.modalPresentationStyle = .fullScreen
    pendingResult = result
    presenter.present(navigation, animated: true)
  }

  @objc private func doneTapped() {
    let finish = { [weak self] in
      self?.pendingResult?(nil)
      self?.pendingResult = nil
    }
    // The pairing screen is the top one; dismiss it from the screen that presented it
    if let top = topViewController(), let presenter = top.presentingViewController {
      presenter.dismiss(animated: true, completion: finish)
    } else {
      finish()
    }
  }
}
