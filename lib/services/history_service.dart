import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/scan_history.dart';

class HistoryService {
  static const String _key = 'scan_history';

  Future<void> saveScan(ScanHistory history) async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> histories = prefs.getStringList(_key) ?? [];

    histories.add(jsonEncode(history.toJson()));
    await prefs.setStringList(_key, histories);
  }

  Future<List<ScanHistory>> getHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> histories = prefs.getStringList(_key) ?? [];

    return histories
        .map((e) => ScanHistory.fromJson(jsonDecode(e)))
        .toList()
        .reversed
        .toList(); // Hiển thị mới nhất lên đầu
  }
}