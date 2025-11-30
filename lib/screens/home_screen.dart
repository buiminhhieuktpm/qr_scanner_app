import 'package:flutter/material.dart';
import 'package:qr_code_scanner/qr_code_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import 'history_screen.dart';
import 'webview_screen.dart';
import '../services/native_permission_service.dart';
import '../services/location_permission_manager.dart';
import '../services/global_cookie_manager.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final GlobalKey qrKey = GlobalKey(debugLabel: 'QR');
  QRViewController? controller;
  bool scanned = false;
  bool showScanner = false;
  String? scannedLink;
  int _selectedIndex = 1; // 0: History, 1: Home(WebView), 2: Account
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
    controller?.dispose();
    super.dispose();
  }

  // Thêm method kiểm tra và yêu cầu quyền camera
  Future<bool> _requestCameraPermission() async {
    try {
      print('=== CHECKING CAMERA PERMISSION ===');
      
      // Thử native method trước (hoạt động cho cả iOS và Android)
      final nativeStatus = await NativePermissionService.getCameraPermissionStatus();
      print('🎯 Native camera status: $nativeStatus');
      
      if (nativeStatus == 'authorized') {
        print('✅ Native camera permission already granted');
        return true;
      }
      
      if (nativeStatus == 'notDetermined') {
        print('🎯 Requesting native camera permission...');
        final granted = await NativePermissionService.requestCameraPermissionNative();
        print('🎯 Native permission result: $granted');
        if (granted) return true;
      }
      
      // Fallback to permission_handler
      print('=== FALLBACK TO PERMISSION_HANDLER ===');
      final currentStatus = await Permission.camera.status;
      print('📱 Permission handler status: $currentStatus');
      
      if (currentStatus.isGranted) {
        return true;
      }
      
      // Force request permission 
      print('📱 Force requesting permission...');
      final requestedStatus = await Permission.camera.request();
      print('📱 Permission result: $requestedStatus');
      
      if (requestedStatus.isGranted) {
        print('✅ Permission granted via permission_handler');
        return true;
      }
      
      // Show error dialog
      if (requestedStatus.isDenied || requestedStatus.isPermanentlyDenied) {
        print('❌ Camera permission denied');
        if (mounted) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Cần quyền Camera'),
              content: const Text('Quyền camera bị từ chối.\n\nCách cấp quyền:\n1. Vào Cài đặt iPhone\n2. Tìm app "QR Scanner App"\n3. Bật Camera\n\nHoặc vào: Cài đặt > Quyền riêng tư & Bảo mật > Camera'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Hủy'),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    openAppSettings();
                  },
                  child: const Text('Mở cài đặt'),
                ),
              ],
            ),
          );
        }
        return false;
      }
      
      return false;
    } catch (e) {
      print('❌ Lỗi khi request camera permission: $e');
      return false;
    }
  }

  void _openWebView(String url, {bool callApi = false}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WebViewScreen(url: url, showAppBar: true, callApi: callApi),
      ),
    );
  }

  void _onQRViewCreated(QRViewController controller) {
    this.controller = controller;
    controller.scannedDataStream.listen((scanData) async {
      if (!scanned) {
        scanned = true;
        await controller.pauseCamera();

        String? code = scanData.code;
        bool isUrl = code != null && (code.startsWith('http://') || code.startsWith('https://'));

        setState(() {
          scannedLink = isUrl ? code : null;
          showScanner = false;
        });

        if (isUrl) {
          _openWebView(code, callApi: true); // Quét QR thì callApi: true
        } else {
          showDialog(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('Đã quét!'),
              content: Text(code ?? 'Không có nội dung'),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    controller.resumeCamera();
                    scanned = false;
                  },
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        }
      }
    });
  }

  void _onItemTapped(int index) async {
    // Đồng bộ cookies trước khi chuyển tab
    try {
      print('🔄 Đồng bộ cookies trước khi chuyển tab từ $_selectedIndex sang $index');
      
      // Nếu đang rời khỏi tab tài khoản (index 2), force save tất cả cookies
      if (_selectedIndex == 2) {
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
      showScanner = false;
    });
  }

  Widget _buildHome() {
    if (showScanner) {
      return Column(
        children: [
          Expanded(
            flex: 4,
            child: QRView(
              key: qrKey,
              onQRViewCreated: _onQRViewCreated,
            ),
          ),
          Expanded(
            flex: 1,
            child: Column(
              children: [
                const Text('Đưa mã QR vào khung để quét'),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: () {
                    setState(() {
                      showScanner = false;
                      scanned = false;
                    });
                  },
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Quay lại'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF036337),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    } else {
      // Chỉ còn WebView, KHÔNG còn Stack và nút "Quét" nổi nữa
      return const WebViewScreen(
        key: ValueKey('https://maqr.vn/#/app'),
        url: 'https://maqr.vn/#/app',
        showAppBar: false,
      );
    }
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
                _openWebView(url, callApi: false);
              },
            ),
            _buildHome(),
            const WebViewScreen(
              key: ValueKey('https://maqr.vn/#/taikhoan'),
              url: 'https://maqr.vn/#/taikhoan',
              showAppBar: false,
            ),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        color: Colors.white,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [              if (_selectedIndex == 1 && !showScanner)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: Column(
                  children: [
                    ElevatedButton.icon(
                      onPressed: () async {
                        // Yêu cầu quyền trước khi mở scanner
                        final hasPermission = await _requestCameraPermission();
                        if (hasPermission) {
                          setState(() {
                            showScanner = true;
                            scanned = false;
                          });
                        }
                      },
                      label: const Text('Quét QRCode', style: TextStyle(color: Colors.white)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1565C0),
                        foregroundColor: Colors.white,
                        minimumSize: const Size(160, 48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 0,
                        shadowColor: Colors.transparent,
                      ),
                    ),
                  ],
                ),
              ),
            BottomNavigationBar(
              items: const [
                BottomNavigationBarItem(
                  icon: Icon(Icons.history),
                  label: 'Lịch sử',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.qr_code_scanner),
                  label: 'Quét QrCode',
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
          ],
        ),
      ),
    );
  }
}