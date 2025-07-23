import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/material.dart';
import 'native_permission_service.dart';

class LocationPermissionManager {
  static const String _hasRequestedOnceKey = 'has_requested_location_once';
  
  static bool _isRequestingPermission = false;

  /// Khởi tạo manager khi app mở - chỉ xin quyền lần đầu tiên
  static Future<Map<String, dynamic>?> initialize() async {
    print('📍 [INIT] Khởi tạo LocationPermissionManager...');
    
    // Kiểm tra xem đã từng xin quyền chưa
    final prefs = await SharedPreferences.getInstance();
    final hasRequestedOnce = prefs.getBool(_hasRequestedOnceKey) ?? false;
    
    if (hasRequestedOnce) {
      print('📍 [INIT] Đã từng xin quyền rồi, chỉ kiểm tra trạng thái hiện tại');
      
      // Chỉ kiểm tra và trả về trạng thái hiện tại, không xin quyền
      if (Platform.isAndroid) {
        final status = await Permission.locationWhenInUse.status;
        return {
          'hasPermission': status.isGranted,
          'status': 'already_requested',
          'platform': 'Android'
        };
      } else if (Platform.isIOS) {
        final nativeStatus = await NativePermissionService.getLocationPermissionStatus();
        return {
          'hasPermission': nativeStatus == 'authorized' || nativeStatus == 'authorizedWhenInUse',
          'status': 'already_requested',
          'platform': 'iOS'
        };
      }
    }
    
    // Chưa từng xin quyền, xin lần đầu tiên
    print('📍 [INIT] Lần đầu tiên mở app, xin quyền vị trí...');
    
    if (Platform.isAndroid) {
      return await _requestPermissionFirstTimeAndroid();
    } else if (Platform.isIOS) {
      return await _requestPermissionFirstTimeIOS();
    }
    
    return null;
  }

  /// Xin quyền lần đầu tiên cho Android
  static Future<Map<String, dynamic>> _requestPermissionFirstTimeAndroid() async {
    print('🤖 [Android] Xin quyền vị trí lần đầu tiên...');
    
    final currentStatus = await Permission.locationWhenInUse.status;
    print('🤖 [Android] Trạng thái quyền hiện tại: $currentStatus');
    
    // Nếu đã có quyền
    if (currentStatus.isGranted) {
      await _markAsRequested();
      return {
        'hasPermission': true,
        'status': 'already_granted',
        'platform': 'Android'
      };
    }
    
    // Xin quyền
    final result = await Permission.locationWhenInUse.request();
    await _markAsRequested(); // Đánh dấu đã xin quyền bất kể kết quả
    
    print('🤖 [Android] Kết quả xin quyền: $result');
    
    return {
      'hasPermission': result.isGranted,
      'status': result.isGranted ? 'granted' : 'denied',
      'platform': 'Android'
    };
  }

  /// Xin quyền lần đầu tiên cho iOS
  static Future<Map<String, dynamic>> _requestPermissionFirstTimeIOS() async {
    print('🍎 [iOS] Xin quyền vị trí lần đầu tiên...');
    
    final nativeStatus = await NativePermissionService.getLocationPermissionStatus();
    print('🍎 [iOS] Native status: $nativeStatus');
    
    // Nếu đã có quyền
    if (nativeStatus == 'authorized' || nativeStatus == 'authorizedWhenInUse') {
      await _markAsRequested();
      return {
        'hasPermission': true,
        'status': 'already_granted',
        'platform': 'iOS'
      };
    }
    
    // Nếu chưa xác định, xin quyền bằng native
    if (nativeStatus == 'notDetermined') {
      print('🍎 [iOS] Chưa xác định, xin quyền bằng native...');
      final granted = await NativePermissionService.requestLocationPermissionNative();
      await _markAsRequested(); // Đánh dấu đã xin quyền bất kể kết quả
      
      print('🍎 [iOS] Kết quả native: $granted');
      
      return {
        'hasPermission': granted,
        'status': granted ? 'granted' : 'denied',
        'platform': 'iOS'
      };
    }
    
    // Đã bị từ chối hoặc hạn chế
    await _markAsRequested();
    return {
      'hasPermission': false,
      'status': 'denied_or_restricted',
      'platform': 'iOS'
    };
  }

  /// Đánh dấu đã từng xin quyền
  static Future<void> _markAsRequested() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_hasRequestedOnceKey, true);
    print('📍 Đã đánh dấu là đã xin quyền vị trí');
  }

  /// Kiểm tra xem có quyền vị trí không
  static Future<bool> hasLocationPermission() async {
    if (Platform.isIOS) {
      final nativeStatus = await NativePermissionService.getLocationPermissionStatus();
      return nativeStatus == 'authorized' || nativeStatus == 'authorizedWhenInUse';
    }
    
    final status = await Permission.locationWhenInUse.status;
    return status.isGranted;
  }

  /// Kiểm tra trạng thái quyền vị trí chi tiết
  static Future<Map<String, dynamic>> getLocationPermissionStatus() async {
    if (Platform.isIOS) {
      final nativeStatus = await NativePermissionService.getLocationPermissionStatus();
      return {
        'hasPermission': nativeStatus == 'authorized' || nativeStatus == 'authorizedWhenInUse',
        'isPermanentlyDenied': nativeStatus == 'denied' || nativeStatus == 'restricted',
        'isNotDetermined': nativeStatus == 'notDetermined',
        'nativeStatus': nativeStatus,
        'platform': 'iOS'
      };
    } else if (Platform.isAndroid) {
      final status = await Permission.locationWhenInUse.status;
      return {
        'hasPermission': status.isGranted,
        'isPermanentlyDenied': status.isPermanentlyDenied,
        'isNotDetermined': status.isDenied && !status.isPermanentlyDenied,
        'status': status.toString(),
        'platform': 'Android'
      };
    }
    
    return {
      'hasPermission': false,
      'isPermanentlyDenied': false,
      'isNotDetermined': false,
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

  /// Reset trạng thái đã xin quyền (để test)
  static Future<void> resetRequestedStatus() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_hasRequestedOnceKey);
    print('📍 Reset trạng thái đã xin quyền');
  }

  /// Dọn dẹp resources (không cần thiết cho phiên bản đơn giản)
  static void dispose() {
    print('📍 [DISPOSE] LocationPermissionManager disposed');
  }

  /// Lấy debug info
  static Future<Map<String, dynamic>> getDebugInfo() async {
    final prefs = await SharedPreferences.getInstance();
    final hasRequestedOnce = prefs.getBool(_hasRequestedOnceKey) ?? false;
    final permissionStatus = await getLocationPermissionStatus();
    
    return {
      'hasRequestedOnce': hasRequestedOnce,
      'permissionStatus': permissionStatus,
      'platform': Platform.isIOS ? 'iOS' : (Platform.isAndroid ? 'Android' : 'Other'),
    };
  }
}
