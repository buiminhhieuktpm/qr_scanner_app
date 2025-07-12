import 'package:flutter/material.dart';
import 'dart:io';
import 'native_permission_service.dart';

class PermissionDialogService {
  static bool _isDialogShowing = false;
  
  /// Hiển thị dialog hướng dẫn user vào Settings để bật quyền vị trí
  static Future<void> showLocationPermissionDialog(BuildContext context) async {
    if (_isDialogShowing) return;
    
    _isDialogShowing = true;
    
    try {
      return showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.location_on, color: Colors.orange),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Cần quyền truy cập vị trí',
                  style: TextStyle(fontSize: 18),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Ứng dụng cần quyền truy cập vị trí để hoạt động tốt nhất.',
                  style: TextStyle(fontSize: 14),
                ),
                SizedBox(height: 12),
                if (Platform.isIOS) ...[
                  Text(
                    'Hướng dẫn bật quyền:',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  SizedBox(height: 8),
                  Padding(
                    padding: EdgeInsets.only(left: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('• Nhấn "Mở Cài đặt"', style: TextStyle(fontSize: 12)),
                        Text('• Tìm "Quyền riêng tư & Bảo mật"', style: TextStyle(fontSize: 12)),
                        Text('• Chọn "Dịch vụ vị trí"', style: TextStyle(fontSize: 12)),
                        Text('• Tìm "QR Scanner App"', style: TextStyle(fontSize: 12)),
                        Text('• Chọn "Khi sử dụng ứng dụng"', style: TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                ] else ...[
                  Text(
                    'Vui lòng bật quyền vị trí trong cài đặt ứng dụng.',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              ],
            ),
          ),
          actions: <Widget>[
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  child: Text(
                    'Để sau',
                    style: TextStyle(color: Colors.grey[600], fontSize: 14),
                  ),
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                ),
                SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    icon: Icon(Icons.settings, size: 16),
                    label: Text(
                      'Mở Cài đặt',
                      style: TextStyle(fontSize: 14),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    onPressed: () async {
                      Navigator.of(context).pop();
                      print("📱 Mở Settings app...");
                      final opened = await NativePermissionService.openAppSettings();
                      if (!opened) {
                        print("📱 ❌ Không thể mở Settings app");
                      }
                    },
                  ),
                ),
              ],
            ),
          ],
          );
        },
      );
    } finally {
      _isDialogShowing = false;
    }
  }
  
  /// Kiểm tra và hiển thị dialog nếu cần thiết dựa trên status
  static Future<void> checkAndShowLocationPermissionDialog(
    BuildContext context, 
    String permissionStatus
  ) async {
    if (permissionStatus == 'denied' || permissionStatus == 'restricted') {
      print("📱 Quyền vị trí bị từ chối, hiển thị dialog hướng dẫn Settings");
      await showLocationPermissionDialog(context);
    }
  }
}
