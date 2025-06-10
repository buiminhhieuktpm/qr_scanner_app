import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/scan_history.dart';
import '../services/history_service.dart';
import 'webview_screen.dart';

class HistoryScreen extends StatelessWidget {
  final void Function(String url)? onUrlTap;
  final HistoryService _historyService = HistoryService();

  HistoryScreen({super.key, this.onUrlTap});

  bool _isUrl(String text) {
    return text.startsWith('http://') || text.startsWith('https://');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lịch sử quét'),
      ),
      body: FutureBuilder<List<ScanHistory>>(
        future: _historyService.getHistory(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

          final histories = snapshot.data!;
          if (histories.isEmpty) return const Center(child: Text('Chưa có dữ liệu'));

          return ListView.builder(
            itemCount: histories.length,
            itemBuilder: (_, index) {
              final h = histories[index];
              final isUrl = _isUrl(h.content);
              return ListTile(
                title: isUrl
                    ? GestureDetector(
                        onTap: () {
                          if (isUrl) {
                            if (onUrlTap != null) {
                              onUrlTap!(h.content);
                            }
                          }
                        },
                        child: Text(
                          h.content,
                          style: const TextStyle(
                            color: Colors.blue,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      )
                    : Text(h.content),
                subtitle: Text(h.timestamp.toString()),
              );
            },
          );
        },
      ),
    );
  }
}