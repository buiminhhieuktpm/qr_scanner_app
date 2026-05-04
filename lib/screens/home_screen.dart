import 'package:flutter/material.dart';
import 'history_screen.dart';
import 'webview_screen.dart';
import 'qr_scan_screen.dart';
import 'account_screen.dart';
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
  String _homeWebViewUrl = 'https://maqr.vn/#/app'; // URL động cho tab Trang chủ
  final GlobalKey<_DynamicWebViewState> _homeWebViewKey = GlobalKey();
  final GlobalKey<AccountScreenState> _accountWebViewKey = GlobalKey();
  DateTime? _lastTabSwitch; // Thời điểm chuyển tab gần nhất

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
    print('👆 Tab tapped: $index (current: $_selectedIndex)');
    
    // Debounce: Tránh conflict khi chuyển tab quá nhanh (trong vòng 200ms)
    final now = DateTime.now();
    if (_lastTabSwitch != null && now.difference(_lastTabSwitch!).inMilliseconds < 200) {
      print('⚠️ Chuyển tab quá nhanh, chờ một chút...');
      await Future.delayed(const Duration(milliseconds: 200));
    }
    _lastTabSwitch = now;
    
    // Chỉ reset URL khi đang ở tab Trang chủ và nhấn lại (double tap)
    if (index == 1 && _selectedIndex == 1) {
      print('🏠 Double tap Trang chủ - reset về URL mặc định');
      _homeWebViewKey.currentState?.loadUrl(_homeWebViewUrl, callApi: false);
      return; // Không cần chuyển tab vì đã ở tab Trang chủ
    }
    
    // Double tap Tài khoản → reload trang
    if (index == 3 && _selectedIndex == 3) {
      print('👤 Double tap Tài khoản - reload trang');
      _accountWebViewKey.currentState?.reload();
      return;
    }
    
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

      // Nếu đang chuyển TỚI tab tài khoản (index 3) từ tab khác,
      // force save cookies từ tab đang active rồi reload AccountScreen
      if (index == 3 && _selectedIndex != 3) {
        print('🍪 Chuyển sang tab Tài khoản - force save + sync + reload Account');
        await _globalCookieManager.forceSaveAllCookies();
        await _globalCookieManager.syncCookiesAcrossWebViews();
        setState(() { _selectedIndex = index; });
        Future.delayed(const Duration(milliseconds: 300), () {
          _accountWebViewKey.currentState?.syncAndReload();
        });
        return;
      }
      
      await _globalCookieManager.syncCookiesAcrossWebViews();
      print('✅ Hoàn thành đồng bộ cookies khi chuyển tab');
    } catch (e) {
      print('❌ Lỗi khi đồng bộ cookies: $e');
    }
    
    print('🔄 Setting _selectedIndex to $index');
    setState(() {
      _selectedIndex = index;
    });
    print('✅ Tab switched to $index');
  }

  // Xử lý khi quét QR thành công
  void _handleQRScanned(String url) {
    print('🔍 QR Scanned: $url');
    // Gọi API để lưu tên sản phẩm đúng
    _loadUrlInHomeTab(url, callApi: true);
  }

  // Xử lý khi click vào bản ghi lịch sử
  void _handleHistoryItemTap(String url) {
    print('📜 History item tapped: $url');
    _loadUrlInHomeTab(url, callApi: false);
  }

  // Hàm chung để load URL vào tab Trang chủ
  void _loadUrlInHomeTab(String url, {required bool callApi}) {
    // Cập nhật thời điểm chuyển tab
    _lastTabSwitch = DateTime.now();
    
    // Chuyển về tab Trang chủ TRƯỚC
    setState(() {
      _selectedIndex = 1;
    });
    
    // Sau đó mới load URL mới vào WebView
    // Delay nhỏ để đảm bảo tab đã chuyển xong
    Future.delayed(const Duration(milliseconds: 150), () {
      if (mounted) {
        _homeWebViewKey.currentState?.loadUrl(url, callApi: callApi);
      }
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
              onUrlTap: _handleHistoryItemTap,
            ),
            _DynamicWebView(
              key: _homeWebViewKey,
              initialUrl: _homeWebViewUrl,
            ),
            _QRScanWrapper(
              onScanned: _handleQRScanned,
              isActive: _selectedIndex == 2,
            ),
            AccountScreen(
              key: _accountWebViewKey,
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

// Wrapper cho QRScanScreen để xử lý callback
class _QRScanWrapper extends StatelessWidget {
  final Function(String) onScanned;
  final bool isActive;

  const _QRScanWrapper({required this.onScanned, required this.isActive});

  @override
  Widget build(BuildContext context) {
    return QRScanScreen(onScanned: onScanned, isActive: isActive);
  }
}

// DynamicWebView có thể thay đổi URL
class _DynamicWebView extends StatefulWidget {
  final String initialUrl;

  const _DynamicWebView({Key? key, required this.initialUrl}) : super(key: key);

  @override
  _DynamicWebViewState createState() => _DynamicWebViewState();
}

class _DynamicWebViewState extends State<_DynamicWebView> {
  late String currentUrl;
  bool shouldCallApi = false; // Chỉ call API khi load URL từ QR scan
  bool _isLoading = false;
  int _loadVersion = 0;

  @override
  void initState() {
    super.initState();
    currentUrl = widget.initialUrl;
  }

  void loadUrl(String url, {bool callApi = false}) {
    print('📱 _DynamicWebView.loadUrl: $url (callApi: $callApi)');
    if (mounted && !_isLoading) {
      _isLoading = true;
      setState(() {
        currentUrl = url;
        shouldCallApi = callApi;
        _loadVersion++;
      });
      // Reset flag sau khi load xong
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          _isLoading = false;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    print('📱 _DynamicWebView.build: currentUrl=$currentUrl, shouldCallApi=$shouldCallApi, loadVersion=$_loadVersion');
    return WebViewScreen(
      key: ValueKey('$currentUrl#$_loadVersion'),
      url: currentUrl,
      showAppBar: false,
      callApi: shouldCallApi,
    );
  }
}