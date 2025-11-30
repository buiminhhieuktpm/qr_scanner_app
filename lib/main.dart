import 'package:flutter/material.dart';
import 'screens/home_screen.dart';
import 'services/location_permission_manager.dart';
import 'services/global_cookie_manager.dart';
import 'services/native_permission_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Khởi tạo location permission manager (chỉ xin quyền lần đầu tiên)
  final permissionResult = await LocationPermissionManager.initialize();
  
  runApp(MyApp(permissionResult: permissionResult));
}

class MyApp extends StatelessWidget {
  final Map<String, dynamic>? permissionResult;
  
  const MyApp({super.key, this.permissionResult});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'QR Scanner',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: _AppWrapper(permissionResult: permissionResult),
      debugShowCheckedModeBanner: false, // Ẩn banner debug
    );
  }
}

class _AppWrapper extends StatefulWidget {
  final Map<String, dynamic>? permissionResult;

  const _AppWrapper({Key? key, this.permissionResult}) : super(key: key);

  @override
  State<_AppWrapper> createState() => _AppWrapperState();
}

class _AppWrapperState extends State<_AppWrapper> with WidgetsBindingObserver {
  final GlobalCookieManager _globalCookieManager = GlobalCookieManager();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    // Xử lý kết quả permission (chỉ hiển thị dialog khi cần)
    if (widget.permissionResult != null) {
      _handlePermissionResult();
    }
  }

  /// Xử lý kết quả permission và hiển thị popup nếu cần
  void _handlePermissionResult() {
    final result = widget.permissionResult!;
    final hasPermission = result['hasPermission'] ?? false;
    final status = result['status'] ?? 'unknown';
    final needsDialog = result['needsDialog'] ?? false;
    final dialogType = result['dialogType'];
    
    print('📱 [INIT] Kết quả permission: $result');
    
    if (hasPermission) {
      print('📱 [INIT] ✅ Đã có quyền vị trí');
    } else {
      print('📱 [INIT] ❌ Không có quyền vị trí - Status: $status');
      
      // Chỉ hiển thị dialog khi Location Services bị tắt hoặc permanently denied
      if (needsDialog && dialogType != null && 
          (dialogType == 'services_disabled' || dialogType == 'permanently_denied')) {
        // Đợi một chút để UI hoàn tất việc render
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) {
            _showPermissionDialog(dialogType, result['reason']);
          }
        });
      }
    }
  }

  /// Hiển thị dialog quyền dựa trên loại vấn đề
  void _showPermissionDialog(String dialogType, String? reason) {
    String title = 'Quyền vị trí';
    String message = '';
    
    switch (dialogType) {
      case 'services_disabled':
        title = 'Dịch vụ vị trí bị tắt';
        message = 'Vui lòng bật dịch vụ vị trí trong cài đặt để ứng dụng có thể hoạt động tốt nhất.\n\n'
                 'Hướng dẫn:\n'
                 '• iPhone: Cài đặt > Quyền riêng tư & Bảo mật > Dịch vụ vị trí\n'
                 '• Android: Cài đặt > Vị trí > Bật dịch vụ vị trí';
        break;
      case 'permanently_denied':
        title = 'Quyền vị trí bị từ chối';
        message = reason ?? 'Ứng dụng cần quyền truy cập vị trí để hoạt động tốt nhất.';
        message += '\n\nVui lòng vào Cài đặt > QR Scanner App > Vị trí và chọn "Khi sử dụng ứng dụng".';
        break;
      default:
        message = 'Có vấn đề với quyền vị trí.';
    }
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
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

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    LocationPermissionManager.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        // App bị tạm dừng, ẩn hoặc tắt - force save tất cả cookies ngay lập tức
        print('📱 App lifecycle changed to $state - force saving all cookies');
        _globalCookieManager.forceSaveAllCookies().catchError((e) {
          print('❌ Lỗi khi force save cookies trong app lifecycle: $e');
        });
        break;
      case AppLifecycleState.resumed:
        // App được mở lại - load cookies
        print('📱 App resumed - loading global cookies');
        _globalCookieManager.loadGlobalCookies().catchError((e) {
          print('❌ Lỗi khi load global cookies trong app lifecycle: $e');
        });
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return const HomeScreen();
  }
}