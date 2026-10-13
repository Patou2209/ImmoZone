import Flutter
import UIKit

// Migration UIScene (requise par iOS 26+/27 — crash
// "NoSceneLifecycleAdoption" sinon). Voir flutter.dev/to/uiscene-migration.
// Le FlutterSceneDelegate est déclaré dans Info.plist
// (UIApplicationSceneManifest) ; l'enregistrement des plugins se fait via
// pluginRegistrant, appelé par le moteur au bon moment du cycle de vie.
@main
@objc class AppDelegate: FlutterAppDelegate, FlutterPluginRegistrant {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    pluginRegistrant = self
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func register(with registry: FlutterPluginRegistry) {
    GeneratedPluginRegistrant.register(with: registry)
  }
}
