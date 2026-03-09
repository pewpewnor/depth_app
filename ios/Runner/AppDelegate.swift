import Flutter
import UIKit
import CoreML
import Vision

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var depthChannel: FlutterMethodChannel?
  
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let controller = window?.rootViewController as! FlutterViewController
    
    depthChannel = FlutterMethodChannel(
      name: "com.depth.app/depth",
      binaryMessenger: controller.binaryMessenger
    )
    
    depthChannel?.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
      switch call.method {
      case "initializeModel":
        if let args = call.arguments as? [String: Any],
           let modelPath = args["modelPath"] as? String {
          self?.initializeModel(modelPath, result: result)
        } else {
          result(FlutterError(code: "INVALID_ARGS", message: "Invalid arguments", details: nil))
        }
      case "estimateDepth":
        if let args = call.arguments as? [String: Any],
           let imageBytes = args["imageBytes"] as? FlutterStandardTypedData {
          self?.estimateDepth(imageBytes.data, result: result)
        } else {
          result(FlutterError(code: "INVALID_ARGS", message: "Invalid arguments", details: nil))
        }
      case "cleanupModel":
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
  
  private func initializeModel(_ modelPath: String, result: @escaping FlutterResult) {
    result(nil)
  }
  
  private func estimateDepth(_ imageBytes: Data, result: @escaping FlutterResult) {
    guard let image = UIImage(data: imageBytes),
          let cgImage = image.cgImage else {
      result(FlutterError(code: "IMAGE_ERROR", message: "Failed to decode image", details: nil))
      return
    }
    
    let request = VNEstimateDepthRequest()
    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
    
    do {
      try handler.perform([request])
      if let depthMap = request.results?.first as? VNDepthData {
        let maxValue = depthMap.depthMapPixelValues.max() ?? 0.0
        result(Double(maxValue))
      } else {
        result(0.0)
      }
    } catch {
      result(FlutterError(code: "DEPTH_ERROR", message: error.localizedDescription, details: nil))
    }
  }
}

