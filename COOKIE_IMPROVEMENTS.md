# Cookie Management Improvements

## Tổng quan
Đã cải thiện hệ thống quản lý cookie trong WebViewScreen để hoạt động tốt hơn trên cả Android và iOS.

## Những cải thiện chính

### 1. Cookie Storage nâng cao
- **Trước**: Lưu cookie dạng string đơn giản với format `name=value`
- **Sau**: Lưu cookie dạng JSON với đầy đủ thông tin:
  ```json
  {
    "name": "cookie_name",
    "value": "cookie_value",
    "domain": "example.com",
    "path": "/",
    "secure": false,
    "httpOnly": false,
    "sameSite": "Lax",
    "expiresDate": 1642723200000
  }
  ```

### 2. Domain-specific Storage
- **Trước**: Tất cả cookies lưu chung với key `cookies`
- **Sau**: Cookies lưu theo domain với key `cookies_domain.com` để tránh conflict

### 3. WebView Settings Tối ưu
```dart
InAppWebViewSettings(
  // Cookie settings quan trọng
  sharedCookiesEnabled: true,
  thirdPartyCookiesEnabled: true,
  cacheEnabled: true,
  clearCache: false,
  
  // Storage settings
  domStorageEnabled: true,
  databaseEnabled: true,
  
  // Network settings
  mixedContentMode: MixedContentMode.MIXED_CONTENT_COMPATIBILITY_MODE,
  cacheMode: CacheMode.LOAD_DEFAULT,
  
  // User Agent tùy chỉnh
  userAgent: 'Mozilla/5.0... QRScannerApp/1.0',
)
```

### 4. Lifecycle Management
- **onWebViewCreated**: Load cookies và debug
- **onLoadStop**: Sync cookies, test functionality, xử lý vấn đề
- **onUpdateVisitedHistory**: Lưu cookies khi có thay đổi
- **dispose**: Lưu cookies cuối cùng

## Các tính năng mới

### 1. Cookie Synchronization
```dart
Future<void> syncCookies(Uri url) async
```
- Đồng bộ cookies giữa WebView và SharedPreferences
- Được gọi sau mỗi lần page load

### 2. Cookie Debugging
```dart
Future<void> debugCookies(Uri url) async
```
- Hiển thị chi tiết thông tin cookies
- Giúp debug các vấn đề cookie

### 3. Issue Handling
```dart
Future<void> handleCookieIssues(Uri url) async
```
- Tự động phát hiện và xử lý các vấn đề cookie:
  - Cookies rỗng
  - Third-party cookies
  - Secure cookies trên HTTP
  - Cookies hết hạn

### 4. Cookie Testing
```dart
Future<void> testCookieFunctionality(Uri url) async
```
- Test khả năng set/get cookies
- Xác minh cookie functionality hoạt động

### 5. Clear Cookies
```dart
Future<void> clearCookies(Uri url) async
```
- Clear cookies cả trên WebView và SharedPreferences
- Hữu ích khi cần reset session

## Cải thiện cho Android & iOS

### Android
- `databaseEnabled: true` - Bật Web SQL Database
- `domStorageEnabled: true` - Bật DOM storage
- `mixedContentMode: MIXED_CONTENT_COMPATIBILITY_MODE` - Cho phép mixed content

### iOS
- `allowsInlineMediaPlayback: true` - Tối ưu media playback
- `allowsAirPlayForMediaPlayback: true` - Hỗ trợ AirPlay
- `allowsLinkPreview: true` - Cho phép link preview

## Các vấn đề được giải quyết

### 1. Cookie Loss
- **Vấn đề**: Cookies bị mất khi restart app
- **Giải pháp**: Persistent storage với SharedPreferences + domain-specific keys

### 2. Third-party Cookies
- **Vấn đề**: Third-party cookies bị block
- **Giải pháp**: `thirdPartyCookiesEnabled: true` + proper handling

### 3. Expired Cookies
- **Vấn đề**: Cookies hết hạn không được xóa
- **Giải pháp**: Auto-detect và xóa cookies hết hạn

### 4. Secure Cookies on HTTP
- **Vấn đề**: Secure cookies không work trên HTTP
- **Giải pháp**: Warning và khuyến nghị chuyển HTTPS

## Sử dụng

### Load cookies
```dart
await loadCookies(uri);
```

### Save cookies
```dart
await saveCookies(uri);
```

### Sync cookies
```dart
await syncCookies(uri);
```

### Debug cookies
```dart
await debugCookies(uri);
```

### Clear cookies
```dart
await clearCookies(uri);
```

## Log Messages

Hệ thống có logging chi tiết để debug:
- `🍪` - Cookie operations
- `💾` - Save operations
- `📥` - Load operations
- `🔄` - Sync operations
- `🧪` - Test operations
- `🔧` - Issue handling
- `✅` - Success messages
- `❌` - Error messages
- `⚠️` - Warning messages

## Lưu ý
- Cookie functionality sẽ được test tự động mỗi lần page load
- Expired cookies được tự động xóa
- Hệ thống hoạt động với cả HTTP và HTTPS
- Hỗ trợ đầy đủ cho cả Android và iOS
