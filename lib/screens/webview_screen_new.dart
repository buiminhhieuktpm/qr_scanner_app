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

class _WebViewScreenState extends State<WebViewScreen> {
  InAppWebViewController? webViewController;
  Timer? _locationTimer;
  bool _isCheckingLocation = false; // Cờ để tránh check location đồng thời

  @override
  void initState() {
    super.initState();
    
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

  // Kiểm tra quyền vị trí đơn giản
  Future<void> _checkLocationPermission() async {
    try {
      print('🔍 Kiểm tra quyền vị trí...');
      
      final hasPermission = await LocationPermissionManager.hasLocationPermission();
      if (hasPermission) {
        print('✅ Đã có quyền vị trí, bắt đầu tracking');
        _startLocationTracking();
      } else {
        print('⚠️ Không có quyền vị trí');
        // Không làm gì thêm - chỉ xin quyền lần đầu tiên mở app
      }
    } catch (e) {
      print('💥 Lỗi khi kiểm tra quyền vị trí: $e');
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
    final cookieManager = CookieManager.instance();
    final cookies = await cookieManager.getCookies(url: WebUri(url.toString()));
    final prefs = await SharedPreferences.getInstance();
    final cookieString = cookies.map((c) => '${c.name}=${c.value}').join(';');
    await prefs.setString('cookies', cookieString);
  }

  Future<void> loadCookies(Uri url) async {
    final prefs = await SharedPreferences.getInstance();
    final cookieString = prefs.getString('cookies');
    if (cookieString != null) {
      final cookieManager = CookieManager.instance();
      for (var cookie in cookieString.split(';')) {
        final parts = cookie.split('=');
        if (parts.length == 2) {
          await cookieManager.setCookie(
            url: WebUri(url.toString()),
            name: parts[0].trim(),
            value: parts[1].trim(),
          );
        }
      }
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

  void _checkCurrentLocation() async {
    if (_isCheckingLocation) {
      print('⚠️ Đang check location, bỏ qua lần này');
      return;
    }
    
    _isCheckingLocation = true;
    
    try {
      print('📍 Đang lấy vị trí hiện tại...');
      
      // Kiểm tra lại quyền trước khi lấy vị trí
      bool hasPermission = await LocationPermissionManager.hasLocationPermission();
      if (!hasPermission) {
        print('❌ Không có quyền vị trí, dừng tracking');
        _locationTimer?.cancel();
        return;
      }
      
      // Kiểm tra dịch vụ vị trí có được bật không
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        print('⚠️ Dịch vụ vị trí bị tắt, không thể lấy vị trí');
        
        // Hiển thị dialog một lần duy nhất nếu chưa hiển thị
        if (mounted) {
          await LocationPermissionManager.showLocationServiceDisabledDialog(context);
        }
        return;
      }
      
      // Lấy vị trí hiện tại
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
      
      print('📍 Vị trí hiện tại: ${position.latitude}, ${position.longitude}');
      
      // Inject vị trí vào JavaScript
      if (webViewController != null) {
        await webViewController!.evaluateJavascript(source: '''
          try {
            if (typeof window.locationData === 'undefined') {
              window.locationData = {};
            }
            window.locationData.latitude = ${position.latitude};
            window.locationData.longitude = ${position.longitude};
            window.locationData.accuracy = ${position.accuracy};
            window.locationData.timestamp = ${position.timestamp.millisecondsSinceEpoch};
            
            console.log('Location injected:', window.locationData);
            
            // Trigger location update event nếu có
            if (typeof window.onLocationUpdate === 'function') {
              window.onLocationUpdate(window.locationData);
            }
            
            // Dispatch custom event
            window.dispatchEvent(new CustomEvent('locationupdate', { 
              detail: window.locationData 
            }));
          } catch (e) {
            console.error('Error injecting location:', e);
          }
        ''');
        
        print('✅ Đã inject vị trí vào WebView');
      }
      
    } catch (e) {
      print('❌ Lỗi khi lấy vị trí: $e');
    } finally {
      _isCheckingLocation = false;
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
          
          console.log('Location helpers injected successfully');
        })();
      ''');
      
      print('✅ Đã inject location helpers vào WebView');
    } catch (e) {
      print('❌ Lỗi khi inject location helpers: $e');
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

  @override
  void dispose() {
    _locationTimer?.cancel();
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
      body: InAppWebView(
        initialUrlRequest: URLRequest(url: WebUri(widget.url)),
        initialSettings: InAppWebViewSettings(
          cacheEnabled: true,
          useOnLoadResource: true,
          clearCache: false,
          sharedCookiesEnabled: true,
          domStorageEnabled: true,
          databaseEnabled: true, // Android: bật Web SQL Database
          supportZoom: true,
          mediaPlaybackRequiresUserGesture: false,
          // iOS: các tuỳ chọn này sẽ tự động bật cache
        ),
        onWebViewCreated: (controller) async {
          webViewController = controller;
          await loadCookies(uri);
          // Inject location helpers ngay khi webview được tạo
          await _injectLocationHelpers();
        },
        onLoadStop: (controller, url) async {
          await saveCookies(uri);
          // Re-inject location helpers sau khi page load xong
          await _injectLocationHelpers();
          // Inject vị trí hiện tại nếu có
          if (!_isCheckingLocation) {
            _checkCurrentLocation();
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
        onReceivedError: (controller, request, error) async {
          print('WebView error: ${error.description}');
          print('Error type: ${error.type}');
          print('Failed URL: ${request.url}');
          
          // Thử load lại với HTTP nếu HTTPS fail
          if (request.url.toString().startsWith('https://')) {
            final httpUrl = request.url.toString().replaceFirst('https://', 'http://');
            print('Thử load lại với HTTP: $httpUrl');
            await controller.loadUrl(urlRequest: URLRequest(url: WebUri(httpUrl)));
          }
        },
      ),
    );
  }
}
