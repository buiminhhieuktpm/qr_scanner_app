import 'package:flutter/material.dart';
import 'screens/home_screen.dart';
import 'services/location_permission_manager.dart';
import 'services/global_cookie_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Khởi tạo location permission manager
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
  Map<String, dynamic>? get permissionResult => widget.permissionResult;
  final GlobalCookieManager _globalCookieManager = GlobalCookieManager();
  bool _hasHandledInitialPermission = false; // Flag để tránh xử lý lặp lại
  static bool _isHandlingPermission = false; // Static flag để tránh multiple instances

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    // Xử lý kết quả permission sau khi widget đã được khởi tạo với delay nhỏ
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Delay nhỏ để đảm bảo UI đã stable
      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted) {
        _handlePermissionResult();
      }
    });
  }

  /// Xử lý kết quả permission từ initialize()
  void _handlePermissionResult() async {
    // Kiểm tra static flag để tránh multiple instances xử lý cùng lúc
    if (_isHandlingPermission) {
      print('📱 [INIT] Đang xử lý permission ở instance khác, bỏ qua');
      return;
    }
    
    if (permissionResult != null && mounted && !_hasHandledInitialPermission) {
      _hasHandledInitialPermission = true;
      _isHandlingPermission = true;
      
      print('📱 [INIT] Xử lý kết quả permission lần đầu');
      print('📱 [INIT] Permission result: $permissionResult');
      
      try {
        await LocationPermissionManager.handleInitializationResult(
          context, 
          permissionResult
        );
      } finally {
        _isHandlingPermission = false;
      }
    } else if (_hasHandledInitialPermission) {
      print('📱 [INIT] Đã xử lý permission rồi, bỏ qua');
    } else if (_isHandlingPermission) {
      print('📱 [INIT] Đang xử lý permission, bỏ qua');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    LocationPermissionManager.dispose();
    _isHandlingPermission = false; // Reset static flag
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
        // App được mở lại - khởi tạo lại LocationPermissionManager và xử lý kết quả
        print('📱 App resumed - reinitializing services');
        _handleAppResumed();
        _globalCookieManager.loadGlobalCookies().catchError((e) {
          print('❌ Lỗi khi load global cookies trong app lifecycle: $e');
        });
        break;
    }
  }

  /// Xử lý khi app được mở lại
  void _handleAppResumed() async {
    try {
      print('📱 [RESUMED] App được mở lại - chỉ khởi tạo lại services');
      
      // Chỉ khởi tạo lại LocationPermissionManager để cập nhật timer
      // KHÔNG xử lý dialog ở đây để tránh lặp lại
      await LocationPermissionManager.initialize();
      
      print('📱 [RESUMED] Đã khởi tạo lại LocationPermissionManager');
    } catch (e) {
      print('❌ Lỗi khi xử lý app resumed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return const HomeScreen();
  }
}