import 'package:flutter/material.dart';
import 'history_screen.dart';
import 'webview_screen.dart';
import 'qr_scan_screen.dart';
import '../services/location_permission_manager.dart';
import '../services/global_cookie_manager.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int _selectedIndex = 1; // 0: History, 1: Home(WebView), 2: QR Scan, 3: Account
  final GlobalCookieManager _globalCookieManager = GlobalCookieManager();

  @override
  void initState() {
    super.initState();
    // Thêm observer để lắng nghe app lifecycle
    WidgetsBinding.instance.addObserver(this);
    _initializeApp();
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    if (state == AppLifecycleState.resumed) {
      print('📱 [HOME] App resumed - kiểm tra lại quyền vị trí');
      // Đồng bộ cookies trước
      _globalCookieManager.syncCookiesAcrossWebViews().catchError((e) {
        print('❌ Lỗi khi đồng bộ cookies: $e');
      });
      // Kiểm tra quyền vị trí
      _checkLocationPermissionOnStart();
    }
  }
  
  Future<void> _initializeApp() async {
    // Khởi tạo global cookies
    try {
      print('🌐 Khởi tạo global cookies...');
      await _globalCookieManager.loadGlobalCookies();
      await _globalCookieManager.debugGlobalCookies();
    } catch (e) {
      print('❌ Lỗi khi khởi tạo global cookies: $e');
    }
    
    // Kiểm tra quyền vị trí mỗi lần mở app
    print('🚀 [HOME] Ứng dụng đang khởi động - kiểm tra quyền vị trí...');
    await _checkLocationPermissionOnStart();
  }

  // Kiểm tra quyền vị trí mỗi lần mở app
  Future<void> _checkLocationPermissionOnStart() async {
    try {
      print('📍 [HOME] Kiểm tra quyền vị trí khi mở app...');
      
      // Lấy trạng thái chi tiết
      final status = await LocationPermissionManager.getLocationPermissionStatus();
      print('📍 [HOME] Chi tiết trạng thái: $status');
      
      final hasPermission = status['hasPermission'] ?? false;
      final isServicesDisabled = status['isServicesDisabled'] ?? false;
      final isNotDetermined = status['isNotDetermined'] ?? false;
      
      if (hasPermission) {
        print('✅ [HOME] Đã có quyền vị trí');
      } else if (isServicesDisabled) {
        print('⚠️ [HOME] Location Services bị tắt');
        // Hiển thị dialog nếu Location Services bị tắt
        if (mounted) {
          await LocationPermissionManager.showLocationServiceDisabledDialog(context);
        }
      } else if (isNotDetermined) {
        // Trạng thái "Ask Next Time" hoặc chưa quyết định → XIN QUYỀN TRỰC TIẾP (chỉ popup hệ thống)
        print('🔔 [HOME] Quyền chưa xác định (Ask Next Time) - xin quyền ngay...');
        final result = await LocationPermissionManager.requestPermissionSilently();
        print('📍 [HOME] Kết quả xin quyền: $result');
        
        if (result != null && result['hasPermission'] == true) {
          print('✅ [HOME] Đã được cấp quyền vị trí');
        } else {
          print('❌ [HOME] Không được cấp quyền vị trí');
        }
      } else {
        print('❌ [HOME] Không có quyền vị trí');
      }
    } catch (e) {
      print('❌ [HOME] Lỗi khi kiểm tra quyền vị trí: $e');
    }
  }

  @override
  void dispose() {
    // Remove lifecycle observer
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _onItemTapped(int index) async {
    // Đồng bộ cookies trước khi chuyển tab
    try {
      print('🔄 Đồng bộ cookies trước khi chuyển tab từ $_selectedIndex sang $index');
      
      // Nếu đang rời khỏi tab tài khoản (index 3), force save tất cả cookies
      if (_selectedIndex == 3) {
        print('🍪 Đang rời khỏi tab tài khoản - force save tất cả cookies');
        await _globalCookieManager.forceSaveAllCookies();
        // Thêm delay nhỏ để đảm bảo cookies được lưu hoàn toàn
        await Future.delayed(const Duration(milliseconds: 500));
      }
      
      await _globalCookieManager.syncCookiesAcrossWebViews();
      print('✅ Hoàn thành đồng bộ cookies khi chuyển tab');
    } catch (e) {
      print('❌ Lỗi khi đồng bộ cookies: $e');
    }
    
    setState(() {
      _selectedIndex = index;
    });
  }



  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: IndexedStack(
          index: _selectedIndex,
          children: [
            HistoryScreen(
              onUrlTap: (url) {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => WebViewScreen(url: url, showAppBar: true, callApi: false),
                  ),
                );
              },
            ),
            const WebViewScreen(
              key: ValueKey('https://maqr.vn/#/app'),
              url: 'https://maqr.vn/#/app',
              showAppBar: false,
            ),
            const QRScanScreen(),
            const WebViewScreen(
              key: ValueKey('https://maqr.vn/#/taikhoan'),
              url: 'https://maqr.vn/#/taikhoan',
              showAppBar: false,
            ),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.history),
            label: 'Lịch sử',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'Trang chủ',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.qr_code_scanner),
            label: 'Quét QR',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.account_circle),
            label: 'Tài khoản',
          ),
        ],
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: const Color(0xFF1565C0),
      ),
    );
  }
}