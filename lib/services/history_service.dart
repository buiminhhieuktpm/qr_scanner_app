import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/scan_history.dart';

class HistoryService {
  static const String historyKey = 'scan_history';

  Future<void> saveScan(ScanHistory scan) async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> history = prefs.getStringList(historyKey) ?? [];
    print('tên sản phẩm: ${scan.productName}');
    history.insert(0, jsonEncode(scan.toJson())); // Lưu mới nhất lên đầu
    await prefs.setStringList(historyKey, history);
  }

  Future<List<ScanHistory>> getHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> history = prefs.getStringList(historyKey) ?? [];
    return history.map((e) => ScanHistory.fromJson(jsonDecode(e))).toList();
  }
}