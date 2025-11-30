import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'native_permission_service.dart';

class LocationPermissionManager {
  static const String _hasShownLocationDisabledDialogKey = 'has_shown_location_disabled_dialog';
  static bool _locationDialogShown = false;

  /// Kiểm tra xem đã hiển thị dialog location disabled chưa
  static Future<bool> hasShownLocationDisabledDialog() async {
    if (_locationDialogShown) return true;
    
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_hasShownLocationDisabledDialogKey) ?? false;
  }

  /// Đánh dấu đã hiển thị dialog location disabled
  static Future<void> markLocationDisabledDialogShown() async {
    _locationDialogShown = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_hasShownLocationDisabledDialogKey, true);
  }

  /// Reset trạng thái dialog (để test)
  static Future<void> resetLocationDisabledDialog() async {
    _locationDialogShown = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_hasShownLocationDisabledDialogKey);
  }

  /// Khởi tạo manager khi app mở - luôn check và xin quyền nếu cần
  static Future<Map<String, dynamic>?> initialize() async {
    print('📍 [INIT] Khởi tạo LocationPermissionManager...');
    
    // Reset dialog state mỗi khi khởi động app để có thể hiển thị lại nếu cần
    _locationDialogShown = false;
    
    // Luôn kiểm tra trạng thái hiện tại và xin quyền nếu notDetermined
    if (Platform.isAndroid) {
      return await _checkAndRequestPermissionAndroid();
    } else if (Platform.isIOS) {
      return await _checkAndRequestPermissionIOS();
    }
    
    return null;
  }
  
  /// Xin quyền trực tiếp (chỉ popup hệ thống, không show dialog tự tạo)
  static Future<Map<String, dynamic>?> requestPermissionSilently() async {
    print('📍 [SILENT] Xin quyền vị trí trực tiếp...');
    
    if (Platform.isAndroid) {
      final currentStatus = await Permission.locationWhenInUse.status;
      
      // Nếu đã có quyền
      if (currentStatus.isGranted) {
        return {'hasPermission': true, 'status': 'granted'};
      }
      
      // Nếu bị chặn vĩnh viễn
      if (currentStatus.isPermanentlyDenied) {
        return {'hasPermission': false, 'status': 'permanently_denied'};
      }
      
      // Xin quyền trực tiếp (chỉ popup hệ thống)
      final result = await Permission.locationWhenInUse.request();
      return {
        'hasPermission': result.isGranted,
        'status': result.isGranted ? 'granted' : 'denied'
      };
    } else if (Platform.isIOS) {
      final nativeStatus = await NativePermissionService.getLocationPermissionStatus();
      
      // Nếu đã có quyền
      if (nativeStatus == 'authorizedWhenInUse' || nativeStatus == 'authorizedAlways') {
        return {'hasPermission': true, 'status': 'granted'};
      }
      
      // Nếu bị chặn vĩnh viễn
      if (nativeStatus == 'denied' || nativeStatus == 'restricted') {
        return {'hasPermission': false, 'status': 'permanently_denied'};
      }
      
      // Xin quyền trực tiếp (chỉ popup hệ thống)
      if (nativeStatus == 'notDetermined') {
        final granted = await NativePermissionService.requestLocationPermissionNative();
        return {
          'hasPermission': granted,
          'status': granted ? 'granted' : 'denied'
        };
      }
    }
    
    return null;
  }

  /// Kiểm tra và xin quyền cho Android - luôn xin quyền nếu notDetermined
  static Future<Map<String, dynamic>> _checkAndRequestPermissionAndroid() async {
    print('🤖 [Android] Kiểm tra và xin quyền vị trí...');
    
    // TRƯỜNG HỢP 1: Kiểm tra Location Services có bật không
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    print('🤖 [Android] Location Services enabled: $serviceEnabled');
    
    if (!serviceEnabled) {
      print('🤖 [Android] ❌ Location Services bị tắt trên thiết bị');
      return {
        'hasPermission': false,
        'status': 'services_disabled',
        'reason': 'Location Services bị tắt trên thiết bị',
        'platform': 'Android',
        'needsDialog': true,
        'dialogType': 'services_disabled'
      };
    }
    
    final currentStatus = await Permission.locationWhenInUse.status;
    print('🤖 [Android] Trạng thái quyền hiện tại: $currentStatus');
    
    // Nếu đã có quyền
    if (currentStatus.isGranted) {
      print('🤖 [Android] ✅ Đã có quyền vị trí');
      return {
        'hasPermission': true,
        'status': 'already_granted',
        'platform': 'Android',
        'needsDialog': false
      };
    }
    
    // TRƯỜNG HỢP 2: Bị chặn vĩnh viễn (kiểm tra trước khi xin quyền)
    if (currentStatus.isPermanentlyDenied) {
      print('🤖 [Android] 🚫 Quyền vị trí bị chặn vĩnh viễn');
      return {
        'hasPermission': false,
        'status': 'permanently_denied',
        'reason': 'Người dùng đã từ chối quyền và chọn "Don\'t ask again"',
        'platform': 'Android',
        'needsDialog': true,
        'dialogType': 'permanently_denied'
      };
    }
    
    // TRƯỜNG HỢP 3: Chưa cấp quyền hoặc "Ask Next Time" - XIN QUYỀN
    print('🤖 [Android] ⚠️ Quyền chưa xác định (notDetermined) - xin quyền...');
    final result = await Permission.locationWhenInUse.request();
    
    print('🤖 [Android] Kết quả xin quyền: $result');
    
    // Nếu bị từ chối vĩnh viễn sau khi xin
    if (result.isPermanentlyDenied) {
      return {
        'hasPermission': false,
        'status': 'permanently_denied',
        'reason': 'Người dùng đã từ chối quyền và chọn "Don\'t ask again"',
        'platform': 'Android',
        'needsDialog': true,
        'dialogType': 'permanently_denied'
      };
    }
    
    return {
      'hasPermission': result.isGranted,
      'status': result.isGranted ? 'granted' : 'denied',
      'platform': 'Android',
      'needsDialog': !result.isGranted,
      'dialogType': result.isGranted ? null : 'permission_denied'
    };
  }

  /// Kiểm tra và xin quyền cho iOS - luôn xin quyền nếu notDetermined
  static Future<Map<String, dynamic>> _checkAndRequestPermissionIOS() async {
    print('🍎 [iOS] Kiểm tra và xin quyền vị trí...');
    
    final nativeStatus = await NativePermissionService.getLocationPermissionStatus();
    print('🍎 [iOS] Native status: $nativeStatus');
    
    // TRƯỜNG HỢP 1: Location Services bị tắt
    if (nativeStatus == 'servicesDisabled') {
      print('🍎 [iOS] ❌ Location Services bị tắt trên thiết bị');
      return {
        'hasPermission': false,
        'status': 'services_disabled',
        'reason': 'Location Services bị tắt trên thiết bị',
        'platform': 'iOS',
        'needsDialog': true,
        'dialogType': 'services_disabled'
      };
    }
    
    // TRƯỜNG HỢP 2: Đã có quyền
    if (nativeStatus == 'authorizedWhenInUse' || nativeStatus == 'authorizedAlways') {
      print('🍎 [iOS] ✅ Đã có quyền vị trí');
      return {
        'hasPermission': true,
        'status': 'already_granted',
        'platform': 'iOS',
        'needsDialog': false
      };
    }
    
    // TRƯỜNG HỢP 3: Chưa xác định (notDetermined) hoặc "Ask Next Time" - XIN QUYỀN
    if (nativeStatus == 'notDetermined') {
      print('🍎 [iOS] ⚠️ Quyền chưa xác định (notDetermined hoặc Ask Next Time) - xin quyền...');
      final granted = await NativePermissionService.requestLocationPermissionNative();
      
      print('🍎 [iOS] Kết quả xin quyền: $granted');
      
      return {
        'hasPermission': granted,
        'status': granted ? 'granted' : 'denied',
        'platform': 'iOS',
        'needsDialog': !granted,
        'dialogType': granted ? null : 'permission_denied'
      };
    }
    
    // TRƯỜNG HỢP 4: Bị chặn vĩnh viễn (denied hoặc restricted)
    if (nativeStatus == 'denied' || nativeStatus == 'restricted') {
      print('🍎 [iOS] 🚫 Quyền vị trí bị chặn vĩnh viễn: $nativeStatus');
      return {
        'hasPermission': false,
        'status': 'permanently_denied',
        'reason': nativeStatus == 'restricted' ? 'Bị hạn chế bởi chính sách thiết bị' : 'Người dùng đã từ chối quyền',
        'platform': 'iOS',
        'needsDialog': true,
        'dialogType': 'permanently_denied'
      };
    }
    
    // Trường hợp không xác định
    return {
      'hasPermission': false,
      'status': 'unknown',
      'platform': 'iOS',
      'needsDialog': false
    };
  }



  /// Kiểm tra xem có quyền vị trí không
  static Future<bool> hasLocationPermission() async {
    if (Platform.isIOS) {
      final nativeStatus = await NativePermissionService.getLocationPermissionStatus();
      // Kiểm tra cả Location Services và quyền ứng dụng
      if (nativeStatus == 'servicesDisabled') return false;
      return nativeStatus == 'authorizedWhenInUse' || nativeStatus == 'authorizedAlways';
    }
    
    // Android: Kiểm tra cả Location Services và quyền ứng dụng
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;
    
    final status = await Permission.locationWhenInUse.status;
    return status.isGranted;
  }

  /// Kiểm tra trạng thái quyền vị trí chi tiết
  static Future<Map<String, dynamic>> getLocationPermissionStatus() async {
    if (Platform.isIOS) {
      final nativeStatus = await NativePermissionService.getLocationPermissionStatus();
      
      // TRƯỜNG HỢP 1: Location Services bị tắt
      if (nativeStatus == 'servicesDisabled') {
        return {
          'hasPermission': false,
          'isPermanentlyDenied': false,
          'isNotDetermined': false,
          'isServicesDisabled': true,
          'nativeStatus': nativeStatus,
          'platform': 'iOS'
        };
      }
      
      return {
        'hasPermission': nativeStatus == 'authorizedWhenInUse' || nativeStatus == 'authorizedAlways',
        'isPermanentlyDenied': nativeStatus == 'denied' || nativeStatus == 'restricted',
        'isNotDetermined': nativeStatus == 'notDetermined',
        'isServicesDisabled': false,
        'nativeStatus': nativeStatus,
        'platform': 'iOS'
      };
    } else if (Platform.isAndroid) {
      // Kiểm tra Location Services có bật không
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      
      // TRƯỜNG HỢP 1: Location Services bị tắt
      if (!serviceEnabled) {
        return {
          'hasPermission': false,
          'isPermanentlyDenied': false,
          'isNotDetermined': false,
          'isServicesDisabled': true,
          'status': 'services_disabled',
          'platform': 'Android'
        };
      }
      
      final status = await Permission.locationWhenInUse.status;
      return {
        'hasPermission': status.isGranted,
        'isPermanentlyDenied': status.isPermanentlyDenied,
        'isNotDetermined': status.isDenied && !status.isPermanentlyDenied,
        'isServicesDisabled': false,
        'status': status.toString(),
        'platform': 'Android'
      };
    }
    
    return {
      'hasPermission': false,
      'isPermanentlyDenied': false,
      'isNotDetermined': false,
      'isServicesDisabled': false,
      'platform': 'Unknown'
    };
  }

  /// Xử lý kết quả từ initialize (không cần thiết cho phiên bản đơn giản)
  static Future<void> handleInitializationResult(
    BuildContext context, 
    Map<String, dynamic>? result
  ) async {
    if (result == null) return;
    
    print('📍 [HANDLE] Kết quả khởi tạo: $result');
    
    // Với phiên bản đơn giản, chúng ta chỉ cần log kết quả
    // Không cần hiển thị dialog hay xử lý phức tạp
    final hasPermission = result['hasPermission'] ?? false;
    final status = result['status'] ?? 'unknown';
    
    if (hasPermission) {
      print('📍 [HANDLE] ✅ Đã có quyền vị trí');
    } else {
      print('📍 [HANDLE] ❌ Không có quyền vị trí - Status: $status');
    }
  }



  /// Hiển thị dialog location service disabled một lần duy nhất
  static Future<void> showLocationServiceDisabledDialog(BuildContext context) async {
    // Kiểm tra nếu dialog đã được hiển thị trong session này
    if (_locationDialogShown) {
      print('📍 Dialog location service disabled đã được hiển thị trong session này, bỏ qua');
      return;
    }

    // Kiểm tra nếu dialog đã được hiển thị lâu dài
    final hasShown = await hasShownLocationDisabledDialog();
    if (hasShown) {
      print('📍 Dialog location service disabled đã được hiển thị trước đó, bỏ qua');
      return;
    }

    // Đánh dấu đã hiển thị trong cả session và storage lâu dài
    _locationDialogShown = true;
    await markLocationDisabledDialogShown();
    
    if (!context.mounted) return;

    // Thêm delay nhỏ để tránh spam
    await Future.delayed(const Duration(milliseconds: 500));
    
    if (!context.mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Dịch vụ vị trí bị tắt'),
          content: const Text(
            'Vui lòng bật dịch vụ vị trí trong cài đặt để ứng dụng có thể hoạt động tốt nhất.\n\n'
            'Hướng dẫn:\n'
            '• iPhone: Cài đặt > Quyền riêng tư & Bảo mật > Dịch vụ vị trí\n'
            '• Android: Cài đặt > Vị trí > Bật dịch vụ vị trí'
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
                await NativePermissionService.openAppSettings();
              },
            ),
          ],
        );
      },
    );
  }

  /// Dọn dẹp resources (không cần thiết cho phiên bản đơn giản)
  static void dispose() {
    // Reset dialog state khi app đóng để có thể hiển thị lại khi mở app
    _locationDialogShown = false;
    print('📍 [DISPOSE] LocationPermissionManager disposed');
  }

  /// Lấy debug info
  static Future<Map<String, dynamic>> getDebugInfo() async {
    final prefs = await SharedPreferences.getInstance();
    final hasShownDialog = prefs.getBool(_hasShownLocationDisabledDialogKey) ?? false;
    final permissionStatus = await getLocationPermissionStatus();
    
    return {
      'hasShownLocationDisabledDialog': hasShownDialog,
      'locationDialogShownInMemory': _locationDialogShown,
      'permissionStatus': permissionStatus,
      'platform': Platform.isIOS ? 'iOS' : (Platform.isAndroid ? 'Android' : 'Other'),
    };
  }
}
