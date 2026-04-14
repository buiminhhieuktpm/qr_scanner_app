# Authentication Persistence Solution

## Vấn đề đã được giải quyết
Trước đây khi đăng nhập xong tại tab tài khoản, sau đó thoát app và vào lại thì không giữ được trạng thái đăng nhập.

## Giải pháp đã triển khai

### 1. Enhanced GlobalCookieManager
Thêm các method chuyên biệt cho authentication:

#### a) `saveAuthenticationCookiesImmediately()`
- Lưu cookies authentication ngay lập tức với priority cao
- Tạo storage key riêng: `global_maqr_cookies_auth_immediate`
- Lưu timestamp để track thời gian

#### b) `syncAuthenticationState()`
- Đồng bộ auth state khi app restart
- Apply auth cookies cho tất cả URLs của maqr.vn
- Kiểm tra và skip cookies đã expired

#### c) `preloadAuthenticationOnStartup()`
- Preload authentication ngay khi app khởi động
- Load global cookies + sync auth state
- Check authentication status

#### d) `isLikelyAuthenticated()`
- Kiểm tra xem user có authenticated không
- Detect các cookie patterns: session, token, auth, login, user, jwt
- Verify cookies chưa expired

#### e) `forceCheckAndSaveAuthentication()`
- Force check và save auth state cho trang authentication
- Wait để đảm bảo cookies đã được set
- Verify rằng cookies đã được lưu thành công

### 2. WebViewScreen Improvements

#### a) App Lifecycle Management
- Implement `WidgetsBindingObserver` để listen app state changes
- `didChangeAppLifecycleState()`: 
  - Khi app vào background: auto-save cookies
  - Khi app resume: reload authentication state

#### b) Enhanced Cookie Detection
- `_detectAndSaveAuthenticationState()`: Auto-detect khi user login thành công
- Detect post-login navigation patterns
- Auto-save authentication cookies

#### c) Enhanced WebView Settings
```dart
incognito: false, // Quan trọng: Không dùng chế độ ẩn danh
sharedCookiesEnabled: true,
thirdPartyCookiesEnabled: true,
cacheEnabled: true,
clearCache: false,
```

#### d) Authentication-Aware Event Handlers
- `onLoadStop`: Force save auth cho authentication pages
- `onUpdateVisitedHistory`: Auto-detect và save auth state
- `dispose`: Force save auth cookies trước khi dispose

### 3. HomeScreen Initialization
- `_initializeApp()`: Preload authentication khi app khởi động
- Check authentication status và log kết quả
- Enhanced tab switching với auth state sync

## Luồng hoạt động mới

### Khi user đăng nhập:
1. **Page Load**: Authentication page được load
2. **Auto-Detection**: System detect đây là auth page
3. **Force Save**: `saveAuthenticationCookiesImmediately()` được gọi
4. **Verification**: Verify auth cookies đã được lưu
5. **State Update**: Update authentication state

### Khi app restart:
1. **Startup**: `preloadAuthenticationOnStartup()` được gọi
2. **Load Global**: Load global cookies
3. **Sync Auth**: Sync authentication state
4. **Apply Cookies**: Apply cookies cho tất cả maqr.vn URLs
5. **Verify**: Check authentication status

### Khi chuyển tab:
1. **Pre-Switch**: Sync cookies và auth state
2. **Auth Check**: Verify authentication status
3. **Load Cookies**: Load cookies cho tab mới
4. **Sync State**: Sync authentication state

### Khi app vào background:
1. **Auto-Save**: Auto-save tất cả cookies
2. **Force Auth Save**: Force save authentication cookies nếu là maqr.vn
3. **Persistence**: Đảm bảo cookies được lưu persistent

## Tính năng mới

### 1. Intelligent Auth Detection
- Detect authentication pages: taikhoan, account, login
- Detect post-login navigation: dashboard, home, main, profile
- Auto-save authentication cookies khi detect login thành công

### 2. Dual Cookie Storage
- **Global Storage**: Cho tất cả cookies
- **Auth Immediate Storage**: Riêng cho authentication cookies với priority cao

### 3. Authentication Verification
- Check authentication patterns trong cookie names
- Verify expiration dates
- Multiple verification points

### 4. Enhanced Logging
```
🔐 - Authentication related operations
🌐 - Global cookie operations
🔄 - Sync operations
✅ - Success operations
⚠️ - Warning states
❌ - Error states
```

## Logs để monitor

### Khi đăng nhập thành công:
```
🔐 Detected authentication page - force saving auth cookies
🔐 Force saving authentication cookies immediately...
✅ Saved 8 authentication cookies immediately
🔐 Authentication page loaded - force checking and saving auth
✅ Authentication verification: 8 cookies saved
```

### Khi app restart:
```
🌐 Initializing global cookies và authentication...
🚀 Pre-loading authentication on app startup...
🌐 Loading global cookies for maqr.vn...
🔄 Syncing authentication state...
✅ Applied 12 authentication cookies across 4 URLs
✅ App startup: User authenticated
```

### Khi chuyển tab:
```
🔄 Đồng bộ cookies trước khi chuyển tab từ 2 sang 1
🔄 Syncing authentication state...
✅ Applied 12 authentication cookies across 4 URLs
✅ Tab switch: User authenticated
```

## Testing Guide

### 1. Test Login Persistence
1. Đăng nhập tại tab "Tài khoản"
2. Verify logs show authentication cookies saved
3. Thoát app hoàn toàn (force quit)
4. Vào lại app
5. Check tab "Chính" - should be authenticated

### 2. Test Tab Switching
1. Đăng nhập tại tab "Tài khoản"
2. Chuyển sang tab "Chính"
3. Verify authentication state maintained

### 3. Test App Background/Resume
1. Đăng nhập
2. Send app to background
3. Wait và bring app back to foreground
4. Verify authentication maintained

## Troubleshooting

### Nếu vẫn mất authentication:
1. Check logs for authentication cookies being saved:
   ```
   🔐 Force saving authentication cookies immediately...
   ✅ Saved X authentication cookies immediately
   ```

2. Check authentication detection:
   ```
   ✅ App startup: User authenticated
   ✅ Tab switch: User authenticated
   ```

3. Verify cookie expiration:
   - Check if cookies có `expiresDate` hợp lệ
   - Authentication cookies thường có thời gian sống dài

4. Clear all cookies nếu cần reset:
   ```dart
   await _globalCookieManager.clearGlobalCookies();
   ```

## Performance Impact
- Minimal: Chỉ apply cho domain maqr.vn
- Smart detection: Chỉ save auth cookies khi cần
- Async operations: Không block UI
- Efficient storage: JSON với compression tốt
