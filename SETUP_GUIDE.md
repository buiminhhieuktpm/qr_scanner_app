# QR Scanner App với Location Integration

## Tổng quan
Ứng dụng quét QR code với tính năng chia sẻ vị trí tự động vào WebView. App có thể theo dõi vị trí real-time và truyền dữ liệu này vào các website được mở trong WebView.

## Tính năng chính

### ✅ Đã hoàn thành:
- 📱 Quét QR code và mở link
- 🌍 Theo dõi vị trí GPS tự động
- 🌐 Inject vị trí vào WebView qua JavaScript
- 💾 Lưu lịch sử quét QR code
- 🔐 Quản lý quyền truy cập (Camera, Location)
- 📍 Dialog yêu cầu bật dịch vụ vị trí

### 🆕 Mới thêm:
- 🚀 **Truyền vị trí vào WebView** - Website có thể truy cập vị trí qua JavaScript
- 🎯 **Demo screen** để test chức năng location
- 📊 **Location API** tương thích với HTML5 Geolocation
- ⏰ **Real-time updates** mỗi 10 giây

## Cách chạy ứng dụng

### 1. Yêu cầu hệ thống
- Flutter SDK (>= 3.0.0)
- Android Studio hoặc VS Code
- Android device/emulator với Android 6.0+ (API 23+)
- iOS device/simulator với iOS 10.0+

### 2. Cài đặt dependencies
```bash
flutter pub get
```

### 3. Chạy ứng dụng
```bash
# Debug mode
flutter run

# Release mode
flutter run --release

# Chỉ định device
flutter run -d <device_id>
```

### 4. Build APK
```bash
# Debug APK
flutter build apk --debug

# Release APK
flutter build apk --release

# Split APK per ABI
flutter build apk --split-per-abi
```

## Cách test Location trong WebView

### 1. Từ Home Screen
- Nhấn nút **"Demo Location"** trong tab "Quét QrCode"
- Chọn một trong các option test:
  - **Test đơn giản**: HTML cơ bản hiển thị vị trí
  - **Test đầy đủ**: HTML với bản đồ và nhiều tính năng
  - **Google Maps**: Test với website thật

### 2. Từ WebView trực tiếp
Mở WebView với một trong các URL sau:
```
file:///android_asset/flutter_assets/web/simple_location_test.html
file:///android_asset/flutter_assets/web/location_test.html
```

### 3. JavaScript API có sẵn trong WebView

#### Lấy vị trí hiện tại:
```javascript
const location = window.getLocation();
if (location) {
    console.log('Lat:', location.latitude);
    console.log('Lng:', location.longitude);
}
```

#### Theo dõi vị trí:
```javascript
window.watchLocation(function(location) {
    console.log('New location:', location);
});
```

#### HTML5 Geolocation API:
```javascript
navigator.geolocation.getCurrentPosition(
    function(position) {
        console.log('Lat:', position.coords.latitude);
    },
    function(error) {
        console.log('Error:', error.message);
    }
);
```

## Cấu trúc project

```
lib/
├── main.dart                          # Entry point
├── models/
│   └── scan_history.dart             # Model lịch sử quét
├── screens/
│   ├── home_screen.dart              # Màn hình chính
│   ├── history_screen.dart           # Lịch sử quét
│   ├── webview_screen.dart           # WebView với location injection
│   └── location_demo_screen.dart     # Demo màn hình location
└── services/
    ├── history_service.dart          # Service lưu lịch sử
    └── location_service_manager.dart # Quản lý location dialog

web/
├── location_test.html                # Test HTML đầy đủ
└── simple_location_test.html         # Test HTML đơn giản
```

## Quyền truy cập cần thiết

### Android (android/app/src/main/AndroidManifest.xml)
```xml
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
<uses-permission android:name="android.permission.INTERNET" />
```

### iOS (ios/Runner/Info.plist)
```xml
<key>NSCameraUsageDescription</key>
<string>App cần quyền camera để quét mã QR</string>
<key>NSLocationWhenInUseUsageDescription</key>
<string>App cần quyền vị trí để chia sẻ với website</string>
```

## Troubleshooting

### 1. Không nhận được vị trí
- Kiểm tra quyền location đã được cấp
- Đảm bảo GPS/Location service đã bật
- Thử test ở ngoài trời hoặc gần cửa sổ

### 2. WebView không nhận được location
- Mở Developer Console trong WebView
- Kiểm tra `window.getLocation()` có return data không
- Đảm bảo WebView đã load xong trước khi gọi API

### 3. Camera không hoạt động
- Kiểm tra quyền camera
- Restart app sau khi cấp quyền
- Test trên device thật thay vì emulator

### 4. Build errors
```bash
# Clean và rebuild
flutter clean
flutter pub get
flutter run
```

## Dependencies chính

```yaml
dependencies:
  flutter_inappwebview: ^6.0.0          # WebView với JavaScript injection
  qr_code_scanner: ^3.0.1               # Quét QR code
  geolocator: ^10.1.0                   # GPS location
  permission_handler: ^11.3.1           # Quản lý quyền
  shared_preferences: ^2.2.2            # Lưu dữ liệu local
  http: ^1.1.0                          # HTTP requests
  qr_flutter: ^4.1.0                    # Generate QR code
```

## Liên hệ
Nếu có vấn đề khi chạy app, vui lòng check:
1. File `LOCATION_WEBVIEW_GUIDE.md` để hiểu rõ hơn về Location API
2. Console logs để debug
3. Quyền truy cập thiết bị
