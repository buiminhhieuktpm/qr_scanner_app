import 'package:flutter/material.dart';
import 'dart:async';
import 'package:qr_code_scanner/qr_code_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/native_permission_service.dart';

class QRScanScreen extends StatefulWidget {
  final Function(String)? onScanned;
  final bool isActive;
  
  const QRScanScreen({super.key, this.onScanned, this.isActive = true});

  @override
  _QRScanScreenState createState() => _QRScanScreenState();
}

class _QRScanScreenState extends State<QRScanScreen> {
  final GlobalKey qrKey = GlobalKey(debugLabel: 'QR');
  QRViewController? controller;
  StreamSubscription<Barcode>? _scanSubscription;
  bool scanned = false;

  @override
  void initState() {
    super.initState();
    _requestCameraPermission();
  }

  @override
  void dispose() {
    _scanSubscription?.cancel();
    controller?.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant QRScanScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.isActive != widget.isActive && controller != null) {
      if (widget.isActive) {
        controller!.resumeCamera();
        if (mounted) {
          setState(() {
            scanned = false;
          });
        }
      } else {
        controller!.pauseCamera();
      }
    }
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

  void _navigateToHomeWithUrl(String url) {
    // Gọi callback để báo cho HomeScreen load URL mới
    if (widget.onScanned != null) {
      widget.onScanned!(url);
    } else {
      // Fallback: pop về màn hình trước với URL
      Navigator.of(context).pop(url);
    }
  }

  void _onQRViewCreated(QRViewController controller) {
    _scanSubscription?.cancel();
    this.controller = controller;
    if (!widget.isActive) {
      controller.pauseCamera();
    }

    _scanSubscription = controller.scannedDataStream.listen((scanData) async {
      if (!scanned) {
        scanned = true;
        await controller.pauseCamera();

        String? code = scanData.code;
        
        // Tạm thời tắt xử lý scan trùng lặp để cùng một QR/link
        // vẫn được load lại và đi tiếp luồng lưu history.
        // if (_lastScannedCode == code &&
        //     _lastScanTime != null &&
        //     now.difference(_lastScanTime!) < const Duration(seconds: 2)) {
        //   print('⏭️ Bỏ qua scan trùng lặp: $code');
        //   scanned = false;
        //   controller.resumeCamera();
        //   return;
        // }
        
        bool isUrl = code != null && (code.startsWith('http://') || code.startsWith('https://'));

        if (isUrl) {
          // Quay về HomeScreen với URL đã quét
          _navigateToHomeWithUrl(code);
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
        child: QRView(
          key: qrKey,
          onQRViewCreated: _onQRViewCreated,
        ),
      ),
    );
  }
}
