import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/history_service.dart';
import '../services/location_permission_manager.dart';
import '../services/global_cookie_manager.dart';
import '../models/scan_history.dart';

class WebViewScreen extends StatefulWidget {
  final String url;
  final bool showAppBar;
  final bool callApi; // Thêm biến này
  const WebViewScreen({
    Key? key,
    required this.url,
    this.showAppBar = false,
    this.callApi = false, // Mặc định không gọi API
  }) : super(key: key);

  @override
  _WebViewScreenState createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> with WidgetsBindingObserver {
  InAppWebViewController? webViewController;
  PullToRefreshController? _pullToRefreshController;
  Timer? _locationTimer;
  Timer? _cookieSaveTimer;
  bool _isCheckingLocation = false; // Cờ để tránh check location đồng thời
  bool _isInjectingLocation = false; // Cờ để tránh inject location đồng thời
  final GlobalCookieManager _globalCookieManager = GlobalCookieManager();
  double _loadingProgress = 0; // Thêm biến theo dõi progress
  bool _isPageLoaded = false; // Thêm biến theo dõi page đã load xong chưa

  @override
  void initState() {
    super.initState();
    
    // Thêm observer để lắng nghe app lifecycle
    WidgetsBinding.instance.addObserver(this);

    // Khởi tạo PullToRefreshController
    _pullToRefreshController = PullToRefreshController(
      settings: PullToRefreshSettings(
        color: const Color(0xFF1565C0),
      ),
      onRefresh: () async {
        print('🔄 Pull-to-refresh: đang reload trang...');
        if (webViewController != null) {
          await webViewController!.reload();
        } else {
          // Nếu chưa có controller, dừng refresh indicator
          _pullToRefreshController?.endRefreshing();
        }
      },
    );
    
    // Load global cookies trước khi khởi tạo WebView
    _initializeGlobalCookies();
    
    // Bắt đầu timer lưu cookies định kỳ
    _startPeriodicCookieSaving();
    
    // Kiểm tra quyền vị trí với LocationPermissionManager (không cần delay)
    _checkLocationPermission();
    
    final uri = Uri.parse(widget.url);
    String qrcode = '';
    if (uri.fragment.isNotEmpty) {
      qrcode = uri.fragment.split('/').last;
    } else {
      qrcode = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : '';
    }
    
    print('WebViewScreen initState - URL: ${widget.url}');
    print('WebViewScreen initState - QR code extracted: $qrcode');
    print('WebViewScreen initState - callApi: ${widget.callApi}');
    
    // Chỉ call API khi mở link từ quét QR (callApi == true)
    if (qrcode.isNotEmpty && widget.callApi) {
      print('Bắt đầu gọi API cho QR code: $qrcode');
      // Thêm delay nhỏ để đảm bảo widget đã được khởi tạo hoàn toàn
      Future.delayed(const Duration(milliseconds: 1500), () {
        fetchQrcodeInfo(qrcode);
      });
    }
  }

  // Bắt đầu lưu cookies định kỳ mỗi 30 giây
  void _startPeriodicCookieSaving() {
    _cookieSaveTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      _saveCurrentCookies();
    });
  }

  // Lưu cookies hiện tại
  Future<void> _saveCurrentCookies() async {
    if (webViewController != null) {
      try {
        final uri = Uri.parse(widget.url);
        print('🍪 Lưu cookies định kỳ cho ${uri.host}...');
        await saveCookies(uri);
        
        // Đồng bộ global cookies nếu là maqr.vn
        if (uri.host.contains('maqr.vn')) {
          await _globalCookieManager.saveGlobalCookies();
        }
      } catch (e) {
        print('❌ Lỗi khi lưu cookies định kỳ: $e');
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    switch (state) {
      case AppLifecycleState.paused:
        print('📱 App đã bị tạm dừng - lưu cookies ngay lập tức');
        _saveCurrentCookies();
        // Dừng location tracking khi app pause
        _locationTimer?.cancel();
        break;
      case AppLifecycleState.inactive:
        print('📱 App không hoạt động - lưu cookies ngay lập tức');
        _saveCurrentCookies();
        break;
      case AppLifecycleState.detached:
        print('📱 App đã bị detached - lưu cookies cuối cùng');
        _saveCurrentCookies();
        _locationTimer?.cancel();
        break;
      case AppLifecycleState.resumed:
        print('📱 App đã được resume - load cookies và kiểm tra lại quyền vị trí');
        _loadCurrentCookies();
        // Kiểm tra lại quyền vị trí khi app resume
        _checkLocationPermission();
        break;
      case AppLifecycleState.hidden:
        print('📱 App đã bị ẩn - lưu cookies');
        _saveCurrentCookies();
        break;
    }
  }

  // Load cookies khi app resume
  Future<void> _loadCurrentCookies() async {
    if (webViewController != null) {
      try {
        final uri = Uri.parse(widget.url);
        print('🍪 Load cookies khi app resume...');
        await loadCookies(uri);
        await _globalCookieManager.loadGlobalCookies();
      } catch (e) {
        print('❌ Lỗi khi load cookies: $e');
      }
    }
  }

  // Kiểm tra quyền vị trí và bắt đầu tracking nếu có quyền
  Future<void> _checkLocationPermission() async {
    try {
      print('🔍 [WEBVIEW] Kiểm tra quyền vị trí...');
      
      // Lấy trạng thái chi tiết
      final status = await LocationPermissionManager.getLocationPermissionStatus();
      final hasPermission = status['hasPermission'] ?? false;
      final isServicesDisabled = status['isServicesDisabled'] ?? false;
      
      print('🔍 [WEBVIEW] Chi tiết trạng thái: $status');
      
      if (hasPermission) {
        print('✅ [WEBVIEW] Đã có quyền vị trí, bắt đầu tracking');
        _startLocationTracking();
      } else if (isServicesDisabled) {
        print('⚠️ [WEBVIEW] Location Services bị tắt');
        // Hiển thị dialog một lần
        if (mounted) {
          await LocationPermissionManager.showLocationServiceDisabledDialog(context);
        }
      } else {
        print('❌ [WEBVIEW] Không có quyền vị trí');
      }
    } catch (e) {
      print('💥 [WEBVIEW] Lỗi khi kiểm tra quyền vị trí: $e');
    }
  }

  // Method để bypass SSL và gọi API
  Future<http.Response?> _makeApiRequest(String url) async {
    try {
      // Thử với HTTP client thường trước
      final normalResponse = await http.get(
        Uri.parse(url),
        headers: {
          'Accept': 'application/json',
          'User-Agent': 'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Mobile Safari/537.36',
          'Connection': 'keep-alive',
          'Cache-Control': 'no-cache',
        },
      ).timeout(const Duration(seconds: 15));
      
      return normalResponse;
    } catch (e) {
      print('Normal HTTP client failed: $e');
      
      try {
        // Thử với IOClient và bypass SSL
        final httpClient = HttpClient();
        httpClient.badCertificateCallback = (cert, host, port) => true;
        final ioClient = IOClient(httpClient);
        
        final response = await ioClient.get(
          Uri.parse(url),
          headers: {
            'Accept': 'application/json',
            'User-Agent': 'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Mobile Safari/537.36',
            'Connection': 'keep-alive',
            'Cache-Control': 'no-cache',
          },
        ).timeout(const Duration(seconds: 15));
        
        ioClient.close();
        return response;
      } catch (e2) {
        print('IOClient with SSL bypass also failed: $e2');
        return null;
      }
    }
  }

  Future<void> saveCookies(Uri url) async {
    try {
      print('💾 Bắt đầu lưu cookies cho URL: $url');
      final cookieManager = CookieManager.instance();
      final cookies = await cookieManager.getCookies(url: WebUri(url.toString()));
      
      if (cookies.isEmpty) {
        print('⚠️ Không có cookies để lưu');
        return;
      }
      
      final prefs = await SharedPreferences.getInstance();
      
      // Lưu cookies với domain-specific key để tránh conflict
      final domain = url.host;
      final cookieKey = 'cookies_$domain';
      
      // Tạo cookie string với thông tin đầy đủ hơn
      final cookieList = <Map<String, dynamic>>[];
      for (var cookie in cookies) {
        cookieList.add({
          'name': cookie.name,
          'value': cookie.value,
          'domain': cookie.domain ?? domain,
          'path': cookie.path ?? '/',
          'secure': cookie.isSecure ?? false,
          'httpOnly': cookie.isHttpOnly ?? false,
          'sameSite': cookie.sameSite?.toString() ?? 'Lax',
          'expiresDate': cookie.expiresDate,
        });
      }
      
      final cookieJson = jsonEncode(cookieList);
      await prefs.setString(cookieKey, cookieJson);
      
      // 🌐 Lưu vào global storage nếu là domain maqr.vn
      if (domain.contains('maqr.vn')) {
        print('🌐 Lưu cookies vào global storage cho maqr.vn...');
        await _globalCookieManager.saveGlobalCookies();
      }
      
      print('✅ Đã lưu ${cookies.length} cookies cho domain: $domain');
    } catch (e) {
      print('❌ Lỗi khi lưu cookies: $e');
    }
  }

  Future<void> loadCookies(Uri url) async {
    try {
      print('📥 Bắt đầu load cookies cho URL: $url');
      final domain = url.host;
      
      // 🌐 Load từ global storage trước nếu là domain maqr.vn
      if (domain.contains('maqr.vn')) {
        print('🌐 Load cookies từ global storage cho maqr.vn...');
        await _globalCookieManager.loadGlobalCookies();
      }
      
      final prefs = await SharedPreferences.getInstance();
      final cookieKey = 'cookies_$domain';
      
      final cookieJson = prefs.getString(cookieKey);
      if (cookieJson == null || cookieJson.isEmpty) {
        print('⚠️ Không tìm thấy cookies cho domain: $domain');
        return;
      }
      
      final cookieManager = CookieManager.instance();
      final cookieList = jsonDecode(cookieJson) as List<dynamic>;
      
      int loadedCount = 0;
      for (var cookieData in cookieList) {
        try {
          final cookieMap = cookieData as Map<String, dynamic>;
          
          // Kiểm tra xem cookie có còn hạn không
          final expiresDate = cookieMap['expiresDate'] != null 
              ? DateTime.fromMillisecondsSinceEpoch(cookieMap['expiresDate'])
              : null;
          
          if (expiresDate != null && expiresDate.isBefore(DateTime.now())) {
            print('⏰ Cookie ${cookieMap['name']} đã hết hạn, bỏ qua');
            continue;
          }
          
          await cookieManager.setCookie(
            url: WebUri(url.toString()),
            name: cookieMap['name'] ?? '',
            value: cookieMap['value'] ?? '',
            domain: cookieMap['domain'] ?? domain,
            path: cookieMap['path'] ?? '/',
            isSecure: cookieMap['secure'] ?? false,
            isHttpOnly: cookieMap['httpOnly'] ?? false,
            sameSite: _parseSameSite(cookieMap['sameSite']),
            expiresDate: expiresDate?.millisecondsSinceEpoch,
          );
          
          loadedCount++;
        } catch (e) {
          print('❌ Lỗi khi load cookie individual: $e');
        }
      }
      
      print('✅ Đã load $loadedCount cookies cho domain: $domain');
    } catch (e) {
      print('❌ Lỗi khi load cookies: $e');
    }
  }

  HTTPCookieSameSitePolicy? _parseSameSite(String? sameSite) {
    if (sameSite == null) return HTTPCookieSameSitePolicy.LAX;
    
    switch (sameSite.toLowerCase()) {
      case 'strict':
        return HTTPCookieSameSitePolicy.STRICT;
      case 'none':
        return HTTPCookieSameSitePolicy.NONE;
      case 'lax':
      default:
        return HTTPCookieSameSitePolicy.LAX;
    }
  }

  // Method để clear cookies khi cần
  Future<void> clearCookies(Uri url) async {
    try {
      print('🗑️ Clearing cookies cho URL: $url');
      final cookieManager = CookieManager.instance();
      await cookieManager.deleteCookies(url: WebUri(url.toString()));
      
      final prefs = await SharedPreferences.getInstance();
      final domain = url.host;
      final cookieKey = 'cookies_$domain';
      await prefs.remove(cookieKey);
      
      print('✅ Đã clear cookies cho domain: $domain');
    } catch (e) {
      print('❌ Lỗi khi clear cookies: $e');
    }
  }

  Future<String> generateQrBase64(String data) async {
    try {
      print('generateQrBase64: Bắt đầu tạo QR cho data: $data');
      
      final qrValidationResult = QrValidator.validate(
        data: data,
        version: QrVersions.auto,
        errorCorrectionLevel: QrErrorCorrectLevel.L,
      );
      
      print('generateQrBase64: Validation status: ${qrValidationResult.status}');
      
      if (qrValidationResult.status == QrValidationStatus.valid) {
        final qrCode = qrValidationResult.qrCode!;
        print('generateQrBase64: QR code created successfully');
        
        final painter = QrPainter.withQr(
          qr: qrCode,
          color: const Color(0xFF000000),
          emptyColor: const Color(0xFFFFFFFF),
          gapless: true,
        );
        
        print('generateQrBase64: QrPainter created');
        
        final picData = await painter.toImageData(300);
        if (picData != null) {
          final bytes = picData.buffer.asUint8List();
          final base64String = base64Encode(bytes);
          print('generateQrBase64: Base64 generated, length: ${base64String.length}');
          return base64String;
        } else {
          print('generateQrBase64: picData is null');
        }
      } else {
        print('generateQrBase64: Validation failed: ${qrValidationResult.status}');
      }
    } catch (e, stackTrace) {
      print('generateQrBase64: Error: $e');
      print('generateQrBase64: Stack trace: $stackTrace');
    }
    return '';
  }

  Future<void> fetchQrcodeInfo(String qrcode) async {
    // Ưu tiên HTTPS với URL chính xác mà bạn cung cấp
    final urls = [
      'https://maqr.vn/api5/vnptcheck_apiv1/qrcode/thongtinsanpham/$qrcode',
      'http://maqr.vn/api5/vnptcheck_apiv1/qrcode/thongtinsanpham/$qrcode',
    ];
    
    for (String apiUrl in urls) {
      print('Gọi API: $apiUrl');
      
      try {
        final response = await _makeApiRequest(apiUrl);
        
        if (response == null) {
          print('Không thể kết nối API: $apiUrl');
          continue;
        }
        
        print('Response status: ${response.statusCode}');
        
        if (response.statusCode == 200) {
          print('Response body: ${response.body}');
          try {
            final data = jsonDecode(response.body);
            print('Data parsed từ API: $data');

            // Tạo ảnh QR code base64
            final qrBase64 = await generateQrBase64(qrcode);
            print('QR Base64 generated: ${qrBase64.isNotEmpty ? "Success" : "Failed"}');

            // Lấy tên sản phẩm - thử nhiều path khác nhau
            String productName = 'Không có tên sản phẩm';
            
            // Thử các path khác nhau để lấy tên sản phẩm
            if (data['data']?['sanpham']?['data']?['ten_sanpham'] != null) {
              productName = data['data']['sanpham']['data']['ten_sanpham'];
            } else if (data['data']?['ten_sanpham'] != null) {
              productName = data['data']['ten_sanpham'];
            } else if (data['ten_sanpham'] != null) {
              productName = data['ten_sanpham'];
            } else if (data['sanpham']?['ten_sanpham'] != null) {
              productName = data['sanpham']['ten_sanpham'];
            } else if (data['product_name'] != null) {
              productName = data['product_name'];
            } else if (data['name'] != null) {
              productName = data['name'];
            }

            print('Product name extracted: $productName');

            // Lưu vào lịch sử
            final scanHistory = ScanHistory(
              productName: productName,
              qrImage: qrBase64,
              url: widget.url,
              scannedAt: DateTime.now(),
            );

            final historyService = HistoryService();
            await historyService.saveScan(scanHistory);
            print('Đã lưu scan history');

            return; // Thành công, thoát khỏi vòng lặp
            
          } catch (e) {
            print('Lỗi khi parse JSON: $e');
            continue; // Thử URL tiếp theo
          }
        } else {
          print('API trả về lỗi ${response.statusCode}: ${response.body}');
          continue; // Thử URL tiếp theo
        }
      } catch (e) {
        print('Lỗi khi gọi API $apiUrl: $e');
        continue; // Thử URL tiếp theo
      }
    }

    // Nếu tất cả URLs đều fail, vẫn lưu với tên mặc định
    print('Tất cả API URLs đều fail, lưu với tên mặc định');
    final qrBase64 = await generateQrBase64(qrcode);
    final scanHistory = ScanHistory(
      productName: 'Không thể lấy thông tin sản phẩm',
      qrImage: qrBase64,
      url: widget.url,
      scannedAt: DateTime.now(),
    );

    final historyService = HistoryService();
    await historyService.saveScan(scanHistory);
    print('Đã lưu scan history với thông tin mặc định');
  }

  void _startLocationTracking() {
    print('🌍 Bắt đầu location tracking...');
    
    // Hủy timer cũ nếu có
    _locationTimer?.cancel();
    
    // Tạo timer mới, gửi location mỗi 10 giây
    _locationTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      _checkCurrentLocation();
    });
    
    // Gửi location ngay lập tức
    _checkCurrentLocation();
  }
  
  void _stopLocationTracking() {
    print('🛑 Dừng location tracking');
    _locationTimer?.cancel();
    _locationTimer = null;
  }

  void _checkCurrentLocation() async {
    if (_isCheckingLocation || _isInjectingLocation) {
      print('⏳ Đang xử lý location, bỏ qua lần này');
      return;
    }
    
    _isCheckingLocation = true;
    
    try {
      print('📍 Đang lấy vị trí hiện tại...');
      
      // Kiểm tra dịch vụ vị trí có được bật không (kiểm tra trước)
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        print('⚠️ Dịch vụ vị trí bị tắt, không thể lấy vị trí');
        
        // Hiển thị dialog một lần duy nhất nếu chưa hiển thị
        if (mounted) {
          await LocationPermissionManager.showLocationServiceDisabledDialog(context);
        }
        
        // Dừng tracking tạm thời, sẽ được bật lại khi app resume
        _stopLocationTracking();
        return;
      }
      
      // Kiểm tra lại quyền trước khi lấy vị trí
      bool hasPermission = await LocationPermissionManager.hasLocationPermission();
      if (!hasPermission) {
        print('❌ Không có quyền vị trí');
        
        // Kiểm tra chi tiết để biết lý do
        final status = await LocationPermissionManager.getLocationPermissionStatus();
        print('📍 Chi tiết trạng thái: $status');
        
        // Dừng tracking tạm thời
        _stopLocationTracking();
        return;
      }
      
      // Lấy vị trí hiện tại
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
      
      print('📍 Vị trí hiện tại: ${position.latitude}, ${position.longitude}');
      
      // Inject vị trí vào JavaScript với debounce và wrap trong setTimeout
      if (webViewController != null && !_isInjectingLocation) {
        _isInjectingLocation = true;
        try {
          await webViewController!.evaluateJavascript(source: '''
            (function() {
              try {
                // Chỉ inject nếu chưa có hoặc timestamp mới hơn
                if (!window.locationData || 
                    !window.locationData.timestamp ||
                    window.locationData.timestamp < ${position.timestamp.millisecondsSinceEpoch}) {
                  
                  window.locationData = {
                    latitude: ${position.latitude},
                    longitude: ${position.longitude},
                    accuracy: ${position.accuracy},
                    timestamp: ${position.timestamp.millisecondsSinceEpoch}
                  };
                  
                  console.log('Location injected:', window.locationData);
                  
                  // Wrap events trong setTimeout để tránh AngularJS digest conflicts
                  setTimeout(function() {
                    try {
                      if (typeof window.onLocationUpdate === 'function') {
                        window.onLocationUpdate(window.locationData);
                      }
                      
                      window.dispatchEvent(new CustomEvent('locationupdate', { 
                        detail: window.locationData 
                      }));
                    } catch (e) {
                      console.error('Error triggering location events:', e);
                    }
                  }, 100);
                }
              } catch (e) {
                console.error('Error injecting location:', e);
              }
            })();
          ''');
          
          print('✅ Đã inject vị trí vào WebView');
        } finally {
          // Delay reset flag để tránh inject quá nhanh
          await Future.delayed(const Duration(milliseconds: 300));
          _isInjectingLocation = false;
        }
      }
      
    } catch (e) {
      print('❌ Lỗi khi lấy vị trí: $e');
    } finally {
      _isCheckingLocation = false;
    }
  }

  // Lưu localStorage của trang hiện tại vào SharedPreferences để chia sẻ với AccountScreen
  Future<void> _saveLocalStorage(InAppWebViewController controller) async {
    try {
      final result = await controller.evaluateJavascript(source: '''
        (function() {
          try {
            var items = {};
            for (var i = 0; i < localStorage.length; i++) {
              var key = localStorage.key(i);
              items[key] = localStorage.getItem(key);
            }
            return JSON.stringify(items);
          } catch(e) { return null; }
        })();
      ''');
      if (result != null && result.toString() != 'null' && result.toString().length > 2) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('maqr_local_storage', result.toString());
        print('💾 [WEBVIEW] Đã lưu localStorage (${result.toString().length} chars)');
      }
    } catch (e) {
      print('❌ [WEBVIEW] Lỗi lưu localStorage: $e');
    }
  }

  Future<void> _injectLogoutDetectorJS(InAppWebViewController controller) async {
    try {
      await controller.evaluateJavascript(source: '''
        (function() {
          if (window.__logoutDetectorInjected) return;
          window.__logoutDetectorInjected = true;

          function attachLogoutListener() {
            var btns = document.querySelectorAll('a[ng-click="cl_dangxuat()"]');
            btns.forEach(function(btn) {
              if (!btn.__logoutListenerAttached) {
                btn.__logoutListenerAttached = true;
                btn.addEventListener('click', function() {
                  console.log('[LOGOUT] Nut dang xuat duoc nhan');
                  if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
                    window.flutter_inappwebview.callHandler('onLogout');
                  }
                }, true);
                console.log('[LOGOUT] Da gan listener vao nut dang xuat');
              }
            });
          }

          attachLogoutListener();

          var observer = new MutationObserver(function() {
            attachLogoutListener();
          });
          observer.observe(document.body || document.documentElement, {
            childList: true,
            subtree: true
          });

          console.log('[LOGOUT] Logout detector injected');
        })();
      ''');
      print('✅ [WEBVIEW] Đã inject logout detector JS');
    } catch (e) {
      print('❌ [WEBVIEW] Lỗi inject logout detector JS: \$e');
    }
  }

  Future<void> _injectLocationHelpers() async {
    if (webViewController == null) return;
    
    try {
      await webViewController!.evaluateJavascript(source: '''
        (function() {
          // Override geolocation API
          if (navigator.geolocation) {
            const originalGetCurrentPosition = navigator.geolocation.getCurrentPosition;
            const originalWatchPosition = navigator.geolocation.watchPosition;
            
            navigator.geolocation.getCurrentPosition = function(success, error, options) {
              console.log('geolocation.getCurrentPosition called');
              
              if (window.locationData) {
                console.log('Using injected location data:', window.locationData);
                if (success) {
                  success({
                    coords: {
                      latitude: window.locationData.latitude,
                      longitude: window.locationData.longitude,
                      accuracy: window.locationData.accuracy || 10,
                      altitude: null,
                      altitudeAccuracy: null,
                      heading: null,
                      speed: null
                    },
                    timestamp: window.locationData.timestamp || Date.now()
                  });
                }
                return;
              }
              
              // Fallback to original method
              console.log('Fallback to original getCurrentPosition');
              originalGetCurrentPosition.call(this, success, error, options);
            };
            
            navigator.geolocation.watchPosition = function(success, error, options) {
              console.log('geolocation.watchPosition called');
              
              // Gọi getCurrentPosition một lần
              navigator.geolocation.getCurrentPosition(success, error, options);
              
              // Return dummy watch ID
              return Math.floor(Math.random() * 10000);
            };
            
            console.log('Geolocation API overridden successfully');
          }
          
          // Helper function để website có thể dùng
          window.requestCurrentLocation = function() {
            return new Promise((resolve, reject) => {
              if (window.locationData) {
                resolve(window.locationData);
              } else {
                reject(new Error('Location not available'));
              }
            });
          };
          
          // Thêm listener để tự động lưu cookies khi có thay đổi trong DOM
          let cookieSaveTimeout;
          function scheduleCookieSave() {
            if (cookieSaveTimeout) {
              clearTimeout(cookieSaveTimeout);
            }
            cookieSaveTimeout = setTimeout(function() {
              console.log('🍪 DOM changed - requesting cookie save');
              // Gửi message để Flutter biết cần lưu cookies
              if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
                window.flutter_inappwebview.callHandler('saveCookiesFromJS');
              }
            }, 2000); // Delay 2 giây để tránh save quá nhiều
          }
          
          // Listen for DOM changes that might indicate login/logout
          if (document.body) {
            const observer = new MutationObserver(function(mutations) {
              mutations.forEach(function(mutation) {
                // Kiểm tra các thay đổi có thể liên quan đến login/logout
                if (mutation.type === 'childList' || mutation.type === 'characterData') {
                  const text = document.body.innerText.toLowerCase();
                  if (text.includes('đăng nhập') || text.includes('đăng xuất') || 
                      text.includes('login') || text.includes('logout') ||
                      text.includes('tài khoản') || text.includes('account')) {
                    console.log('🍪 Login/logout related change detected');
                    scheduleCookieSave();
                  }
                }
              });
            });
            
            observer.observe(document.body, {
              childList: true,
              subtree: true,
              characterData: true
            });
            
            console.log('🍪 DOM mutation observer setup complete');
          }
          
          // Listen for storage events (localStorage, sessionStorage changes)
          window.addEventListener('storage', function(e) {
            console.log('🍪 Storage event detected:', e.key);
            scheduleCookieSave();
          });
          
          // Listen for cookie changes via document.cookie
          let lastCookies = document.cookie;
          setInterval(function() {
            if (document.cookie !== lastCookies) {
              console.log('🍪 Cookie change detected via polling');
              lastCookies = document.cookie;
              scheduleCookieSave();
            }
          }, 5000); // Check every 5 seconds
          
          console.log('Location helpers and cookie monitoring injected successfully');
        })();
      ''');
      
      print('✅ Đã inject location helpers và cookie monitoring vào WebView');
    } catch (e) {
      print('❌ Lỗi khi inject location helpers và cookie monitoring: $e');
    }
  }

  Future<bool> _handleSpecialScheme(String url) async {
    final uri = Uri.parse(url);
    
    try {
      switch (uri.scheme.toLowerCase()) {
        case 'tel':
          print('Đang gọi điện: $url');
          return await launchUrl(uri);
          
        case 'sms':
          print('Đang gửi SMS: $url');
          return await launchUrl(uri);
          
        case 'mailto':
          print('Đang mở email: $url');
          return await launchUrl(uri);
          
        case 'whatsapp':
          print('Đang mở WhatsApp: $url');
          return await launchUrl(uri, mode: LaunchMode.externalApplication);
          
        case 'zalo':
          print('Đang mở Zalo: $url');
          return await launchUrl(uri, mode: LaunchMode.externalApplication);
          
        case 'viber':
          print('Đang mở Viber: $url');
          return await launchUrl(uri, mode: LaunchMode.externalApplication);
          
        case 'fb':
        case 'facebook':
          print('Đang mở Facebook: $url');
          return await launchUrl(uri, mode: LaunchMode.externalApplication);
          
        case 'intent':
          print('Đang xử lý Android intent: $url');
          // Trích xuất URL fallback từ intent nếu có
          if (url.contains('S.browser_fallback_url=')) {
            final fallbackMatch = RegExp(r'S\.browser_fallback_url=([^;]+)').firstMatch(url);
            if (fallbackMatch != null) {
              final fallbackUrl = Uri.decodeComponent(fallbackMatch.group(1)!);
              print('Sử dụng fallback URL: $fallbackUrl');
              if (webViewController != null) {
                await webViewController!.loadUrl(urlRequest: URLRequest(url: WebUri(fallbackUrl)));
                return true;
              }
            }
          }
          return false;
          
        case 'market':
        case 'play':
          print('Đang mở Google Play Store: $url');
          return await launchUrl(uri, mode: LaunchMode.externalApplication);
          
        default:
          // Cho các scheme khác, thử mở bằng ứng dụng external
          if (uri.scheme != 'http' && uri.scheme != 'https' && uri.scheme != 'file' && uri.scheme != 'data') {
            print('Đang thử mở scheme không hỗ trợ với ứng dụng external: ${uri.scheme}');
            return await launchUrl(uri, mode: LaunchMode.externalApplication);
          }
          return false;
      }
    } catch (e) {
      print('Lỗi khi xử lý scheme $url: $e');
      return false;
    }
  }

  // Method để đồng bộ cookies định kỳ (gọi mỗi khi page load)
  Future<void> syncCookies(Uri url) async {
    try {
      print('🔄 Bắt đầu đồng bộ cookies cho URL: $url');
      
      // Lưu cookies hiện tại từ WebView
      await saveCookies(url);
      
      // 🌐 Đồng bộ cookies across WebViews nếu là maqr.vn
      if (url.host.contains('maqr.vn')) {
        print('🌐 Đồng bộ cookies across WebViews...');
        await _globalCookieManager.syncCookiesAcrossWebViews();
      }
      
      // Load lại cookies để đảm bảo đồng bộ
      await loadCookies(url);
      
      print('✅ Hoàn thành đồng bộ cookies');
    } catch (e) {
      print('❌ Lỗi khi đồng bộ cookies: $e');
    }
  }

  // Method để kiểm tra trạng thái cookies
  Future<void> debugCookies(Uri url) async {
    try {
      final cookieManager = CookieManager.instance();
      final cookies = await cookieManager.getCookies(url: WebUri(url.toString()));
      
      print('🍪 Debug Cookies cho ${url.host}:');
      print('   - Số lượng cookies: ${cookies.length}');
      
      for (var cookie in cookies) {
        print('   - ${cookie.name}: ${cookie.value.length > 50 ? '${cookie.value.substring(0, 50)}...' : cookie.value}');
        print('     Domain: ${cookie.domain}, Path: ${cookie.path}');
        print('     Secure: ${cookie.isSecure}, HttpOnly: ${cookie.isHttpOnly}');
        print('     Expires: ${cookie.expiresDate != null ? DateTime.fromMillisecondsSinceEpoch(cookie.expiresDate!) : 'Session'}');
      }
    } catch (e) {
      print('❌ Lỗi khi debug cookies: $e');
    }
  }

  // Method để xử lý các vấn đề cookie thường gặp
  Future<void> handleCookieIssues(Uri url) async {
    try {
      print('🔧 Kiểm tra và xử lý vấn đề cookies...');
      
      final cookieManager = CookieManager.instance();
      
      // 1. Kiểm tra cookie có được lưu không
      final cookies = await cookieManager.getCookies(url: WebUri(url.toString()));
      if (cookies.isEmpty) {
        print('⚠️ Không có cookies, có thể do:');
        print('   - Website chưa set cookies');
        print('   - Cookies bị block bởi SameSite policy');
        print('   - Quyền storage bị deny');
        
        // Thử clear cache và reload
        await cookieManager.deleteAllCookies();
        print('🗑️ Đã clear tất cả cookies và thử lại');
      }
      
      // 2. Kiểm tra third-party cookies
      final domain = url.host;
      final hasThirdPartyCookies = cookies.any((cookie) => 
        cookie.domain != null && !cookie.domain!.contains(domain));
      
      if (hasThirdPartyCookies) {
        print('🍪 Phát hiện third-party cookies - đảm bảo thirdPartyCookiesEnabled = true');
      }
      
      // 3. Kiểm tra secure cookies trên HTTP
      final isHttps = url.scheme == 'https';
      final hasSecureCookies = cookies.any((cookie) => cookie.isSecure == true);
      
      if (!isHttps && hasSecureCookies) {
        print('⚠️ Cảnh báo: Có secure cookies nhưng đang dùng HTTP');
        print('   - Secure cookies sẽ không được gửi qua HTTP');
        print('   - Khuyến nghị chuyển sang HTTPS');
      }
      
      // 4. Kiểm tra cookies hết hạn
      final now = DateTime.now();
      final expiredCookies = cookies.where((cookie) => 
        cookie.expiresDate != null && 
        DateTime.fromMillisecondsSinceEpoch(cookie.expiresDate!).isBefore(now)
      ).length;
      
      if (expiredCookies > 0) {
        print('⏰ Có $expiredCookies cookies đã hết hạn');
        
        // Clear expired cookies
        for (var cookie in cookies) {
          if (cookie.expiresDate != null && 
              DateTime.fromMillisecondsSinceEpoch(cookie.expiresDate!).isBefore(now)) {
            await cookieManager.deleteCookie(
              url: WebUri(url.toString()),
              name: cookie.name,
            );
          }
        }
        print('🗑️ Đã xóa cookies hết hạn');
      }
      
    } catch (e) {
      print('❌ Lỗi khi xử lý vấn đề cookies: $e');
    }
  }

  // Method để test cookie functionality
  Future<void> testCookieFunctionality(Uri url) async {
    try {
      print('🧪 Test cookie functionality...');
      
      final cookieManager = CookieManager.instance();
      const testCookieName = 'qr_scanner_test_cookie';
      final testCookieValue = 'test_value_${DateTime.now().millisecondsSinceEpoch}';
      
      // Set test cookie
      await cookieManager.setCookie(
        url: WebUri(url.toString()),
        name: testCookieName,
        value: testCookieValue,
        domain: url.host,
        path: '/',
      );
      
      // Verify test cookie
      final cookies = await cookieManager.getCookies(url: WebUri(url.toString()));
      final testCookie = cookies.firstWhere(
        (cookie) => cookie.name == testCookieName,
        orElse: () => Cookie(name: '', value: ''),
      );
      
      if (testCookie.name.isNotEmpty && testCookie.value == testCookieValue) {
        print('✅ Cookie functionality hoạt động bình thường');
      } else {
        print('❌ Cookie functionality có vấn đề');
      }
      
      // Clean up test cookie
      await cookieManager.deleteCookie(
        url: WebUri(url.toString()),
        name: testCookieName,
      );
      
    } catch (e) {
      print('❌ Lỗi khi test cookie functionality: $e');
    }
  }

  // Initialize global cookies
  Future<void> _initializeGlobalCookies() async {
    try {
      print('🌐 Initializing global cookies for WebView...');
      await _globalCookieManager.loadGlobalCookies();
      await _globalCookieManager.debugGlobalCookies();
    } catch (e) {
      print('❌ Error initializing global cookies: $e');
    }
  }

  @override
  void dispose() {
    print('🗑️ Disposing WebViewScreen...');
    
    // Remove lifecycle observer
    WidgetsBinding.instance.removeObserver(this);
    
    // Cancel timers
    _locationTimer?.cancel();
    _cookieSaveTimer?.cancel();
    _pullToRefreshController?.dispose();
    
    // Force save tất cả cookies trước khi dispose
    if (webViewController != null) {
      final uri = Uri.parse(widget.url);
      
      // Sử dụng force save để đảm bảo không mất cookies
      if (uri.host.contains('maqr.vn')) {
        _globalCookieManager.forceSaveAllCookies().catchError((e) {
          print('❌ Lỗi khi force save cookies trong dispose: $e');
        });
      } else {
        saveCookies(uri).catchError((e) {
          print('❌ Lỗi khi lưu cookies trong dispose: $e');
        });
      }
    }
    
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    final uri = Uri.parse(widget.url);

    return Scaffold(
      appBar: widget.showAppBar
          ? AppBar(
              title: const Text('Quay lại'),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.of(context).pop(),
              ),
            )
          : null,
      backgroundColor: Colors.white, // Đặt màu nền trắng để dễ thấy vấn đề
      body: Stack(
        children: [
          InAppWebView(
        pullToRefreshController: _pullToRefreshController,
        initialUrlRequest: URLRequest(url: WebUri(widget.url)),
        initialSettings: InAppWebViewSettings(
          // Cookie settings - chỉ dùng cookie để duy trì đăng nhập
          cacheEnabled: true,
          clearCache: false,
          sharedCookiesEnabled: true,
          thirdPartyCookiesEnabled: true, // Cho phép third-party cookies
          
          // Storage settings
          domStorageEnabled: true,
          databaseEnabled: true,
          
          // Network và Security
          mixedContentMode: MixedContentMode.MIXED_CONTENT_COMPATIBILITY_MODE,
          allowsInlineMediaPlayback: true,
          allowsAirPlayForMediaPlayback: true,
          
          // User experience
          supportZoom: true,
          mediaPlaybackRequiresUserGesture: false,
          useOnLoadResource: true,
          
          // Platform specific optimizations
          disableDefaultErrorPage: false,
          allowsLinkPreview: true,
          allowingReadAccessTo: WebUri('file://'),
          
          // Không dùng cache - luôn fetch mới từ server
          cacheMode: CacheMode.LOAD_NO_CACHE,
          applicationNameForUserAgent: 'QRScannerApp/1.0',
          
          // Headers để đảm bảo cookie được gửi
          userAgent: 'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Mobile Safari/537.36 QRScannerApp/1.0',
          
          // Fix màn hình đen
          transparentBackground: false,
          useHybridComposition: true, // Quan trọng để tránh màn hình đen trên Android
        ),
        onWebViewCreated: (controller) async {
          webViewController = controller;
          print('🌐 WebView được tạo, bắt đầu load cookies...');
          
          // Thêm handler để nhận message từ JavaScript
          controller.addJavaScriptHandler(
            handlerName: 'saveCookiesFromJS',
            callback: (args) async {
              print('🍪 JavaScript yêu cầu lưu cookies');
              await _saveCurrentCookies();
              return 'Cookies saved';
            },
          );

          // Đăng ký handler cho sự kiện đăng xuất từ JS
          controller.addJavaScriptHandler(
            handlerName: 'onLogout',
            callback: (args) async {
              print('🚪 [WEBVIEW] Nhận sự kiện đăng xuất từ WebView');
              await _globalCookieManager.clearAllCookiesAndStorage();
              print('✅ [WEBVIEW] Đã xóa toàn bộ cookies sau đăng xuất');
              return 'Logged out';
            },
          );
          
          await loadCookies(uri);
          // Debug cookies sau khi load
          await debugCookies(uri);
          // Inject location helpers ngay khi webview được tạo
          await _injectLocationHelpers();
        },
        onLoadStop: (controller, url) async {
          print('📄 Page load hoàn thành: $url');
          print('📱 Current URL: ${await controller.getUrl()}');
          print('📝 Page title: ${await controller.getTitle()}');

          // Kết thúc pull-to-refresh animation
          _pullToRefreshController?.endRefreshing();

          setState(() {
            _isPageLoaded = true;
            _loadingProgress = 1.0;
          });
          
          // Test cookie functionality
          await testCookieFunctionality(uri);
          
          // Đồng bộ cookies sau khi page load
          await syncCookies(uri);
          
          // Xử lý các vấn đề cookies
          await handleCookieIssues(uri);
          
          // Debug cookies sau khi xử lý
          await debugCookies(uri);
          
          // Re-inject location helpers sau khi page load xong
          await _injectLocationHelpers();

          // Inject JS để bắt sự kiện nút đăng xuất
          await _injectLogoutDetectorJS(controller);

          // Lưu localStorage để AccountScreen có thể sử dụng
          await _saveLocalStorage(controller);

          // Inject vị trí hiện tại nếu có
          if (!_isCheckingLocation) {
            _checkCurrentLocation();
          }
        },
        onProgressChanged: (controller, progress) {
          print('📊 Loading progress: $progress%');
          setState(() {
            _loadingProgress = progress / 100;
          });
        },
        onLoadStart: (controller, url) async {
          print('📄 Page bắt đầu load: $url');
        },
        onUpdateVisitedHistory: (controller, url, androidIsReload) async {
          print('📝 Update visited history: $url');
          // Lưu cookies khi có thay đổi history
          if (url != null) {
            await saveCookies(Uri.parse(url.toString()));
          }
        },
        shouldOverrideUrlLoading: (controller, navigationAction) async {
          final url = navigationAction.request.url.toString();
          print('Navigation detected: $url');
          
          // Xử lý các scheme đặc biệt
          final uri = Uri.parse(url);
          if (uri.scheme != 'http' && uri.scheme != 'https') {
            print('Detected special scheme: ${uri.scheme}');
            final handled = await _handleSpecialScheme(url);
            if (handled) {
              // Ngăn webview load URL này
              return NavigationActionPolicy.CANCEL;
            }
          }
          
          // Cho phép navigation bình thường
          return NavigationActionPolicy.ALLOW;
        },
        onConsoleMessage: (controller, consoleMessage) {
          print('🌐 [WEB CONSOLE] ${consoleMessage.messageLevel}: ${consoleMessage.message}');
        },
        onReceivedError: (controller, request, error) async {
          print('❌ WebView error: ${error.description}');
          print('❌ Error type: ${error.type}');
          print('❌ Failed URL: ${request.url}');
          
          // Xử lý ERR_NAME_NOT_RESOLVED - có thể do DNS cache hoặc network issue
          if (error.description.contains('ERR_NAME_NOT_RESOLVED')) {
            print('🔧 Phát hiện ERR_NAME_NOT_RESOLVED - đang xử lý...');
            
            // Clear cache và thử lại
            await controller.clearCache();
            print('🗑️ Đã clear cache, đợi 2 giây rồi thử lại...');
            
            // Đợi một chút trước khi retry
            await Future.delayed(const Duration(seconds: 2));
            
            // Reload
            await controller.reload();
            print('🔄 Đã reload WebView');
            
            return; // Không hiển thị error message ngay
          }
          
          // Hiển thị error cho user với các lỗi khác
          if (mounted) {
            String errorMessage = 'Lỗi tải trang';
            
            if (error.description.contains('ERR_INTERNET_DISCONNECTED')) {
              errorMessage = 'Không có kết nối internet';
            } else if (error.description.contains('ERR_CONNECTION_REFUSED')) {
              errorMessage = 'Không thể kết nối đến máy chủ';
            } else if (error.description.contains('ERR_CONNECTION_TIMED_OUT')) {
              errorMessage = 'Kết nối bị timeout';
            } else {
              errorMessage = 'Lỗi: ${error.description}';
            }
            
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(errorMessage),
                action: SnackBarAction(
                  label: 'Thử lại',
                  onPressed: () {
                    controller.reload();
                  },
                ),
                duration: const Duration(seconds: 5),
              ),
            );
          }
        },
        onReceivedHttpError: (controller, request, errorResponse) async {
          print('❌ HTTP error: ${errorResponse.statusCode}');
          print('❌ Failed URL: ${request.url}');
          
          final statusCode = errorResponse.statusCode;
          if (mounted && statusCode != null && statusCode >= 400) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Lỗi HTTP $statusCode'),
                action: SnackBarAction(
                  label: 'Thử lại',
                  onPressed: () {
                    controller.reload();
                  },
                ),
              ),
            );
          }
        },
      ),
          // Progress indicator
          if (_loadingProgress < 1.0)
            LinearProgressIndicator(
              value: _loadingProgress,
              backgroundColor: Colors.grey[200],
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.blue),
            ),
          // Loading overlay khi chưa load xong
          if (!_isPageLoaded)
            Container(
              color: Colors.white,
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Đang tải trang...', style: TextStyle(fontSize: 16)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
