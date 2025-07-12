import 'package:flutter/material.dart';
import 'webview_screen.dart';

class LocationDemoScreen extends StatelessWidget {
  const LocationDemoScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Demo Vị trí trong WebView'),
        backgroundColor: Colors.green,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '🌍 Chia sẻ vị trí với WebView',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'App sẽ tự động chia sẻ vị trí hiện tại với website trong WebView. '
                      'Website có thể sử dụng JavaScript để truy cập thông tin vị trí.',
                      style: TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const WebViewScreen(
                      url: 'file:///android_asset/flutter_assets/web/location_test.html',
                      showAppBar: true,
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.web),
              label: const Text('Test đầy đủ (HTML phức tạp)'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const WebViewScreen(
                      url: 'file:///android_asset/flutter_assets/web/simple_location_test.html',
                      showAppBar: true,
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.location_on),
              label: const Text('Test đơn giản'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const WebViewScreen(
                      url: 'https://www.google.com/maps',
                      showAppBar: true,
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.map),
              label: const Text('Test với Google Maps'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
            const SizedBox(height: 20),
            const Card(
              color: Colors.blue,
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '💡 Hướng dẫn sử dụng:',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      '1. App sẽ tự động yêu cầu quyền vị trí\n'
                      '2. Vị trí được cập nhật mỗi 10 giây\n'
                      '3. Website có thể truy cập vị trí qua window.getLocation()\n'
                      '4. Hoặc dùng navigator.geolocation như bình thường',
                      style: TextStyle(fontSize: 14, color: Colors.white),
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
