import 'package:flutter/material.dart';
import 'screens/home_screen.dart';
import 'services/location_permission_manager.dart';
import 'services/global_cookie_manager.dart';

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
    
    // Xử lý kết quả permission (chỉ log, không cần dialog phức tạp)
    if (widget.permissionResult != null) {
      _handlePermissionResult();
    }
  }

  /// Xử lý kết quả permission đơn giản
  void _handlePermissionResult() {
    final result = widget.permissionResult!;
    final hasPermission = result['hasPermission'] ?? false;
    final status = result['status'] ?? 'unknown';
    
    print('📱 [INIT] Kết quả permission: $result');
    
    if (hasPermission) {
      print('📱 [INIT] ✅ Đã có quyền vị trí');
    } else {
      print('📱 [INIT] ❌ Không có quyền vị trí - Status: $status');
    }
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