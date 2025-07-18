import 'package:flutter/services.dart';
import 'package:flutter/material.dart';

class NativePermissionService {
  static const MethodChannel _channel = MethodChannel('native_permissions');

  static Future<bool> requestCameraPermissionNative() async {
    try {
      final bool result = await _channel.invokeMethod('requestCameraPermission');
      return result;
    } on PlatformException catch (e) {
      print("❌ Lỗi khi request camera permission: ${e.toString()}");
      return false;
    } catch (e) {
      print("❌ Lỗi không xác định khi request camera permission: ${e.toString()}");
      return false;
    }
  }

  static Future<String> getCameraPermissionStatus() async {
    try {
      final String result = await _channel.invokeMethod('getCameraPermissionStatus');
      return result;
    } on PlatformException catch (e) {
      print("❌ Lỗi khi request camera permission: ${e.toString()}");
      return 'unknown';
    } catch (e) {
      print("❌ Lỗi không xác định khi request camera permission: ${e.toString()}");
      return 'unknown';
    }
  }

  // MARK: - Location Permission Methods

  static Future<bool> requestLocationPermissionNative() async {
    try {
      print("🌍 Dart: Calling native location permission request...");
      final bool result = await _channel.invokeMethod('requestLocationPermission');
      print("🌍 Dart: Native location permission result: $result");
      return result;
    } on PlatformException catch (e) {
      print("🌍 Dart: Failed to request location permission - Code: ${e.code}, Message: '${e.message}', Details: ${e.details}");
      return false;
    } catch (e) {
      print("🌍 Dart: Unexpected error requesting location permission: $e");
      return false;
    }
  }

  static Future<String> getLocationPermissionStatus() async {
    try {
      final String result = await _channel.invokeMethod('getLocationPermissionStatus');
      print("🌍 Dart: Native location permission status: $result");
      return result;
    } on PlatformException catch (e) {
      print("🌍 Dart: Failed to get location permission status - Code: ${e.code}, Message: '${e.message}', Details: ${e.details}");
      return 'unknown';
    } catch (e) {
      print("🌍 Dart: Unexpected error getting location permission status: $e");
      return 'unknown';
    }
  }

  // Mở Settings app để user có thể bật lại quyền
  static Future<bool> openAppSettings() async {
    try {
      final bool result = await _channel.invokeMethod('openAppSettings');
      print("📱 Dart: Mở Settings app - success: $result");
      return result;
    } on PlatformException catch (e) {
      print("📱 Dart: Failed to open Settings - Code: ${e.code}, Message: '${e.message}'");
      return false;
    } catch (e) {
      print("📱 Dart: Unexpected error opening Settings: $e");
      return false;
    }
  }

  // Hiển thị dialog hướng dẫn user vào Settings
  static Future<void> showLocationPermissionDialog(BuildContext context) async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Cần quyền truy cập vị trí'),
          content: const Text(
            'Ứng dụng cần quyền truy cập vị trí để hoạt động tốt nhất.\n\n'
            'Vui lòng vào Cài đặt > Quyền riêng tư & Bảo mật > Dịch vụ vị trí > QR Scanner App và bật quyền "Khi sử dụng ứng dụng".',
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Bỏ qua'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: const Text('Mở Cài đặt'),
              onPressed: () async {
                Navigator.of(context).pop();
                await openAppSettings();
              },
            ),
          ],
        );
      },
    );
  }
}
