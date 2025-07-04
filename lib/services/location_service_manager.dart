import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

class LocationServiceManager {
  static final LocationServiceManager _instance = LocationServiceManager._internal();
  factory LocationServiceManager() => _instance;
  LocationServiceManager._internal();

  bool _dialogShown = false;
  bool _isCheckingLocation = false;
  
  // Singleton để đảm bảo chỉ một dialog được hiển thị
  static bool get isDialogShown => _instance._dialogShown;
  static bool get isCheckingLocation => _instance._isCheckingLocation;
  
  static void setDialogShown(bool shown) {
    _instance._dialogShown = shown;
  }
  
  static void setCheckingLocation(bool checking) {
    _instance._isCheckingLocation = checking;
  }
  
  static void reset() {
    _instance._dialogShown = false;
    _instance._isCheckingLocation = false;
  }
  
  // Method để hiển thị dialog location service một cách an toàn
  static Future<void> showLocationServiceDialog(BuildContext context, String source) async {
    if (_instance._dialogShown) {
      print('$source: Location dialog already shown, skipping...');
      return;
    }
    
    _instance._dialogShown = true;
    print('$source: Showing location service dialog');
    
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Dịch vụ vị trí bị tắt'),
          content: const Text('Vui lòng bật dịch vụ vị trí trong cài đặt để ứng dụng có thể theo dõi vị trí của bạn.'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _instance._dialogShown = false;
                print('$source: User dismissed location dialog');
              },
              child: const Text('Bỏ qua'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.of(context).pop();
                _instance._dialogShown = false;
                print('$source: Opening location settings');
                // Mở cài đặt vị trí
                bool opened = await Geolocator.openLocationSettings();
                print('$source: Location settings opened: $opened');
              },
              child: const Text('Mở cài đặt'),
            ),
          ],
        );
      },
    );
  }
}
