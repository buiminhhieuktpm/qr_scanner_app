import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/history_service.dart';
import '../services/location_service_manager.dart';
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
    // Chỉ kiểm tra và yêu cầu quyền vị trí dựa trên thời gian
    _checkLocationPermissionTiming(); 
    
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
      Future.delayed(const Duration(milliseconds: 500), () {
        fetchQrcodeInfo(qrcode);
      });
    }
  }

  // Kiểm tra và yêu cầu quyền vị trí theo logic mới
  Future<void> _checkLocationPermissionTiming() async {
    final prefs = await SharedPreferences.getInstance();
    final hasGrantedLocation = prefs.getBool('has_granted_location') ?? false;
    final lastLocationRequestTime = prefs.getInt('last_location_request_time');
    
    final now = DateTime.now().millisecondsSinceEpoch;
    
    // Nếu đã cấp quyền vị trí rồi, bắt đầu tracking luôn
    if (hasGrantedLocation) {
      print('Đã có quyền vị trí, bắt đầu theo dõi vị trí');
      _startLocationTracking();
      return;
    }
    
    // Nếu chưa từng yêu cầu quyền hoặc đã đủ 30 phút kể từ lần yêu cầu cuối
    bool shouldRequestPermission = false;
    
    if (lastLocationRequestTime == null) {
      // Lần đầu tiên
      print('Lần đầu mở app, yêu cầu quyền vị trí');
      shouldRequestPermission = true;
    } else {
      // Kiểm tra đã đủ 30 phút chưa (30 phút = 1800000 ms)
      final timeDiff = now - lastLocationRequestTime;
      const thirtyMinutes = 30 * 60 * 1000;
      
      if (timeDiff >= thirtyMinutes) {
        print('Đã đủ 30 phút kể từ lần yêu cầu cuối, yêu cầu quyền vị trí lại');
        shouldRequestPermission = true;
      } else {
        final remainingTime = thirtyMinutes - timeDiff;
        final remainingMinutes = (remainingTime / (60 * 1000)).round();
        print('Còn $remainingMinutes phút nữa sẽ yêu cầu quyền vị trí lại');
      }
    }
    
    if (shouldRequestPermission) {
      // Lưu thời gian yêu cầu quyền
      await prefs.setInt('last_location_request_time', now);
      
      // Yêu cầu quyền
      final granted = await _requestLocationPermission();
      if (granted) {
        print('User đã cấp quyền vị trí');
        await prefs.setBool('has_granted_location', true);
        _startLocationTracking();
      } else {
        print('User từ chối cấp quyền vị trí, sẽ hỏi lại sau 30 phút');
      }
    }
  }

  // Method yêu cầu quyền vị trí và trả về kết quả
  Future<bool> _requestLocationPermission() async {
    try {
      // Yêu cầu quyền vị trí
      final locationStatus = await Permission.locationWhenInUse.request();
      
      print('Trạng thái quyền vị trí: $locationStatus');
      
      if (locationStatus.isGranted) {
        // Kiểm tra xem dịch vụ vị trí có được bật không
        bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
        print('Dịch vụ vị trí đã bật: $serviceEnabled');
        
        if (!serviceEnabled) {
          print('Dịch vụ vị trí bị tắt, yêu cầu bật');
          if (mounted && !LocationServiceManager.isDialogShown) {
            await LocationServiceManager.showLocationServiceDialog(context, 'WebView');
          }
          return false;
        }
        
        return true;
      } else {
        print('User từ chối cấp quyền vị trí');
        return false;
      }
    } catch (e) {
      print('Lỗi khi yêu cầu quyền vị trí: $e');
      return false;
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
            } else if (data['product_name'] != null) {
              productName = data['product_name'];
            } else if (data['name'] != null) {
              productName = data['name'];
            }
            
            print('Tên sản phẩm: $productName');

            // Lưu lịch sử quét
            final scanHistory = ScanHistory(
              scannedAt: DateTime.now(),
              productName: productName,
              qrImage: qrBase64,
              url: widget.url,
            );
            
            print('Đang lưu lịch sử...');
            await HistoryService().saveScan(scanHistory);
            print('Đã lưu lịch sử thành công!');

            // Hiển thị thông báo lưu thành công
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Đã lưu lịch sử: $productName'),
                  duration: const Duration(seconds: 2),
                ),
              );
            }
            return; // Thành công, thoát khỏi loop
          } catch (jsonError) {
            print('Lỗi parse JSON: $jsonError');
            print('Response body: ${response.body}');
          }
          
        } else {
          print('Lỗi API: ${response.statusCode}');
          if (response.statusCode == 404) {
            print('API URL không tồn tại: $apiUrl');
          }
        }
        
      } catch (e) {
        print('Lỗi khi gọi API $apiUrl: $e');
      }
    }
    
    // Nếu tất cả URL đều thất bại, lưu lịch sử với thông tin lỗi
    print('Tất cả URL API đều thất bại, lưu lịch sử backup');
    
    final scanHistory = ScanHistory(
      scannedAt: DateTime.now(),
      productName: 'Sản phẩm (Lỗi kết nối)',
      qrImage: '',
      url: widget.url,
    );
    
    await HistoryService().saveScan(scanHistory);
    print('Đã lưu lịch sử backup thành công!');
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Đã lưu lịch sử (không thể lấy thông tin sản phẩm)'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  // Bắt đầu theo dõi vị trí mỗi 10 giây
  void _startLocationTracking() {
    // Hủy timer cũ nếu có
    _locationTimer?.cancel();
    
    _locationTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      _checkCurrentLocation();
    });
    
    // Delay kiểm tra vị trí ban đầu để tránh xung đột với permission request
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        _checkCurrentLocation();
      }
    });
  }

  // Kiểm tra vị trí hiện tại
  Future<void> _checkCurrentLocation() async {
    // Tránh check location đồng thời
    if (_isCheckingLocation) {
      print('Location check already in progress, skipping...');
      return;
    }
    
    _isCheckingLocation = true;
    
    try {
      // Kiểm tra quyền vị trí
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          print('Location permissions denied');
          return;
        }
      }
      
      if (permission == LocationPermission.deniedForever) {
        print('Location permissions permanently denied');
        return;
      }

      // Kiểm tra xem dịch vụ vị trí có được bật không
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        print('WebView: Location service disabled');
        
        // Sử dụng LocationServiceManager để hiển thị dialog
        if (mounted && !LocationServiceManager.isDialogShown) {
          await LocationServiceManager.showLocationServiceDialog(context, 'WebView');
        }
        return;
      }
      
      // Reset dialog flag khi dịch vụ vị trí đã được bật
      LocationServiceManager.setDialogShown(false);

      // Lấy vị trí hiện tại
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );

      // In thông tin vị trí
      print('=== LOCATION CHECK (${DateTime.now().toString()}) ===');
      print('Latitude: ${position.latitude}');
      print('Longitude: ${position.longitude}');
      print('Accuracy: ${position.accuracy} meters');
      print('Altitude: ${position.altitude} meters');
      print('Speed: ${position.speed} m/s');
      print('Heading: ${position.heading}°');
      print('Timestamp: ${position.timestamp}');
      print('=== END LOCATION CHECK ===');

      // Truyền vị trí vào webview
      await _injectLocationToWebView(position);

    } catch (e) {
      print('Error getting location: $e');
    } finally {
      _isCheckingLocation = false;
    }
  }

  // Method để inject vị trí vào webview
  Future<void> _injectLocationToWebView(Position position) async {
    if (webViewController == null) {
      print('WebViewController chưa sẵn sàng, bỏ qua inject location');
      return;
    }

    try {
      // Tạo JavaScript code để set location data vào window object
      final jsCode = '''
        // Tạo object location để webview có thể truy cập
        window.currentLocation = {
          latitude: ${position.latitude},
          longitude: ${position.longitude},
          accuracy: ${position.accuracy},
          altitude: ${position.altitude},
          speed: ${position.speed},
          heading: ${position.heading},
          timestamp: ${position.timestamp.millisecondsSinceEpoch}
        };
        
        // Trigger event để thông báo có location mới
        if (typeof window.onLocationUpdate === 'function') {
          window.onLocationUpdate(window.currentLocation);
        }
        
        // Dispatch custom event
        window.dispatchEvent(new CustomEvent('locationUpdate', {
          detail: window.currentLocation
        }));
        
        console.log('Location updated:', window.currentLocation);
      ''';

      await webViewController!.evaluateJavascript(source: jsCode);
      print('Đã inject vị trí vào webview: ${position.latitude}, ${position.longitude}');
    } catch (e) {
      print('Lỗi khi inject location vào webview: $e');
    }
  }

  // Method để inject JavaScript helpers vào webview khi load
  Future<void> _injectLocationHelpers() async {
    if (webViewController == null) return;

    try {
      final jsCode = '''
        // Helper functions để webview dễ dàng sử dụng location
        window.getLocation = function() {
          return window.currentLocation || null;
        };
        
        window.watchLocation = function(callback) {
          if (typeof callback === 'function') {
            window.onLocationUpdate = callback;
            // Gọi callback ngay lập tức nếu đã có location
            if (window.currentLocation) {
              callback(window.currentLocation);
            }
          }
        };
        
        // Mock navigator.geolocation để compatibility
        if (!navigator.geolocation) {
          navigator.geolocation = {};
        }
        
        navigator.geolocation.getCurrentPosition = function(success, error, options) {
          if (window.currentLocation && typeof success === 'function') {
            const position = {
              coords: {
                latitude: window.currentLocation.latitude,
                longitude: window.currentLocation.longitude,
                accuracy: window.currentLocation.accuracy,
                altitude: window.currentLocation.altitude,
                speed: window.currentLocation.speed,
                heading: window.currentLocation.heading
              },
              timestamp: window.currentLocation.timestamp
            };
            success(position);
          } else if (typeof error === 'function') {
            error({ code: 1, message: 'Location not available' });
          }
        };
        
        navigator.geolocation.watchPosition = function(success, error, options) {
          window.watchLocation(function(location) {
            if (typeof success === 'function') {
              const position = {
                coords: {
                  latitude: location.latitude,
                  longitude: location.longitude,
                  accuracy: location.accuracy,
                  altitude: location.altitude,
                  speed: location.speed,
                  heading: location.heading
                },
                timestamp: location.timestamp
              };
              success(position);
            }
          });
          return 1; // Mock watch ID
        };
        
        navigator.geolocation.clearWatch = function(id) {
          window.onLocationUpdate = null;
        };
        
        console.log('Location helpers injected successfully');
      ''';

      await webViewController!.evaluateJavascript(source: jsCode);
      print('Đã inject location helpers vào webview');
    } catch (e) {
      print('Lỗi khi inject location helpers: $e');
    }
  }

  // Method để xử lý các URL scheme đặc biệt
  Future<bool> _handleSpecialScheme(String url) async {
    final uri = Uri.parse(url);
    
    try {
      // Xử lý các scheme đặc biệt
      switch (uri.scheme.toLowerCase()) {
        case 'tel':
          print('Đang mở ứng dụng điện thoại: $url');
          return await launchUrl(uri, mode: LaunchMode.externalApplication);
          
        case 'mailto':
          print('Đang mở ứng dụng email: $url');
          return await launchUrl(uri, mode: LaunchMode.externalApplication);
          
        case 'sms':
          print('Đang mở ứng dụng tin nhắn: $url');
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
          
          // Xử lý lỗi ERR_UNKNOWN_URL_SCHEME
          if (error.description.contains('ERR_UNKNOWN_URL_SCHEME') || 
              error.description.contains('unknown url scheme')) {
            final url = request.url.toString();
            print('Handling unknown URL scheme: $url');
            await _handleSpecialScheme(url);
          }
        },
      ),

    );
  }
}
