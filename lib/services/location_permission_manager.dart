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
  static const String _permissionDeniedCountKey = 'permission_denied_count';
  static const String _lastDialogShownTimeKey = 'last_dialog_shown_time';
  static const Duration _requestInterval = Duration(minutes: 5); // Giảm từ 30 xuống 5 phút
  static const Duration _longRequestInterval = Duration(minutes: 30); // Cho trường hợp từ chối nhiều lần
  static const Duration _dialogInterval = Duration(minutes: 10); // Khoảng cách giữa các lần hiển thị dialog
  
  static Timer? _periodicTimer;
  static bool _isRequestingPermission = false;
  static bool _isShowingDialog = false; // Flag để tránh hiển thị dialog đồng thời

  /// Khởi tạo manager khi app mở
  static Future<Map<String, dynamic>?> initialize() async {
    await _updateLastAppOpenTime();
    
    // Kiểm tra quyền ngay khi mở app
    if (Platform.isAndroid) {
      final result = await _initializeAndroid();
      _startPeriodicCheck();
      return result;
    } else if (Platform.isIOS) {
      final result = await _initializeIOS();
      _startPeriodicCheck();
      return result;
    }
    
    // Thiết lập timer định kỳ kiểm tra (mỗi 30 phút)
    _startPeriodicCheck();
    return null;
  }

  /// Khởi tạo cho Android
  static Future<Map<String, dynamic>> _initializeAndroid() async {
    print('🤖 [Android INIT] Khởi tạo và kiểm tra quyền vị trí...');
    
    final currentStatus = await Permission.locationWhenInUse.status;
    print('🤖 [Android INIT] Trạng thái quyền hiện tại: $currentStatus');
    
    // Nếu đã có quyền
    if (currentStatus.isGranted) {
      await _resetDeniedCount();
      return {
        'hasPermission': true,
        'needsDialog': false,
        'status': 'already_granted',
        'platform': 'Android'
      };
    }
    
    // Nếu quyền bị từ chối vĩnh viễn
    if (currentStatus.isPermanentlyDenied) {
      await _updateDeniedCount();
      return {
        'hasPermission': false,
        'needsDialog': await _shouldRequestPermission(),
        'status': 'permanently_denied',
        'platform': 'Android'
      };
    }
    
    // Nếu chưa có quyền và có thể yêu cầu
    if (await _shouldRequestPermission()) {
      print('🤖 [Android INIT] 🔄 Yêu cầu quyền vị trí...');
      final result = await Permission.locationWhenInUse.request();
      await _updateLastRequestTime();
      
      if (result.isGranted) {
        await _resetDeniedCount();
        return {
          'hasPermission': true,
          'needsDialog': false,
          'status': 'granted',
          'platform': 'Android'
        };
      } else if (result.isPermanentlyDenied) {
        await _updateDeniedCount();
        return {
          'hasPermission': false,
          'needsDialog': true,
          'status': 'permanently_denied',
          'platform': 'Android'
        };
      } else {
        await _updateDeniedCount();
        return {
          'hasPermission': false,
          'needsDialog': false,
          'status': 'denied',
          'platform': 'Android'
        };
      }
    }
    
    // Chưa đủ thời gian để yêu cầu lại
    return {
      'hasPermission': false,
      'needsDialog': false,
      'status': 'waiting',
      'platform': 'Android'
    };
  }

  /// Khởi tạo cho iOS
  static Future<Map<String, dynamic>> _initializeIOS() async {
    print('🍎 [iOS INIT] Khởi tạo và kiểm tra quyền vị trí...');
    
    final nativeStatus = await NativePermissionService.getLocationPermissionStatus();
    print('🍎 [iOS INIT] Native status: $nativeStatus');
    
    // Nếu đã có quyền
    if (nativeStatus == 'authorized' || nativeStatus == 'authorizedWhenInUse') {
      await _resetDeniedCount();
      return {
        'hasPermission': true,
        'needsDialog': false,
        'status': 'already_granted',
        'platform': 'iOS'
      };
    }
    
    // Nếu quyền bị từ chối hoặc hạn chế
    if (nativeStatus == 'denied' || nativeStatus == 'restricted') {
      await _updateDeniedCount();
      return {
        'hasPermission': false,
        'needsDialog': await _shouldRequestPermission(),
        'status': 'permanently_denied',
        'platform': 'iOS'
      };
    }
    
    // Nếu chưa xác định, thử yêu cầu ngay lập tức
    if (nativeStatus == 'notDetermined') {
      print('🍎 [iOS INIT] 🔄 Yêu cầu native quyền vị trí...');
      final granted = await NativePermissionService.requestLocationPermissionNative();
      await _updateLastRequestTime();
      
      if (granted) {
        await _resetDeniedCount();
        return {
          'hasPermission': true,
          'needsDialog': false,
          'status': 'granted',
          'platform': 'iOS'
        };
      } else {
        await _updateDeniedCount();
        return {
          'hasPermission': false,
          'needsDialog': true,
          'status': 'denied',
          'platform': 'iOS'
        };
      }
    }
    
    return {
      'hasPermission': false,
      'needsDialog': false,
      'status': 'unknown',
      'platform': 'iOS'
    };
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

  /// Logic cho Android: Mỗi lần mở app và mỗi 5-30 phút hỏi lại nếu chưa có quyền
  static Future<void> _checkAndRequestPermissionAndroid() async {
    if (_isRequestingPermission) return;
    
    try {
      _isRequestingPermission = true;
      print('🤖 [Android] Kiểm tra quyền vị trí...');
      
      final currentStatus = await Permission.locationWhenInUse.status;
      print('🤖 [Android] Trạng thái quyền hiện tại: $currentStatus');
      
      if (currentStatus.isGranted) {
        print('🤖 [Android] ✅ Đã có quyền vị trí');
        await _resetDeniedCount(); // Reset đếm khi được cấp quyền
        return;
      }
      
      if (currentStatus.isPermanentlyDenied) {
        print('🤖 [Android] ❌ Quyền bị từ chối vĩnh viễn');
        await _updateDeniedCount();
        return;
      }
      
      // Kiểm tra xem đã hỏi gần đây chưa
      if (await _shouldRequestPermission()) {
        print('🤖 [Android] 🔄 Yêu cầu quyền vị trí...');
        final result = await Permission.locationWhenInUse.request();
        await _updateLastRequestTime();
        
        if (result.isGranted) {
          print('🤖 [Android] ✅ Cấp quyền thành công!');
          await _resetDeniedCount();
        } else {
          print('🤖 [Android] ❌ Từ chối quyền: $result');
          await _updateDeniedCount();
        }
      }
    } catch (e) {
      print('🤖 [Android] 💥 Lỗi: $e');
    } finally {
      _isRequestingPermission = false;
    }
  }

  /// Logic cho iOS: Kiểm tra mỗi lần mở app, hỏi lại sau 5-30 phút nếu chưa có quyền
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
        await _updateDeniedCount();
        
        // Sẽ hiển thị dialog từ UI layer - chỉ khi đã qua thời gian chờ
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
          await _resetDeniedCount();
          return;
        } else {
          print('🍎 [iOS] ❌ Native từ chối quyền');
          await _updateDeniedCount();
        }
      }
      
      // Fallback sang permission_handler nếu native không hoạt động
      final permissionStatus = await Permission.locationWhenInUse.status;
      print('🍎 [iOS] Permission handler status: $permissionStatus');
      
      if (permissionStatus.isGranted) {
        print('🍎 [iOS] ✅ Permission handler đã có quyền');
        await _resetDeniedCount();
        return;
      }
      
      if (permissionStatus.isPermanentlyDenied) {
        print('🍎 [iOS] ❌ Permission handler bị từ chối vĩnh viễn');
        await _updateDeniedCount();
        return;
      }
      
      // Chỉ kiểm tra thời gian cho lần request thứ 2 trở đi
      if (permissionStatus.isDenied && await _shouldRequestPermission()) {
        print('🍎 [iOS] 🔄 Fallback: yêu cầu permission handler...');
        final result = await Permission.locationWhenInUse.request();
        await _updateLastRequestTime();
        
        if (result.isGranted) {
          print('🍎 [iOS] ✅ Permission handler cấp quyền thành công!');
          await _resetDeniedCount();
        } else {
          print('🍎 [iOS] ❌ Permission handler từ chối: $result');
          await _updateDeniedCount();
        }
      }
    } catch (e) {
      print('🍎 [iOS] 💥 Lỗi: $e');
    } finally {
      _isRequestingPermission = false;
    }
  }

  /// Kiểm tra xem có nên yêu cầu quyền không (dựa trên thời gian 5-30 phút)
  static Future<bool> _shouldRequestPermission() async {
    final prefs = await SharedPreferences.getInstance();
    final lastRequestTime = prefs.getInt(_lastRequestTimeKey);
    final lastAppOpenTime = prefs.getInt(_lastAppOpenTimeKey);
    final deniedCount = prefs.getInt(_permissionDeniedCountKey) ?? 0;
    
    if (lastRequestTime == null) {
      return true; // Chưa bao giờ hỏi
    }
    
    final now = DateTime.now().millisecondsSinceEpoch;
    final difference = now - lastRequestTime;
    
    // Nếu đã từ chối quyền và đây là lần mở app mới (sau khi tắt app)
    // thì cho phép hiển thị dialog ngay lập tức
    if (deniedCount > 0 && lastAppOpenTime != null) {
      final timeSinceAppOpen = now - lastAppOpenTime;
      // Nếu app vừa được mở trong vòng 10 giây và đã từ chối quyền trước đó
      if (timeSinceAppOpen < 10000) { // 10 seconds
        print('⏰ App vừa được mở và đã từ chối quyền trước đó - cho phép hiển thị dialog');
        return true;
      }
    }
    
    // Sử dụng khoảng thời gian khác nhau tùy theo số lần từ chối
    final interval = deniedCount >= 3 ? _longRequestInterval : _requestInterval;
    final shouldRequest = difference >= interval.inMilliseconds;
    
    print('⏰ Thời gian từ lần hỏi cuối: ${Duration(milliseconds: difference).inMinutes} phút');
    print('⏰ Số lần từ chối: $deniedCount');
    print('⏰ Khoảng thời gian chờ: ${interval.inMinutes} phút');
    print('⏰ Có nên hỏi lại không: $shouldRequest');
    
    return shouldRequest;
  }

  /// Cập nhật số lần từ chối quyền
  static Future<void> _updateDeniedCount() async {
    final prefs = await SharedPreferences.getInstance();
    final currentCount = prefs.getInt(_permissionDeniedCountKey) ?? 0;
    await prefs.setInt(_permissionDeniedCountKey, currentCount + 1);
    print('📊 Cập nhật số lần từ chối: ${currentCount + 1}');
  }

  /// Reset số lần từ chối khi được cấp quyền
  static Future<void> _resetDeniedCount() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_permissionDeniedCountKey);
    print('✅ Reset số lần từ chối');
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
        await _resetDeniedCount(); // Reset đếm khi có quyền
        return true;
      }
    }
    
    final status = await Permission.locationWhenInUse.status;
    if (status.isGranted) {
      await _resetDeniedCount(); // Reset đếm khi có quyền
    }
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

  /// Dọn dẹp resources
  static void dispose() {
    _periodicTimer?.cancel();
    _periodicTimer = null;
  }

  /// Force yêu cầu quyền ngay lập tức (dùng khi user click vào nút cụ thể)
  static Future<Map<String, dynamic>> forceRequestPermission() async {
    if (Platform.isAndroid) {
      return await _forceRequestPermissionAndroid();
    } else if (Platform.isIOS) {
      return await _forceRequestPermissionIOS();
    }
    
    return {
      'granted': false,
      'status': 'unsupported_platform',
      'shouldShowDialog': false
    };
  }

  /// Force request cho Android
  static Future<Map<String, dynamic>> _forceRequestPermissionAndroid() async {
    final currentStatus = await Permission.locationWhenInUse.status;
    print('🤖 [Android Force] Trạng thái quyền hiện tại: $currentStatus');
    
    // Nếu đã có quyền
    if (currentStatus.isGranted) {
      await _resetDeniedCount();
      return {
        'granted': true,
        'status': 'already_granted',
        'shouldShowDialog': false
      };
    }
    
    // Nếu quyền bị từ chối vĩnh viễn
    if (currentStatus.isPermanentlyDenied) {
      await _updateDeniedCount();
      return {
        'granted': false,
        'status': 'permanently_denied',
        'shouldShowDialog': true
      };
    }
    
    // Thử yêu cầu quyền
    final result = await Permission.locationWhenInUse.request();
    await _updateLastRequestTime();
    
    if (result.isGranted) {
      await _resetDeniedCount();
      return {
        'granted': true,
        'status': 'granted',
        'shouldShowDialog': false
      };
    } else if (result.isPermanentlyDenied) {
      await _updateDeniedCount();
      return {
        'granted': false,
        'status': 'permanently_denied',
        'shouldShowDialog': true
      };
    } else {
      await _updateDeniedCount();
      return {
        'granted': false,
        'status': 'denied',
        'shouldShowDialog': false
      };
    }
  }

  /// Force request cho iOS
  static Future<Map<String, dynamic>> _forceRequestPermissionIOS() async {
    // Thử native trước
    final nativeStatus = await NativePermissionService.getLocationPermissionStatus();
    print('🍎 [iOS Force] Native status hiện tại: $nativeStatus');
    
    // Nếu đã có quyền
    if (nativeStatus == 'authorized' || nativeStatus == 'authorizedWhenInUse') {
      await _resetDeniedCount();
      return {
        'granted': true,
        'status': 'already_granted',
        'shouldShowDialog': false
      };
    }
    
    // Nếu quyền bị từ chối hoặc hạn chế
    if (nativeStatus == 'denied' || nativeStatus == 'restricted') {
      await _updateDeniedCount();
      return {
        'granted': false,
        'status': 'permanently_denied',
        'shouldShowDialog': true
      };
    }
    
    // Nếu chưa xác định, thử yêu cầu
    if (nativeStatus == 'notDetermined') {
      final granted = await NativePermissionService.requestLocationPermissionNative();
      await _updateLastRequestTime();
      
      if (granted) {
        await _resetDeniedCount();
        return {
          'granted': true,
          'status': 'granted',
          'shouldShowDialog': false
        };
      } else {
        await _updateDeniedCount();
        return {
          'granted': false,
          'status': 'denied',
          'shouldShowDialog': true
        };
      }
    }
    
    // Fallback sang permission_handler
    final permissionStatus = await Permission.locationWhenInUse.status;
    print('🍎 [iOS Force] Permission handler status: $permissionStatus');
    
    if (permissionStatus.isGranted) {
      await _resetDeniedCount();
      return {
        'granted': true,
        'status': 'already_granted',
        'shouldShowDialog': false
      };
    }
    
    if (permissionStatus.isPermanentlyDenied) {
      await _updateDeniedCount();
      return {
        'granted': false,
        'status': 'permanently_denied',
        'shouldShowDialog': true
      };
    }
    
    // Thử yêu cầu quyền qua permission_handler
    final result = await Permission.locationWhenInUse.request();
    await _updateLastRequestTime();
    
    if (result.isGranted) {
      await _resetDeniedCount();
      return {
        'granted': true,
        'status': 'granted',
        'shouldShowDialog': false
      };
    } else if (result.isPermanentlyDenied) {
      await _updateDeniedCount();
      return {
        'granted': false,
        'status': 'permanently_denied',
        'shouldShowDialog': true
      };
    } else {
      await _updateDeniedCount();
      return {
        'granted': false,
        'status': 'denied',
        'shouldShowDialog': true
      };
    }
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
        print('🍎 [iOS FORCE] ❌ Quyền bị từ chối - sẽ hiển thị dialog sau 5p hoặc lần mở app tiếp theo');
        await _updateDeniedCount();
        return 'granted'; // Trả về 'granted' để không hiển thị popup ngay lập tức
      }
      
      // Force request nếu chưa xác định
      if (nativeStatus == 'notDetermined') {
        print('🍎 [iOS FORCE] 🔄 Force request native permission...');
        final granted = await NativePermissionService.requestLocationPermissionNative();
        await _updateLastRequestTime();
        
        if (granted) {
          print('🍎 [iOS FORCE] ✅ Native cấp quyền thành công!');
          await _resetDeniedCount();
          return 'granted';
        } else {
          print('🍎 [iOS FORCE] ❌ Native từ chối quyền - sẽ hiển thị dialog sau 5p hoặc lần mở app tiếp theo');
          await _updateDeniedCount();
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
    if (Platform.isIOS) {
      await _checkAndShowPermissionDialogIOS(context);
    } else if (Platform.isAndroid) {
      await _checkAndShowPermissionDialogAndroid(context);
    }
  }

  /// Xử lý initialization result - gọi sau khi initialize() để hiển thị dialog nếu cần
  static Future<void> handleInitializationResult(
    BuildContext context, 
    Map<String, dynamic>? initResult
  ) async {
    if (initResult == null) {
      print('🔧 Không có kết quả initialization để xử lý');
      return;
    }
    
    print('🔧 Xử lý kết quả initialization: $initResult');
    
    // Kiểm tra flag để tránh hiển thị dialog đồng thời
    if (_isShowingDialog) {
      print('🔧 Đang hiển thị dialog khác, bỏ qua lần này');
      return;
    }
    
    // Nếu cần hiển thị dialog
    if (initResult['needsDialog'] == true) {
      // Kiểm tra xem đã hiển thị dialog gần đây chưa
      if (await _shouldShowDialog()) {
        print('🔧 Cần hiển thị dialog hướng dẫn Settings');
        
        // Set flag để tránh hiển thị đồng thời
        _isShowingDialog = true;
        
        try {
          // Debug thêm thông tin
          final debugInfo = await getDebugInfo();
          print('🔧 Debug info trước khi hiển thị dialog: $debugInfo');
          
          await PermissionDialogService.showLocationPermissionDialog(context);
          // Cập nhật thời gian hiển thị dialog
          await _updateDialogShownTime();
          
          print('🔧 Đã hiển thị dialog và cập nhật thời gian');
        } finally {
          // Reset flag sau khi dialog đóng
          _isShowingDialog = false;
        }
      } else {
        print('🔧 Đã hiển thị dialog gần đây, bỏ qua lần này');
      }
    } else {
      print('🔧 Không cần hiển thị dialog - hasPermission: ${initResult['hasPermission']}, status: ${initResult['status']}');
    }
  }

  /// Kiểm tra xem có nên hiển thị dialog không (tránh spam dialog)
  static Future<bool> _shouldShowDialog() async {
    final prefs = await SharedPreferences.getInstance();
    final lastDialogTime = prefs.getInt(_lastDialogShownTimeKey);
    
    if (lastDialogTime == null) {
      return true; // Chưa bao giờ hiển thị dialog
    }
    
    final now = DateTime.now().millisecondsSinceEpoch;
    final difference = now - lastDialogTime;
    final shouldShow = difference >= _dialogInterval.inMilliseconds;
    
    print('🔧 Thời gian từ lần hiển thị dialog cuối: ${Duration(milliseconds: difference).inMinutes} phút');
    print('🔧 Có nên hiển thị dialog không: $shouldShow');
    
    return shouldShow;
  }

  /// Cập nhật thời gian hiển thị dialog cuối cùng
  static Future<void> _updateDialogShownTime() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_lastDialogShownTimeKey, DateTime.now().millisecondsSinceEpoch);
    print('📊 Cập nhật thời gian hiển thị dialog');
  }

  /// Xử lý riêng cho iOS
  static Future<void> _checkAndShowPermissionDialogIOS(BuildContext context) async {
    final nativeStatus = await NativePermissionService.getLocationPermissionStatus();
    print('🔍 [iOS] Kiểm tra quyền để hiển thị dialog - Native status: $nativeStatus');
    
    // Nếu đã có quyền thì không làm gì
    if (nativeStatus == 'authorized' || nativeStatus == 'authorizedWhenInUse') {
      print('🔍 [iOS] ✅ Đã có quyền, không cần dialog');
      return;
    }
    
    // Nếu chưa xác định (lần đầu), yêu cầu quyền ngay lập tức
    if (nativeStatus == 'notDetermined') {
      print('🔍 [iOS] 🔄 Chưa xác định, yêu cầu quyền ngay...');
      final granted = await NativePermissionService.requestLocationPermissionNative();
      await _updateLastRequestTime();
      
      if (granted) {
        print('🔍 [iOS] ✅ Cấp quyền thành công!');
        await _resetDeniedCount();
      } else {
        print('🔍 [iOS] ❌ Từ chối quyền - sẽ hiển thị dialog hướng dẫn sau');
        await _updateDeniedCount();
        // Hiển thị dialog hướng dẫn ngay sau khi từ chối
        if (await _shouldRequestPermission()) {
          await PermissionDialogService.showLocationPermissionDialog(context);
          await _updateLastRequestTime();
        }
      }
      return;
    }
    
    // Nếu quyền bị từ chối hoặc hạn chế VÀ đã đủ thời gian chờ
    if ((nativeStatus == 'denied' || nativeStatus == 'restricted') && 
        await _shouldRequestPermission()) {
      print('🔍 [iOS] Đã đủ thời gian, hiển thị dialog hướng dẫn mở Settings');
      await PermissionDialogService.showLocationPermissionDialog(context);
      await _updateLastRequestTime();
    } else if (nativeStatus == 'denied' || nativeStatus == 'restricted') {
      print('🔍 [iOS] Chưa đủ thời gian chờ, không hiển thị dialog');
    }
  }

  /// Xử lý riêng cho Android
  static Future<void> _checkAndShowPermissionDialogAndroid(BuildContext context) async {
    final currentStatus = await Permission.locationWhenInUse.status;
    print('🔍 [Android] Kiểm tra quyền để hiển thị dialog - Status: $currentStatus');
    
    // Nếu đã có quyền thì không làm gì
    if (currentStatus.isGranted) {
      print('🔍 [Android] ✅ Đã có quyền, không cần dialog');
      await _resetDeniedCount();
      return;
    }
    
    // Nếu quyền bị từ chối vĩnh viễn, hiển thị dialog hướng dẫn mở Settings
    if (currentStatus.isPermanentlyDenied) {
      print('🔍 [Android] ❌ Quyền bị từ chối vĩnh viễn - hiển thị dialog Settings');
      if (await _shouldRequestPermission()) {
        await PermissionDialogService.showLocationPermissionDialog(context);
        await _updateLastRequestTime();
      }
      return;
    }
    
    // Nếu chưa có quyền nhưng chưa bị từ chối vĩnh viễn, thử yêu cầu quyền
    if (currentStatus.isDenied && await _shouldRequestPermission()) {
      print('🔍 [Android] 🔄 Yêu cầu quyền vị trí...');
      final result = await Permission.locationWhenInUse.request();
      await _updateLastRequestTime();
      
      if (result.isGranted) {
        print('🔍 [Android] ✅ Cấp quyền thành công!');
        await _resetDeniedCount();
      } else if (result.isPermanentlyDenied) {
        print('🔍 [Android] ❌ Quyền bị từ chối vĩnh viễn sau khi request');
        await _updateDeniedCount();
        // Hiển thị dialog hướng dẫn mở Settings ngay lập tức
        await PermissionDialogService.showLocationPermissionDialog(context);
      } else {
        print('🔍 [Android] ❌ Từ chối quyền: $result');
        await _updateDeniedCount();
      }
    } else if (currentStatus.isDenied) {
      print('🔍 [Android] Chưa đủ thời gian chờ, không yêu cầu quyền');
    }
  }

  /// Thêm method để manual reset thời gian (cho testing)
  static Future<void> resetRequestTime() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_lastRequestTimeKey);
    await prefs.remove(_permissionDeniedCountKey);
    print('🔄 Reset thời gian yêu cầu quyền và số lần từ chối');
  }

  /// Force reset để debug - xóa tất cả thời gian chờ
  static Future<void> forceResetForDebug() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_lastRequestTimeKey);
    await prefs.remove(_permissionDeniedCountKey);
    await prefs.remove(_lastAppOpenTimeKey);
    await prefs.remove(_lastDialogShownTimeKey);
    print('🔄 FORCE RESET - Xóa tất cả thời gian chờ để debug');
  }

  /// Lấy thông tin thống kê để debug
  static Future<Map<String, dynamic>> getDebugInfo() async {
    final prefs = await SharedPreferences.getInstance();
    final lastRequestTime = prefs.getInt(_lastRequestTimeKey);
    final lastAppOpenTime = prefs.getInt(_lastAppOpenTimeKey);
    final lastDialogTime = prefs.getInt(_lastDialogShownTimeKey);
    final deniedCount = prefs.getInt(_permissionDeniedCountKey) ?? 0;
    
    final now = DateTime.now().millisecondsSinceEpoch;
    final timeSinceLastRequest = lastRequestTime != null 
        ? Duration(milliseconds: now - lastRequestTime)
        : null;
    final timeSinceAppOpen = lastAppOpenTime != null
        ? Duration(milliseconds: now - lastAppOpenTime)
        : null;
    final timeSinceLastDialog = lastDialogTime != null
        ? Duration(milliseconds: now - lastDialogTime)
        : null;

    // Lấy thông tin trạng thái quyền hiện tại
    final permissionStatus = await getLocationPermissionStatus();
    
    return {
      'lastRequestTime': lastRequestTime != null 
          ? DateTime.fromMillisecondsSinceEpoch(lastRequestTime).toString()
          : 'Chưa bao giờ',
      'lastAppOpenTime': lastAppOpenTime != null
          ? DateTime.fromMillisecondsSinceEpoch(lastAppOpenTime).toString()
          : 'Chưa bao giờ',
      'lastDialogTime': lastDialogTime != null
          ? DateTime.fromMillisecondsSinceEpoch(lastDialogTime).toString()
          : 'Chưa bao giờ',
      'deniedCount': deniedCount,
      'timeSinceLastRequest': timeSinceLastRequest?.inMinutes,
      'timeSinceAppOpen': timeSinceAppOpen?.inMinutes,
      'timeSinceLastDialog': timeSinceLastDialog?.inMinutes,
      'shouldRequest': await _shouldRequestPermission(),
      'shouldShowDialog': await _shouldShowDialog(),
      'currentInterval': deniedCount >= 3 ? 30 : 5,
      'dialogInterval': _dialogInterval.inMinutes,
      'permissionStatus': permissionStatus,
      'platform': Platform.isIOS ? 'iOS' : (Platform.isAndroid ? 'Android' : 'Other'),
      'timerActive': _periodicTimer?.isActive ?? false,
      'isRequestingPermission': _isRequestingPermission,
      'isShowingDialog': _isShowingDialog,
    };
  }
}
