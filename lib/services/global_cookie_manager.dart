import 'dart:convert';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:shared_preferences/shared_preferences.dart';

class GlobalCookieManager {
  static final GlobalCookieManager _instance = GlobalCookieManager._internal();
  factory GlobalCookieManager() => _instance;
  GlobalCookieManager._internal();

  static const String _globalCookieKey = 'global_maqr_cookies';
  static const String _baseDomain = 'maqr.vn';

  // Lưu cookies globally cho domain maqr.vn
  Future<void> saveGlobalCookies() async {
    try {
      print('🌐 Saving global cookies for $_baseDomain...');

      final cookieManager = CookieManager.instance();
      // Đọc cookies từ tất cả các URL có thể chứa session maqr.vn
      final readUrls = [
        'https://maqr.vn',
        'https://maqr.vn/vnptcheck/',
        'https://maqr.vn/b/',
      ];
      final allCookies = <String, Map<String, dynamic>>{};
      for (final url in readUrls) {
        final cookies = await cookieManager.getCookies(url: WebUri(url));
        for (final cookie in cookies) {
          final key = '${cookie.name}_${cookie.domain ?? _baseDomain}';
          allCookies[key] = {
            'name': cookie.name,
            'value': cookie.value,
            'domain': cookie.domain ?? _baseDomain,
            'path': cookie.path ?? '/',
            'secure': cookie.isSecure ?? false,
            'httpOnly': cookie.isHttpOnly ?? false,
            'sameSite': cookie.sameSite?.toString() ?? 'Lax',
            'expiresDate': cookie.expiresDate,
          };
        }
      }

      if (allCookies.isEmpty) {
        print('⚠️ No cookies to save globally');
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      final cookieJson = jsonEncode(allCookies.values.toList());
      await prefs.setString(_globalCookieKey, cookieJson);

      print('✅ Saved ${allCookies.length} global cookies');
    } catch (e) {
      print('❌ Error saving global cookies: $e');
    }
  }

  // Load cookies globally cho tất cả WebView của domain maqr.vn
  Future<void> loadGlobalCookies() async {
    try {
      print('🌐 Loading global cookies for $_baseDomain...');
      
      final prefs = await SharedPreferences.getInstance();
      final cookieJson = prefs.getString(_globalCookieKey);
      
      if (cookieJson == null || cookieJson.isEmpty) {
        print('⚠️ No global cookies found');
        return;
      }
      
      final cookieManager = CookieManager.instance();
      final cookieList = jsonDecode(cookieJson) as List<dynamic>;
      
      // Apply cookies cho tất cả URLs của maqr.vn
      final urls = [
        'https://maqr.vn',
        'https://maqr.vn/vnptcheck/',
        'https://maqr.vn/vnptcheck/#/app',
        'https://maqr.vn/vnptcheck/#/taikhoan',
        'https://maqr.vn/b/',
        'https://maqr.vn/b/#/taikhoan',
        'https://maqr.vn/b/#/app',
      ];
      
      int loadedCount = 0;
      for (var url in urls) {
        for (var cookieData in cookieList) {
          try {
            final cookieMap = cookieData as Map<String, dynamic>;
            
            // Kiểm tra xem cookie có còn hạn không
            final expiresDate = cookieMap['expiresDate'] != null 
                ? DateTime.fromMillisecondsSinceEpoch(cookieMap['expiresDate'])
                : null;
            
            if (expiresDate != null && expiresDate.isBefore(DateTime.now())) {
              continue; // Skip expired cookies
            }
            
            await cookieManager.setCookie(
              url: WebUri(url),
              name: cookieMap['name'] ?? '',
              value: cookieMap['value'] ?? '',
              domain: cookieMap['domain'] ?? _baseDomain,
              path: cookieMap['path'] ?? '/',
              isSecure: cookieMap['secure'] ?? false,
              isHttpOnly: cookieMap['httpOnly'] ?? false,
              sameSite: _parseSameSite(cookieMap['sameSite']),
              expiresDate: expiresDate?.millisecondsSinceEpoch,
            );
            
            loadedCount++;
          } catch (e) {
            print('❌ Error loading individual cookie: $e');
          }
        }
      }
      
      print('✅ Loaded $loadedCount global cookies across ${urls.length} URLs');
    } catch (e) {
      print('❌ Error loading global cookies: $e');
    }
  }

  HTTPCookieSameSitePolicy? _parseSameSite(String? sameSite) {
    if (sameSite == null) return HTTPCookieSameSitePolicy.LAX;
    
    switch (sameSite.toLowerCase()) {
      case 'strict':
        return HTTPCookieSameSitePolicy.STRICT;
      case 'none':
        return HTTPCookieSameSitePolicy.NONE;
      case 'lax':
      default:
        return HTTPCookieSameSitePolicy.LAX;
    }
  }

  // Force save cookies ngay lập tức từ tất cả active WebViews
  Future<void> forceSaveAllCookies() async {
    try {
      print('🚨 Force saving cookies từ tất cả active WebViews...');
      
      final cookieManager = CookieManager.instance();
      final urls = [
        'https://maqr.vn',
        'https://maqr.vn/vnptcheck/',
        'https://maqr.vn/vnptcheck/#/app',
        'https://maqr.vn/vnptcheck/#/taikhoan',
        'https://maqr.vn/b/',
        'https://maqr.vn/b/#/taikhoan',
        'https://maqr.vn/b/#/app',
      ];
      
      // Lấy cookies từ tất cả URLs
      final allCookies = <Cookie>[];
      for (var url in urls) {
        try {
          final cookies = await cookieManager.getCookies(url: WebUri(url));
          allCookies.addAll(cookies);
          print('🍪 Lấy được ${cookies.length} cookies từ $url');
        } catch (e) {
          print('❌ Lỗi khi lấy cookies từ $url: $e');
        }
      }
      
      if (allCookies.isEmpty) {
        print('⚠️ Không có cookies để force save');
        return;
      }
      
      // Loại bỏ duplicates dựa trên name và domain
      final uniqueCookies = <String, Cookie>{};
      for (var cookie in allCookies) {
        final key = '${cookie.name}_${cookie.domain}';
        uniqueCookies[key] = cookie;
      }
      
      final prefs = await SharedPreferences.getInstance();
      final cookieList = <Map<String, dynamic>>[];
      
      for (var cookie in uniqueCookies.values) {
        // Chỉ lưu cookies còn hạn
        final expiresDate = cookie.expiresDate != null 
            ? DateTime.fromMillisecondsSinceEpoch(cookie.expiresDate!)
            : null;
        
        if (expiresDate != null && expiresDate.isBefore(DateTime.now())) {
          continue; // Skip expired cookies
        }
        
        cookieList.add({
          'name': cookie.name,
          'value': cookie.value,
          'domain': cookie.domain ?? _baseDomain,
          'path': cookie.path ?? '/',
          'secure': cookie.isSecure ?? false,
          'httpOnly': cookie.isHttpOnly ?? false,
          'sameSite': cookie.sameSite?.toString() ?? 'Lax',
          'expiresDate': cookie.expiresDate,
        });
      }
      
      final cookieJson = jsonEncode(cookieList);
      await prefs.setString(_globalCookieKey, cookieJson);
      
      print('🚨 Force saved ${cookieList.length} unique cookies');
      
      // Sync ngay lập tức để load lại cho tất cả WebViews
      await loadGlobalCookies();
      
    } catch (e) {
      print('❌ Error force saving cookies: $e');
    }
  }

  // Sync cookies giữa các WebView
  Future<void> syncCookiesAcrossWebViews() async {
    await saveGlobalCookies();
    await loadGlobalCookies();
  }

  // Clear tất cả global cookies
  Future<void> clearGlobalCookies() async {
    try {
      print('🗑️ Clearing all global cookies...');
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_globalCookieKey);
      
      final cookieManager = CookieManager.instance();
      await cookieManager.deleteAllCookies();
      
      print('✅ All global cookies cleared');
    } catch (e) {
      print('❌ Error clearing global cookies: $e');
    }
  }

  // Xóa toàn bộ cookies và storage khi đăng xuất
  Future<void> clearAllCookiesAndStorage() async {
    try {
      print('🗑️ [LOGOUT] Xóa toàn bộ cookies sau khi đăng xuất...');

      final prefs = await SharedPreferences.getInstance();
      // Xóa global cookie key
      await prefs.remove(_globalCookieKey);
      // Xóa các domain-specific cookie keys
      final keys = Set<String>.from(prefs.getKeys());
      for (final key in keys) {
        if (key.startsWith('cookies')) {
          await prefs.remove(key);
        }
      }

      // Xóa tất cả cookies trong WebView
      final cookieManager = CookieManager.instance();
      await cookieManager.deleteAllCookies();

      print('✅ [LOGOUT] Đã xóa toàn bộ cookies');
    } catch (e) {
      print('❌ [LOGOUT] Lỗi xóa cookies: $e');
    }
  }

  // Debug cookies
  Future<void> debugGlobalCookies() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cookieJson = prefs.getString(_globalCookieKey);
      
      if (cookieJson == null) {
        print('🍪 No global cookies stored');
        return;
      }
      
      final cookieList = jsonDecode(cookieJson) as List<dynamic>;
      print('🍪 Global Cookies ($_baseDomain):');
      print('   - Count: ${cookieList.length}');
      
      for (var cookieData in cookieList) {
        final cookieMap = cookieData as Map<String, dynamic>;
        final value = cookieMap['value']?.toString() ?? '';
        print('   - ${cookieMap['name']}: ${value.length > 50 ? '${value.substring(0, 50)}...' : value}');
      }
    } catch (e) {
      print('❌ Error debugging global cookies: $e');
    }
  }

  // Method để test cookie sharing giữa các tab
  Future<void> testCookieSharing() async {
    try {
      print('🧪 Testing cookie sharing giữa các tab...');
      
      final cookieManager = CookieManager.instance();
      final testCookieName = 'maqr_test_sharing_${DateTime.now().millisecondsSinceEpoch}';
      final testCookieValue = 'shared_value_${DateTime.now().millisecondsSinceEpoch}';
      
      // Set test cookie trên main URL
      await cookieManager.setCookie(
        url: WebUri('https://maqr.vn/vnptcheck/#/app'),
        name: testCookieName,
        value: testCookieValue,
        domain: 'maqr.vn',
        path: '/',
      );
      
      print('✅ Set test cookie: $testCookieName = $testCookieValue');
      
      // Save và sync
      await saveGlobalCookies();
      await loadGlobalCookies();
      
      // Check trên account URL
      final accountCookies = await cookieManager.getCookies(
        url: WebUri('https://maqr.vn/vnptcheck/#/taikhoan')
      );
      
      final foundCookie = accountCookies.firstWhere(
        (cookie) => cookie.name == testCookieName,
        orElse: () => Cookie(name: '', value: ''),
      );
      
      if (foundCookie.name.isNotEmpty && foundCookie.value == testCookieValue) {
        print('✅ Cookie sharing THÀNH CÔNG! Cookie đã được share giữa các tab');
      } else {
        print('❌ Cookie sharing THẤT BẠI! Cookie không được share');
      }
      
      // Clean up test cookie
      await cookieManager.deleteCookie(
        url: WebUri('https://maqr.vn'),
        name: testCookieName,
      );
      
    } catch (e) {
      print('❌ Lỗi khi test cookie sharing: $e');
    }
  }
}
