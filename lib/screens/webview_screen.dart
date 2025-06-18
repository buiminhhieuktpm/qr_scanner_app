// filepath: /Users/buiminhhieu/Desktop/qr_scan/qr_scanner_app/lib/screens/webview_screen.dart
import 'dart:convert';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:http/http.dart' as http;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
    final uri = Uri.parse(widget.url);
    String qrcode = '';
    if (uri.fragment.isNotEmpty) {
      qrcode = uri.fragment.split('/').last;
    } else {
      qrcode = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : '';
    }
    // Chỉ call API khi mở link từ quét QR (callApi == true)
    if (qrcode.isNotEmpty && widget.callApi) {
      fetchQrcodeInfo(qrcode);
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
    final qrValidationResult = QrValidator.validate(
      data: data,
      version: QrVersions.auto,
      errorCorrectionLevel: QrErrorCorrectLevel.L,
    );
    if (qrValidationResult.status == QrValidationStatus.valid) {
      final qrCode = qrValidationResult.qrCode!;
      final painter = QrPainter.withQr(
        qr: qrCode,
        color: const Color(0xFF000000),
        emptyColor: const Color(0xFFFFFFFF),
        gapless: true,
      );
      final picData = await painter.toImageData(300);
      if (picData != null) {
        final bytes = picData.buffer.asUint8List();
        return base64Encode(bytes);
      }
    }
    return '';
  }

  Future<void> fetchQrcodeInfo(String qrcode) async {
    final apiUrl = 'https://maqr.vn/api5/vnptcheck_apiv1/qrcode/thongtinsanpham/$qrcode';
    try {
      final response = await http.get(Uri.parse(apiUrl));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        // Tạo ảnh QR code base64
        final qrBase64 = await generateQrBase64(qrcode);

        // Lưu lịch sử quét
        final scanHistory = ScanHistory(
          scannedAt: DateTime.now(),
          productName: data['data']?['sanpham']?['data']?['ten_sanpham'] ?? '',
          qrImage: qrBase64,
          url: widget.url,
        );
        await HistoryService().saveScan(scanHistory);

        // Xoá phần hiển thị dialog kiểm tra object
        print('Object lấy được từ API: $data');
      } else {
        print('Lỗi API: ${response.statusCode}');
      }
    } catch (e) {
      print('Lỗi khi gọi API: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final uri = Uri.parse(widget.url);

    // Lấy mã sản phẩm từ cuối link
    String qrcode = '';
    if (uri.fragment.isNotEmpty) {
      // Nếu có fragment (sau dấu #), lấy phần cuối
      qrcode = uri.fragment.split('/').last;
    } else {
      // Nếu không có fragment, lấy phần cuối của path
      qrcode = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : '';
    }

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
        onWebViewCreated: (controller) async {
          webViewController = controller;
          await loadCookies(uri);
        },
        onLoadStop: (controller, url) async {
          await saveCookies(uri);
        },
      ), // <-- Đóng ngoặc cho InAppWebView
    );
  }
}