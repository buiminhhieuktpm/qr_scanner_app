# Cập nhật luồng cấp quyền vị trí - QR Scanner App

## Tóm tắt các thay đổi

### 1. Tạo LocationPermissionManager mới
- **File**: `lib/services/location_permission_manager.dart`
- **Chức năng**: Quản lý luồng cấp quyền vị trí tự động theo yêu cầu:
  - **Android**: Mỗi lần mở app đều hỏi quyền nếu chưa có, và sau 30 phút nếu chưa có thì hỏi lại
  - **iOS**: Mỗi lần mở app đều kiểm tra quyền vị trí, nếu chưa cấp thì 30 phút sau hỏi lại bằng native (không hỏi liên tục), ưu tiên native permission

### 2. Cập nhật main.dart
- **File**: `lib/main.dart`
- **Thay đổi**:
  - Khởi tạo `LocationPermissionManager` khi app start
  - Thêm lifecycle management để handle khi app resume/pause
  - Cleanup resources khi app dispose

### 3. Cập nhật WebViewScreen
- **File**: `lib/screens/webview_screen.dart`
- **Thay đổi**:
  - Thay thế logic cũ bằng `LocationPermissionManager`
  - Xóa code native permission cũ
  - Đơn giản hóa logic kiểm tra quyền vị trí
  - Vẫn giữ nguyên location tracking và injection vào WebView

### 4. Cập nhật HomeScreen
- **File**: `lib/screens/home_screen.dart`
- **Thay đổi**:
  - Xóa import các màn hình test không cần thiết
  - Xóa các nút test quyền vị trí
  - Giữ nguyên logic quét QR và camera permission

### 5. Xóa các file test
- **Files đã xóa**:
  - `lib/screens/location_permission_test.dart`
  - `lib/screens/simple_location_test.dart`
  - Các file backup khác

## Logic hoạt động của LocationPermissionManager

### Khởi tạo
- Khi app mở, `LocationPermissionManager.initialize()` được gọi
- Kiểm tra quyền vị trí ngay lập tức theo platform
- Thiết lập timer định kỳ mỗi 30 phút

### Android
```
1. Mở app → Kiểm tra quyền vị trí
2. Nếu chưa có → Hỏi quyền ngay lập tức
3. Mỗi 30 phút → Kiểm tra lại và hỏi nếu chưa có
4. Sử dụng permission_handler
```

### iOS
```
1. Mở app → Kiểm tra quyền vị trí
2. Nếu chưa xác định → Hỏi bằng native iOS permission
3. Mỗi 30 phút → Kiểm tra lại và hỏi nếu chưa có
4. Ưu tiên native, fallback sang permission_handler
```

### Tính năng chính
- **Tự động**: Không cần tương tác thủ công
- **Thông minh**: Không hỏi liên tục nếu user đã từ chối
- **Đa nền tảng**: Logic khác nhau cho Android và iOS
- **Cleanup**: Tự động dọn dẹp resources khi app đóng

## Files quan trọng

1. **LocationPermissionManager**: `lib/services/location_permission_manager.dart`
2. **Main App**: `lib/main.dart`
3. **WebView**: `lib/screens/webview_screen.dart`
4. **Home**: `lib/screens/home_screen.dart`
5. **Native iOS**: `ios/Runner/AppDelegate.swift` (giữ nguyên)
6. **Native Service**: `lib/services/native_permission_service.dart` (giữ nguyên)

## Cách test

1. **Mở app lần đầu**: Sẽ hỏi quyền vị trí
2. **Từ chối quyền**: Sau 30 phút sẽ hỏi lại
3. **Đóng/mở app**: Luôn kiểm tra quyền vị trí
4. **WebView**: Vị trí sẽ được inject tự động nếu có quyền

## Lưu ý

- Quyền mạng cục bộ (Local Network) hoàn toàn tách biệt với quyền vị trí
- Native iOS permission vẫn hoạt động và được ưu tiên trên iOS
- Tất cả logic cũ đã được thay thế bằng LocationPermissionManager
- App sẽ không hỏi quyền liên tục nếu user đã từ chối

## Build và chạy

```bash
# Kiểm tra lỗi
flutter analyze

# Build iOS (cần certificate)
flutter build ios

# Build Android
flutter build apk

# Chạy debug
flutter run
```
