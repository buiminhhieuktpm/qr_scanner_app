import 'dart:convert';
import 'package:flutter/material.dart';
import '../models/scan_history.dart';
import '../services/history_service.dart';

class HistoryScreen extends StatefulWidget {
  final void Function(String url)? onUrlTap;

  const HistoryScreen({super.key, this.onUrlTap});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final HistoryService _historyService = HistoryService();

  Future<void> _refreshHistory() async {
    setState(() {}); // Trigger rebuild
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
              return ListTile(
                leading: h.qrImage.isNotEmpty
                    ? Image.memory(
                        base64Decode(h.qrImage),
                        width: 56,
                        height: 56,
                        fit: BoxFit.cover,
                      )
                    : const Icon(Icons.qr_code, size: 40),
                title: Text(
                  h.productName.isNotEmpty ? h.productName : 'Không rõ tên sản phẩm',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  'Thời gian: ${h.scannedAt.toLocal().toString().substring(0, 19)}',
                  style: const TextStyle(fontSize: 13),
                ),
                onTap: () {
                  if (widget.onUrlTap != null && h.url.isNotEmpty) {
                    widget.onUrlTap!(h.url);
                  }
                },
              );
            },
          );
        },
      ),
    );
  }
}