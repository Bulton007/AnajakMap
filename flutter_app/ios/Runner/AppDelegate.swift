import Flutter
import UIKit
import GoogleMaps

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var mapsConfigured = false
  private var mapsChannel: FlutterMethodChannel?
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if let key = Bundle.main.object(forInfoDictionaryKey: "GoogleMapsAPIKey") as? String,
       !key.isEmpty, !key.hasPrefix("$("), !key.hasPrefix("YOUR_") {
      mapsConfigured = GMSServices.provideAPIKey(key)
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "AnajakMapsConfig") {
      mapsChannel = FlutterMethodChannel(name: "anajak/maps_config", binaryMessenger: registrar.messenger())
      mapsChannel?.setMethodCallHandler { [weak self] call, result in
        if call.method == "configured" { result(self?.mapsConfigured ?? false) }
        else { result(FlutterMethodNotImplemented) }
      }
    }
  }
}
