import 'package:flutter/material.dart';
import 'package:qr_code_scanner/qr_code_scanner.dart';
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
  int _selectedIndex = 1; // 0: Home(WebView), 1: History, 2: Account

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

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  void _onItemTapped(int index) {
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
        key: ValueKey('https://maqr.vn/vnptcheck/#/app'),
        url: 'https://maqr.vn/vnptcheck/#/app',
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
              key: ValueKey('https://maqr.vn/vnptcheck/#/taikhoan'),
              url: 'https://maqr.vn/vnptcheck/#/taikhoan',
              showAppBar: false,
            ),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        color: Colors.white,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_selectedIndex == 1 && !showScanner)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                child: ElevatedButton.icon(
                  onPressed: () {
                    setState(() {
                      showScanner = true;
                      scanned = false;
                    });
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