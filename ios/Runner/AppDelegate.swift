import UIKit
import Flutter
import AVFoundation

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    
    let controller : FlutterViewController = window?.rootViewController as! FlutterViewController
    let nativeChannel = FlutterMethodChannel(name: "native_permissions",
                                           binaryMessenger: controller.binaryMessenger)
    
    nativeChannel.setMethodCallHandler({
      [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in
      
      switch call.method {
      case "requestCameraPermission":
        self?.requestCameraPermission(result: result)
      case "getCameraPermissionStatus":
        self?.getCameraPermissionStatus(result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    })
    
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
  
  private func requestCameraPermission(result: @escaping FlutterResult) {
    print("🎯 Native iOS: Requesting camera permission...")
    
    AVCaptureDevice.requestAccess(for: .video) { granted in
      DispatchQueue.main.async {
        print("🎯 Native iOS: Camera permission result: \(granted)")
        result(granted)
      }
    }
  }
  
  private func getCameraPermissionStatus(result: @escaping FlutterResult) {
    let status = AVCaptureDevice.authorizationStatus(for: .video)
    print("🎯 Native iOS: Camera permission status: \(status.rawValue)")
    
    let statusString: String
    switch status {
    case .authorized:
      statusString = "authorized"
    case .denied:
      statusString = "denied"
    case .restricted:
      statusString = "restricted"
    case .notDetermined:
      statusString = "notDetermined"
    @unknown default:
      statusString = "unknown"
    }
    
    result(statusString)
  }
}
