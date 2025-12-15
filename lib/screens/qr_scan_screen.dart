import 'package:flutter/material.dart';
import 'package:qr_code_scanner/qr_code_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import 'webview_screen.dart';
import '../services/native_permission_service.dart';

class QRScanScreen extends StatefulWidget {
  const QRScanScreen({super.key});

  @override
  _QRScanScreenState createState() => _QRScanScreenState();
}

class _QRScanScreenState extends State<QRScanScreen> {
  final GlobalKey qrKey = GlobalKey(debugLabel: 'QR');
  QRViewController? controller;
  bool scanned = false;

  @override
  void initState() {
    super.initState();
    _requestCameraPermission();
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  // Kiểm tra và yêu cầu quyền camera
  Future<void> _requestCameraPermission() async {
    try {
      print('=== CHECKING CAMERA PERMISSION ===');
      
      // Thử native method trước (hoạt động cho cả iOS và Android)
      final nativeStatus = await NativePermissionService.getCameraPermissionStatus();
      print('🎯 Native camera status: $nativeStatus');
      
      if (nativeStatus == 'authorized') {
        print('✅ Native camera permission already granted');
        return;
      }
      
      if (nativeStatus == 'notDetermined') {
        print('🎯 Requesting native camera permission...');
        final granted = await NativePermissionService.requestCameraPermissionNative();
        print('🎯 Native permission result: $granted');
        if (granted) return;
      }
      
      // Fallback to permission_handler
      print('=== FALLBACK TO PERMISSION_HANDLER ===');
      final currentStatus = await Permission.camera.status;
      print('📱 Permission handler status: $currentStatus');
      
      if (currentStatus.isGranted) {
        return;
      }
      
      // Force request permission 
      print('📱 Force requesting permission...');
      final requestedStatus = await Permission.camera.request();
      print('📱 Permission result: $requestedStatus');
      
      if (requestedStatus.isGranted) {
        print('✅ Permission granted via permission_handler');
        return;
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
      }
    } catch (e) {
      print('❌ Lỗi khi request camera permission: $e');
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

        if (isUrl) {
          _openWebView(code, callApi: true);
          // Reset trạng thái sau khi mở webview
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted) {
              controller.resumeCamera();
              setState(() {
                scanned = false;
              });
            }
          });
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
                    setState(() {
                      scanned = false;
                    });
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
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
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Icon(Icons.qr_code_scanner, size: 48, color: Color(0xFF1565C0)),
                    SizedBox(height: 8),
                    Text(
                      'Đưa mã QR vào khung để quét',
                      style: TextStyle(fontSize: 16),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
