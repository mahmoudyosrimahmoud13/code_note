import Cocoa
import FlutterMacOS

@NSApplicationMain
class AppDelegate: FlutterAppDelegate {
  /// Links and files macOS asked CodeNote to open (codenote:// links from
  /// inPace, double-clicked .codenote files), until the app picks them up.
  var pendingLinks: [String] = []
  var linkChannel: FlutterMethodChannel?

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func application(_ application: NSApplication, open urls: [URL]) {
    for url in urls {
      let item = url.isFileURL ? url.path : url.absoluteString
      pendingLinks.append(item)
      linkChannel?.invokeMethod("link", arguments: item)
    }
  }

  func attachLinks(to controller: FlutterViewController) {
    let channel = FlutterMethodChannel(name: "codenote/links", binaryMessenger: controller.engine.binaryMessenger)
    channel.setMethodCallHandler { [weak self] call, result in
      if call.method == "initialLinks" {
        result(self?.pendingLinks ?? [])
        self?.pendingLinks.removeAll()
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
    linkChannel = channel
  }
}
