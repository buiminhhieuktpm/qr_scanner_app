import 'dart:io';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/material.dart';
import 'native_permission_service.dart';
import 'permission_dialog_service.dart';

class LocationPermissionManager {
  static const String _lastRequestTimeKey = 'last_location_permission_request_time';
  static const String _lastAppOpenTimeKey = 'last_app_open_time';
  static const Duration _requestInterval = Duration(minutes: 30);
  
  static Timer? _periodicTimer;
  static bool _isRequestingPermission = false;

  /// Khởi tạo manager khi app mở
  static Future<String?> initialize() async {
    await _updateLastAppOpenTime();
    
    // Kiểm tra quyền ngay khi mở app
    if (Platform.isAndroid) {
      await _checkAndRequestPermissionAndroid();
      return null;
    } else if (Platform.isIOS) {
      // Force request cho iOS để popup hiển thị ngay lập tức
      final result = await forceRequestLocationPermissionIOS();
      print('🍎 [iOS INIT] Kết quả force request: $result');
      
      // Thiết lập timer định kỳ kiểm tra (mỗi 30 phút)
      _startPeriodicCheck();
      
      return result; // Trả về kết quả để UI có thể xử lý
    }
    
    // Thiết lập timer định kỳ kiểm tra (mỗi 30 phút)
    _startPeriodicCheck();
    return null;
  }

  /// Cập nhật thời gian mở app cuối cùng
  static Future<void> _updateLastAppOpenTime() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_lastAppOpenTimeKey, DateTime.now().millisecondsSinceEpoch);
  }

  /// Bắt đầu timer định kỳ kiểm tra quyền vị trí
  static void _startPeriodicCheck() {
    _periodicTimer?.cancel();
    _periodicTimer = Timer.periodic(_requestInterval, (timer) {
      if (Platform.isAndroid) {
        _checkAndRequestPermissionAndroid();
      } else if (Platform.isIOS) {
        _checkAndRequestPermissionIOS();
      }
    });
  }

  /// Logic cho Android: Mỗi lần mở app và mỗi 30 phút hỏi lại nếu chưa có quyền
  static Future<void> _checkAndRequestPermissionAndroid() async {
    if (_isRequestingPermission) return;
    
    try {
      _isRequestingPermission = true;
      print('🤖 [Android] Kiểm tra quyền vị trí...');
      
      final currentStatus = await Permission.locationWhenInUse.status;
      print('🤖 [Android] Trạng thái quyền hiện tại: $currentStatus');
      
      if (currentStatus.isGranted) {
        print('🤖 [Android] ✅ Đã có quyền vị trí');
        return;
      }
      
      if (currentStatus.isPermanentlyDenied) {
        print('🤖 [Android] ❌ Quyền bị từ chối vĩnh viễn');
        return;
      }
      
      // Kiểm tra xem đã hỏi gần đây chưa
      if (await _shouldRequestPermission()) {
        print('🤖 [Android] 🔄 Yêu cầu quyền vị trí...');
        final result = await Permission.locationWhenInUse.request();
        await _updateLastRequestTime();
        
        if (result.isGranted) {
          print('🤖 [Android] ✅ Cấp quyền thành công!');
        } else {
          print('🤖 [Android] ❌ Từ chối quyền: $result');
        }
      }
    } catch (e) {
      print('🤖 [Android] 💥 Lỗi: $e');
    } finally {
      _isRequestingPermission = false;
    }
  }

  /// Logic cho iOS: Kiểm tra mỗi lần mở app, hỏi lại sau 30 phút nếu chưa có quyền
  static Future<void> _checkAndRequestPermissionIOS() async {
    if (_isRequestingPermission) return;
    
    try {
      _isRequestingPermission = true;
      print('🍎 [iOS] Kiểm tra quyền vị trí...');
      
      // Ưu tiên native iOS permission
      final nativeStatus = await NativePermissionService.getLocationPermissionStatus();
      print('🍎 [iOS] Native status: $nativeStatus');
      
      if (nativeStatus == 'authorized' || nativeStatus == 'authorizedWhenInUse') {
        print('🍎 [iOS] ✅ Native đã có quyền vị trí');
        return;
      }
      
      if (nativeStatus == 'denied') {
        print('🍎 [iOS] ❌ Native quyền bị từ chối - cần hướng dẫn vào Settings');
        // Sẽ hiển thị dialog từ UI layer - chỉ khi đã qua 30 phút hoặc mở app lần tiếp theo
        if (await _shouldRequestPermission()) {
          print('🍎 [iOS] 📝 Đã đủ thời gian - cần hiển thị dialog hướng dẫn');
          // Logic hiển thị dialog sẽ được xử lý ở UI layer
        }
        return;
      }
      
      // Nếu chưa xác định, request ngay lập tức
      if (nativeStatus == 'notDetermined') {
        print('🍎 [iOS] 🔄 Yêu cầu native quyền vị trí ngay lập tức...');
        final granted = await NativePermissionService.requestLocationPermissionNative();
        await _updateLastRequestTime();
        
        if (granted) {
          print('🍎 [iOS] ✅ Native cấp quyền thành công!');
          return;
        } else {
          print('🍎 [iOS] ❌ Native từ chối quyền');
        }
      }
      
      // Fallback sang permission_handler nếu native không hoạt động
      final permissionStatus = await Permission.locationWhenInUse.status;
      print('🍎 [iOS] Permission handler status: $permissionStatus');
      
      if (permissionStatus.isGranted) {
        print('🍎 [iOS] ✅ Permission handler đã có quyền');
        return;
      }
      
      if (permissionStatus.isPermanentlyDenied) {
        print('🍎 [iOS] ❌ Permission handler bị từ chối vĩnh viễn');
        return;
      }
      
      // Chỉ kiểm tra thời gian cho lần request thứ 2 trở đi
      if (permissionStatus.isDenied && await _shouldRequestPermission()) {
        print('🍎 [iOS] 🔄 Fallback: yêu cầu permission handler...');
        final result = await Permission.locationWhenInUse.request();
        await _updateLastRequestTime();
        
        if (result.isGranted) {
          print('🍎 [iOS] ✅ Permission handler cấp quyền thành công!');
        } else {
          print('🍎 [iOS] ❌ Permission handler từ chối: $result');
        }
      }
    } catch (e) {
      print('🍎 [iOS] 💥 Lỗi: $e');
    } finally {
      _isRequestingPermission = false;
    }
  }

  /// Kiểm tra xem có nên yêu cầu quyền không (dựa trên thời gian 30 phút)
  static Future<bool> _shouldRequestPermission() async {
    final prefs = await SharedPreferences.getInstance();
    final lastRequestTime = prefs.getInt(_lastRequestTimeKey);
    
    if (lastRequestTime == null) {
      return true; // Chưa bao giờ hỏi
    }
    
    final now = DateTime.now().millisecondsSinceEpoch;
    final difference = now - lastRequestTime;
    final shouldRequest = difference >= _requestInterval.inMilliseconds;
    
    print('⏰ Thời gian từ lần hỏi cuối: ${Duration(milliseconds: difference).inMinutes} phút');
    print('⏰ Có nên hỏi lại không: $shouldRequest');
    
    return shouldRequest;
  }

  /// Cập nhật thời gian yêu cầu quyền cuối cùng
  static Future<void> _updateLastRequestTime() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_lastRequestTimeKey, DateTime.now().millisecondsSinceEpoch);
  }

  /// Kiểm tra xem có quyền vị trí không
  static Future<bool> hasLocationPermission() async {
    if (Platform.isIOS) {
      final nativeStatus = await NativePermissionService.getLocationPermissionStatus();
      if (nativeStatus == 'authorized' || nativeStatus == 'authorizedWhenInUse') {
        return true;
      }
    }
    
    final status = await Permission.locationWhenInUse.status;
    return status.isGranted;
  }

  /// Dọn dẹp resources
  static void dispose() {
    _periodicTimer?.cancel();
    _periodicTimer = null;
  }

  /// Force yêu cầu quyền ngay lập tức (dùng khi user click vào nút cụ thể)
  static Future<bool> forceRequestPermission() async {
    if (Platform.isAndroid) {
      final result = await Permission.locationWhenInUse.request();
      await _updateLastRequestTime();
      return result.isGranted;
    } else if (Platform.isIOS) {
      // Thử native trước
      final granted = await NativePermissionService.requestLocationPermissionNative();
      if (granted) {
        await _updateLastRequestTime();
        return true;
      }
      
      // Fallback
      final result = await Permission.locationWhenInUse.request();
      await _updateLastRequestTime();
      return result.isGranted;
    }
    
    return false;
  }

  /// Force request quyền vị trí ngay lập tức cho iOS (không kiểm tra thời gian)
  static Future<String> forceRequestLocationPermissionIOS() async {
    if (_isRequestingPermission) return 'busy';
    
    try {
      _isRequestingPermission = true;
      print('🍎 [iOS FORCE] Yêu cầu quyền vị trí ngay lập tức...');
      
      // Kiểm tra status hiện tại
      final nativeStatus = await NativePermissionService.getLocationPermissionStatus();
      print('🍎 [iOS FORCE] Native status: $nativeStatus');
      
      if (nativeStatus == 'authorized' || nativeStatus == 'authorizedWhenInUse') {
        print('🍎 [iOS FORCE] ✅ Đã có quyền vị trí');
        return 'granted';
      }
      
      if (nativeStatus == 'denied') {
        print('🍎 [iOS FORCE] ❌ Quyền bị từ chối - sẽ hiển thị dialog sau 30p hoặc lần mở app tiếp theo');
        return 'granted'; // Trả về 'granted' để không hiển thị popup ngay lập tức
      }
      
      // Force request nếu chưa xác định
      if (nativeStatus == 'notDetermined') {
        print('🍎 [iOS FORCE] 🔄 Force request native permission...');
        final granted = await NativePermissionService.requestLocationPermissionNative();
        await _updateLastRequestTime();
        
        if (granted) {
          print('🍎 [iOS FORCE] ✅ Native cấp quyền thành công!');
          return 'granted';
        } else {
          print('🍎 [iOS FORCE] ❌ Native từ chối quyền - sẽ hiển thị dialog sau 30p hoặc lần mở app tiếp theo');
          return 'granted'; // Trả về 'granted' để không hiển thị popup ngay lập tức
        }
      }
      
      return 'unknown';
    } catch (e) {
      print('🍎 [iOS FORCE] 💥 Lỗi: $e');
      return 'error';
    } finally {
      _isRequestingPermission = false;
    }
  }

  /// Kiểm tra quyền và hiển thị dialog nếu cần thiết
  static Future<void> checkAndShowPermissionDialog(BuildContext context) async {
    final nativeStatus = await NativePermissionService.getLocationPermissionStatus();
    print('🔍 Kiểm tra quyền để hiển thị dialog - Native status: $nativeStatus');
    
    // Chỉ hiển thị dialog nếu quyền bị từ chối VÀ đã đủ thời gian (30 phút)
    if ((nativeStatus == 'denied' || nativeStatus == 'restricted') && 
        await _shouldRequestPermission()) {
      print('🔍 Đã đủ thời gian, hiển thị dialog hướng dẫn');
      await PermissionDialogService.showLocationPermissionDialog(context);
      // Cập nhật thời gian để không hiển thị liên tục
      await _updateLastRequestTime();
    } else if (nativeStatus == 'denied' || nativeStatus == 'restricted') {
      print('🔍 Chưa đủ 30 phút, không hiển thị dialog');
    }
  }
}
