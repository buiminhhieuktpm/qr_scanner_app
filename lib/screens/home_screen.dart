import 'package:flutter/material.dart';
import 'package:qr_code_scanner/qr_code_scanner.dart';
import '../models/scan_history.dart';
import '../services/history_service.dart';
import 'history_screen.dart';
import 'webview_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final GlobalKey qrKey = GlobalKey(debugLabel: 'QR');
  QRViewController? controller;
  bool scanned = false;
  bool showScanner = false;
  String? scannedLink;
  String? dynamicWebUrl; // Thêm biến này
  int _selectedIndex = 1; // Tab mặc định là WebView

  void _openWebView(String url) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WebViewScreen(url: url),
      ),
    );
  }

  void _onQRViewCreated(QRViewController controller) {
    this.controller = controller;
    controller.scannedDataStream.listen((scanData) async {
      if (!scanned) {
        scanned = true;
        await controller.pauseCamera();

        final history = ScanHistory(
          content: scanData.code ?? '',
          timestamp: DateTime.now(),
        );
        await HistoryService().saveScan(history);

        String? code = scanData.code;
        bool isUrl = code != null && (code.startsWith('http://') || code.startsWith('https://'));

        setState(() {
          scannedLink = isUrl ? code : null;
          showScanner = false;
        });

        if (isUrl) {
          _openWebView(code!);
          controller.resumeCamera();
          scanned = false;
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

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  void _startScan() {
    setState(() {
      showScanner = true;
      scanned = false;
      scannedLink = null;
    });
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
      showScanner = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Quét QR'),
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          // Tab 0: Quét QR
          Column(
            children: [
              if (!showScanner) ...[
                const Spacer(flex: 2),
                Center(
                  child: ElevatedButton(
                    onPressed: _startScan,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF036337),
                      minimumSize: const Size(200, 50),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Text(
                      'Quét',
                      style: TextStyle(fontSize: 20, color: Colors.white),
                    ),
                  ),
                ),
                const Spacer(flex: 2),
                if (scannedLink != null)
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        const Text('Đã quét được link:', style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        GestureDetector(
                          onTap: () {
                            _openWebView(scannedLink!);
                          },
                          child: Text(
                            scannedLink!,
                            style: const TextStyle(
                              color: Colors.blue,
                              decoration: TextDecoration.underline,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  ),
              ] else ...[
                Expanded(
                  flex: 4,
                  child: QRView(
                    key: qrKey,
                    onQRViewCreated: _onQRViewCreated,
                  ),
                ),
                const Expanded(
                  flex: 1,
                  child: Center(child: Text('Đưa mã QR vào khung để quét')),
                ),
              ],
            ],
          ),
          // Tab 1: WebView Trang chủ hoặc link động
          WebViewScreen(
            key: ValueKey(dynamicWebUrl ?? 'https://maqr.vn/vnptcheck'),
            url: dynamicWebUrl ?? 'https://maqr.vn/vnptcheck',
          ),
          // Tab 2: Lịch sử
          HistoryScreen(
            onUrlTap: (url) {
              _openWebView(url);
            },
          ),
          // Tab 3: Tài khoản (để trống)
          const Center(
            child: Text('Tài khoản', style: TextStyle(fontSize: 24)),
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.qr_code_scanner),
            label: 'Quét',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'Trang chủ',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.history),
            label: 'Lịch sử',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.account_circle),
            label: 'Tài khoản',
          ),
        ],
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        type: BottomNavigationBarType.fixed, // Thêm dòng này để hiển thị đủ 4 tab
      ),
    );
  }
}