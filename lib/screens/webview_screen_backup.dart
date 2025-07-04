import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:http/http.dart' as http;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/history_service.dart';
import '../models/scan_history.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/history_service.dart';
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

  @override
  void initState() {
    super.initState();
    _requestPermissions(); // Yêu cầu quyền ngay khi khởi tạo
    
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

  // Thêm method yêu cầu quyền
  Future<void> _requestPermissions() async {
    // Yêu cầu quyền vị trí
    await Permission.locationWhenInUse.request();
    
    // Yêu cầu quyền camera (cho QR scanner)
    await Permission.camera.request();
    
    // Kiểm tra trạng thái quyền
    final locationStatus = await Permission.locationWhenInUse.status;
    final cameraStatus = await Permission.camera.status;
    
    print('Trạng thái quyền vị trí: $locationStatus');
    print('Trạng thái quyền camera: $cameraStatus');
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
    final apiUrl = 'https://maqr.vn/api5/vnptcheck_apiv1/qrcode/thongtinsanpham/$qrcode';
    print('Gọi API: $apiUrl');
    
    try {
      // Tạo HTTP client với cấu hình SSL
      final client = http.Client();
      
      final response = await client.get(
        Uri.parse(apiUrl),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Linux; Android 10; SM-G973F) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.120 Mobile Safari/537.36',
          'Accept': 'application/json, text/plain, */*',
          'Accept-Language': 'vi-VN,vi;q=0.9,en;q=0.8',
          'Accept-Encoding': 'gzip, deflate, br',
          'Connection': 'keep-alive',
        },
      );
      
      client.close();
      
      print('Response status: ${response.statusCode}');
      print('Response body: ${response.body}');
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print('Data parsed từ API: $data');

        // Tạo ảnh QR code base64 (đơn giản hóa để test)
        String qrBase64 = '';
        try {
          qrBase64 = await generateQrBase64(qrcode);
          print('QR Base64 generated: ${qrBase64.isNotEmpty ? "Success" : "Failed"}');
        } catch (e) {
          print('Lỗi tạo QR base64: $e, sẽ lưu rỗng');
          qrBase64 = ''; // Lưu rỗng nếu lỗi
        }

        // Lấy tên sản phẩm
        final productName = data['data']?['sanpham']?['data']?['ten_sanpham'] ?? 'Không có tên sản phẩm';
        print('Tên sản phẩm: $productName');

        // Lưu lịch sử quét (đơn giản hóa để test)
        final scanHistory = ScanHistory(
          scannedAt: DateTime.now(),
          productName: productName,
          qrImage: qrBase64, // Có thể rỗng
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
              duration: const Duration(seconds: 3),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        print('Lỗi API: ${response.statusCode} - ${response.body}');
        
        // Lưu lịch sử với thông tin cơ bản ngay cả khi API lỗi
        final scanHistory = ScanHistory(
          scannedAt: DateTime.now(),
          productName: 'Sản phẩm (API lỗi ${response.statusCode})',
          qrImage: '',
          url: widget.url,
        );
        
        await HistoryService().saveScan(scanHistory);
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('API lỗi nhưng đã lưu lịch sử: ${response.statusCode}'),
              duration: const Duration(seconds: 3),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      print('Lỗi khi gọi API: $e');
      print('Stack trace: ${StackTrace.current}');
      
      // Lưu lịch sử với thông tin cơ bản ngay cả khi có lỗi
      try {
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
            SnackBar(
              content: const Text('Lỗi kết nối API nhưng đã lưu lịch sử'),
              duration: const Duration(seconds: 3),
              backgroundColor: Colors.red,
            ),
          );
        }
      } catch (saveError) {
        print('Lỗi khi lưu lịch sử backup: $saveError');
      }
    }
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
        },
        onLoadStop: (controller, url) async {
          await saveCookies(uri);
        },
      ),
      // Thêm FAB để test API call và lưu lịch sử
      floatingActionButton: widget.callApi 
          ? Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                FloatingActionButton(
                  heroTag: "test_save",
                  onPressed: () async {
                    print('Test Save: Bắt đầu test lưu lịch sử trực tiếp');
                    try {
                      final scanHistory = ScanHistory(
                        scannedAt: DateTime.now(),
                        productName: 'Test Product ${DateTime.now().millisecondsSinceEpoch}',
                        qrImage: '',
                        url: widget.url,
                      );
                      
                      await HistoryService().saveScan(scanHistory);
                      print('Test Save: Đã lưu thành công!');
                      
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Test: Đã lưu lịch sử thành công!'),
                            backgroundColor: Colors.green,
                            duration: Duration(seconds: 2),
                          ),
                        );
                      }
                    } catch (e) {
                      print('Test Save: Lỗi khi lưu: $e');
                    }
                  },
                  child: const Icon(Icons.save),
                  backgroundColor: Colors.green,
                ),
                const SizedBox(height: 8),
                FloatingActionButton(
                  heroTag: "test_api",
                  onPressed: () async {
                    // Test API call với QR code mẫu
                    print('Test FAB: Bắt đầu test API call');
                    await fetchQrcodeInfo('123456789'); // QR code test
                  },
                  child: const Icon(Icons.bug_report),
                  backgroundColor: Colors.red,
                ),
              ],
            )
          : null,
    );
  }
}