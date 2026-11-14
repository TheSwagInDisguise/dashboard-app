import Flutter
import UIKit

/**
 * Scene lifecycle for Flutter (required by Flutter 3.47). Only extra duty:
 * deliver home-screen Quick Actions into the app — cold starts stash the
 * action, warm starts forward it live. Everything else is Flutter's job.
 */
class SceneDelegate: FlutterSceneDelegate {

  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    if let shortcut = connectionOptions.shortcutItem {
      (UIApplication.shared.delegate as? AppDelegate)?.handleShortcutAction(type: shortcut.type)
    }
  }

  // Flutter's FlutterSceneLifeCycleDelegate does implement this (the protocol
  // lists it), so `override` is required — caught by the CI iOS compile gate.
  override func windowScene(
    _ windowScene: UIWindowScene,
    performActionFor shortcutItem: UIApplicationShortcutItem,
    completionHandler: @escaping (Bool) -> Void
  ) {
    (UIApplication.shared.delegate as? AppDelegate)?.handleShortcutAction(type: shortcutItem.type)
    completionHandler(true)
  }
}
