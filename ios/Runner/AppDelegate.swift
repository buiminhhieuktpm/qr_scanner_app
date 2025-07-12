import UIKit
import Flutter
import AVFoundation
import CoreLocation

@main
@objc class AppDelegate: FlutterAppDelegate, CLLocationManagerDelegate {
  private var locationManager: CLLocationManager?
  private var locationResult: FlutterResult?
  private var locationMethodChannel: FlutterMethodChannel?
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    
    let controller : FlutterViewController = window?.rootViewController as! FlutterViewController
    let nativeChannel = FlutterMethodChannel(name: "native_permissions",
                                           binaryMessenger: controller.binaryMessenger)
    
    // Store reference to prevent deallocation
    locationMethodChannel = nativeChannel
    
    nativeChannel.setMethodCallHandler({
      [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in
      
      switch call.method {
      case "requestCameraPermission":
        self?.requestCameraPermission(result: result)
      case "getCameraPermissionStatus":
        self?.getCameraPermissionStatus(result: result)
      case "requestLocationPermission":
        self?.requestLocationPermission(result: result)
      case "getLocationPermissionStatus":
        self?.getLocationPermissionStatus(result: result)
      case "openAppSettings":
        self?.openAppSettings(result: result)
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
  
  // MARK: - Settings Methods
  
  private func openAppSettings(result: @escaping FlutterResult) {
    guard let settingsUrl = URL(string: UIApplication.openSettingsURLString) else {
      print("📱 Native iOS: Không thể tạo URL Settings")
      result(false)
      return
    }
    
    if UIApplication.shared.canOpenURL(settingsUrl) {
      UIApplication.shared.open(settingsUrl) { [weak self] success in
        DispatchQueue.main.async {
          print("📱 Native iOS: Mở Settings app - success: \(success)")
          result(success)
        }
      }
    } else {
      print("📱 Native iOS: Không thể mở Settings URL")
      result(false)
    }
  }

  // MARK: - Location Permission Methods
  
  private func requestLocationPermission(result: @escaping FlutterResult) {
    print("🌍 Native iOS: Requesting location permission...")
    
    // Ensure we're on main thread
    DispatchQueue.main.async { [weak self] in
      self?.performLocationPermissionRequest(result: result)
    }
  }
  
  private func performLocationPermissionRequest(result: @escaping FlutterResult) {
    locationResult = result
    
    // Create new location manager instance
    locationManager = CLLocationManager()
    locationManager?.delegate = self
    
    let currentStatus = CLLocationManager.authorizationStatus()
    print("🌍 Native iOS: Current location status: \(currentStatus.rawValue)")
    
    switch currentStatus {
    case .notDetermined:
      print("🌍 Native iOS: Requesting when in use authorization...")
      locationManager?.requestWhenInUseAuthorization()
    case .denied, .restricted:
      print("🌍 Native iOS: Location permission denied/restricted")
      result(false)
      locationResult = nil
      locationManager = nil
    case .authorizedWhenInUse, .authorizedAlways:
      print("🌍 Native iOS: Location permission already granted")
      result(true)
      locationResult = nil
      locationManager = nil
    @unknown default:
      print("🌍 Native iOS: Unknown location permission status")
      result(false)
      locationResult = nil
      locationManager = nil
    }
  }
  
  private func getLocationPermissionStatus(result: @escaping FlutterResult) {
    let status = CLLocationManager.authorizationStatus()
    print("🌍 Native iOS: Location permission status: \(status.rawValue)")
    
    let statusString: String
    switch status {
    case .authorizedWhenInUse, .authorizedAlways:
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
  
  // MARK: - CLLocationManagerDelegate
  
  func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
    print("🌍 Native iOS: Location authorization changed to: \(status.rawValue)")
    
    // Ensure callback on main thread
    DispatchQueue.main.async { [weak self] in
      self?.handleLocationAuthorizationChange(status: status)
    }
  }
  
  private func handleLocationAuthorizationChange(status: CLAuthorizationStatus) {
    guard let result = locationResult else { 
      print("🌍 Native iOS: No pending result callback")
      return 
    }
    
    switch status {
    case .authorizedWhenInUse, .authorizedAlways:
      print("🌍 Native iOS: Location permission granted!")
      result(true)
      cleanupLocationRequest()
    case .denied, .restricted:
      print("🌍 Native iOS: Location permission denied!")
      result(false)
      cleanupLocationRequest()
    case .notDetermined:
      print("🌍 Native iOS: Location permission still not determined")
      // Don't call result yet, wait for final decision
      return
    @unknown default:
      print("🌍 Native iOS: Unknown location permission status")
      result(false)
      cleanupLocationRequest()
    }
  }
  
  private func cleanupLocationRequest() {
    locationResult = nil
    locationManager?.delegate = nil
    locationManager = nil
  }
}
