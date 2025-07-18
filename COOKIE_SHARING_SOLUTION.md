# Cookie Sharing Between Tabs Solution

## Vấn đề
Trước đây, khi đăng nhập ở tab "Tài khoản", cookies không được chia sẻ với tab "Chính" vì mỗi WebView có cookie storage riêng biệt.

## Giải pháp
Đã tạo `GlobalCookieManager` để đồng bộ cookies giữa tất cả WebView của domain `maqr.vn`.

## Cách hoạt động

### 1. GlobalCookieManager
- **File**: `lib/services/global_cookie_manager.dart`
- **Chức năng**: Quản lý cookies globally cho domain `maqr.vn`
- **Storage key**: `global_maqr_cookies`

### 2. Cookie Sync Strategy
```dart
// Khi save cookies
await saveCookies(url) {
  // Save local cookies
  // + Save to global storage if domain contains 'maqr.vn'
  if (domain.contains('maqr.vn')) {
    await _globalCookieManager.saveGlobalCookies();
  }
}

// Khi load cookies
await loadCookies(url) {
  // Load from global storage first if domain contains 'maqr.vn'
  if (domain.contains('maqr.vn')) {
    await _globalCookieManager.loadGlobalCookies();
  }
  // + Load local cookies
}
```

### 3. Tab Switching Sync
```dart
void _onItemTapped(int index) async {
  // Sync cookies before switching tabs
  await _globalCookieManager.syncCookiesAcrossWebViews();
  setState(() {
    _selectedIndex = index;
  });
}
```

## Luồng hoạt động

### Khi user đăng nhập ở tab "Tài khoản":
1. WebView tự động gọi `saveCookies()` sau khi page load
2. `saveCookies()` detect domain là `maqr.vn`
3. Lưu cookies vào global storage với key `global_maqr_cookies`
4. Cookies bao gồm session, login tokens, preferences, etc.

### Khi user chuyển sang tab "Chính":
1. `_onItemTapped()` được gọi
2. Tự động sync cookies bằng `syncCookiesAcrossWebViews()`
3. Load cookies từ global storage vào tất cả URLs của maqr.vn:
   - `https://maqr.vn`
   - `https://maqr.vn/vnptcheck/`
   - `https://maqr.vn/vnptcheck/#/app`
   - `https://maqr.vn/vnptcheck/#/taikhoan`

### Khi WebView tab "Chính" load:
1. `loadCookies()` được gọi trong `onWebViewCreated`
2. Load cookies từ global storage trước
3. Apply cookies vào WebView
4. User đã đăng nhập trên tab "Chính"

## Các tính năng

### 1. Automatic Sync
- Cookies tự động sync khi:
  - Page load hoàn thành
  - User chuyển tab
  - App khởi động

### 2. Cross-URL Coverage
Cookies được apply cho tất cả URLs của maqr.vn:
- Main app: `/vnptcheck/#/app`
- Account: `/vnptcheck/#/taikhoan`  
- Base domain: `maqr.vn`

### 3. Cookie Testing
```dart
await _globalCookieManager.testCookieSharing();
```
- Test tự động cookie sharing
- Verify cookies work across tabs

### 4. Debug Support
```dart
await _globalCookieManager.debugGlobalCookies();
```
- View all global cookies
- Monitor cookie sync status

## Kết quả

### ✅ Trước
- Đăng nhập ở tab "Tài khoản" ✅
- Chuyển sang tab "Chính" → Chưa đăng nhập ❌

### ✅ Sau  
- Đăng nhập ở tab "Tài khoản" ✅
- Chuyển sang tab "Chính" → Đã đăng nhập ✅
- Cookies được chia sẻ hoàn toàn ✅

## Logs để theo dõi

### Khi đăng nhập:
```
🌐 Lưu cookies vào global storage cho maqr.vn...
✅ Saved 5 global cookies
```

### Khi chuyển tab:
```
🔄 Đồng bộ cookies trước khi chuyển tab từ 2 sang 1
🌐 Bắt đầu đồng bộ cookies across WebViews...
✅ Loaded 15 global cookies across 4 URLs
```

### Khi load WebView:
```
🌐 Load cookies từ global storage cho maqr.vn...
✅ Loaded 5 global cookies
```

## Troubleshooting

### Nếu cookies vẫn không sync:
1. Check logs xem có `🌐` icons không
2. Verify domain detection: `domain.contains('maqr.vn')`
3. Run test: `await _globalCookieManager.testCookieSharing()`
4. Check global storage: `await _globalCookieManager.debugGlobalCookies()`

### Clear cookies nếu cần:
```dart
await _globalCookieManager.clearGlobalCookies();
```

## Performance Impact
- Minimal overhead: chỉ sync cho domain maqr.vn
- Async operations: không block UI
- Efficient storage: JSON compression
- Smart caching: chỉ sync khi cần thiết
