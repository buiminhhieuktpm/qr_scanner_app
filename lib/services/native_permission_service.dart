import 'package:flutter/services.dart';

class NativePermissionService {
  static const MethodChannel _channel = MethodChannel('native_permissions');

  static Future<bool> requestCameraPermissionNative() async {
    try {
      final bool result = await _channel.invokeMethod('requestCameraPermission');
      return result;
    } on PlatformException catch (e) {
      print("Failed to request camera permission: '${e.message}'.");
      return false;
    }
  }

  static Future<String> getCameraPermissionStatus() async {
    try {
      final String result = await _channel.invokeMethod('getCameraPermissionStatus');
      return result;
    } on PlatformException catch (e) {
      print("Failed to get camera permission status: '${e.message}'.");
      return 'unknown';
    }
  }
}
