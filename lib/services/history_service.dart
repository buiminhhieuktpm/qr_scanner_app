import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/scan_history.dart';

class HistoryService {
  static const String historyKey = 'scan_history';

  Future<void> saveScan(ScanHistory scan) async {
    try {
      print('HistoryService: Bắt đầu lưu scan history');
      final prefs = await SharedPreferences.getInstance();
      final List<String> history = prefs.getStringList(historyKey) ?? [];
      
      print('HistoryService: Lịch sử hiện tại có ${history.length} items');
      print('HistoryService: Tên sản phẩm: ${scan.productName}');
      print('HistoryService: URL: ${scan.url}');
      print('HistoryService: Thời gian: ${scan.scannedAt}');
      
      final scanJson = jsonEncode(scan.toJson());
      print('HistoryService: JSON data: $scanJson');
      
      history.insert(0, scanJson); // Lưu mới nhất lên đầu
      
      final result = await prefs.setStringList(historyKey, history);
      print('HistoryService: Kết quả lưu: $result');
      
      // Kiểm tra lại dữ liệu đã lưu
      final savedHistory = prefs.getStringList(historyKey) ?? [];
      print('HistoryService: Sau khi lưu, có ${savedHistory.length} items');
      
    } catch (e, stackTrace) {
      print('HistoryService: Lỗi khi lưu: $e');
      print('HistoryService: Stack trace: $stackTrace');
      rethrow;
    }
  }

  Future<List<ScanHistory>> getHistory() async {
    try {
      print('HistoryService: Đang lấy lịch sử');
      final prefs = await SharedPreferences.getInstance();
      final List<String> history = prefs.getStringList(historyKey) ?? [];
      print('HistoryService: Tìm thấy ${history.length} items trong lịch sử');
      
      final result = history.map((e) {
        try {
          return ScanHistory.fromJson(jsonDecode(e));
        } catch (parseError) {
          print('HistoryService: Lỗi parse item: $e - Error: $parseError');
          return null;
        }
      }).whereType<ScanHistory>().toList();
      
      print('HistoryService: Trả về ${result.length} items hợp lệ');
      return result;
    } catch (e, stackTrace) {
      print('HistoryService: Lỗi khi lấy lịch sử: $e');
      print('HistoryService: Stack trace: $stackTrace');
      return [];
    }
  }
}