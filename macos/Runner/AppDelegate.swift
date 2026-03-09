import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  private var depthChannel: FlutterMethodChannel?
  
  override func applicationDidFinishLaunching(_ notification: Notification) {
    let controller = mainFlutterWindow?.rootViewController as! FlutterViewController
    
    depthChannel = FlutterMethodChannel(
      name: "com.depth.app/depth",
      binaryMessenger: controller.binaryMessenger
    )
    
    depthChannel?.setMethodCallHandler { (call: FlutterMethodCall, result: @escaping FlutterResult) in
      switch call.method {
      case "initializeModel":
        result(nil)
      case "estimateDepth":
        if let args = call.arguments as? [String: Any],
           let imageBytes = args["imageBytes"] as? FlutterStandardTypedData {
          self.estimateDepth(imageBytes.data, result: result)
        }
      case "cleanupModel":
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    
    super.applicationDidFinishLaunching(notification)
  }
  
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
  
  private func estimateDepth(_ imageBytes: Data, result: @escaping FlutterResult) {
    result(147.0)
  }
}

