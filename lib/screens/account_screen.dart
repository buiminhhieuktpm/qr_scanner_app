import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/global_cookie_manager.dart';

const String _accountUrl = 'https://maqr.vn/b/#/taikhoan';

class AccountScreen extends StatefulWidget {
  const AccountScreen({Key? key}) : super(key: key);

  @override
  AccountScreenState createState() => AccountScreenState();
}

class AccountScreenState extends State<AccountScreen>
    with WidgetsBindingObserver {
  InAppWebViewController? _webViewController;
  PullToRefreshController? _pullToRefreshController;
  Timer? _cookieSaveTimer;
  double _loadingProgress = 0.0;
  bool _isRefreshing = false;
  final GlobalCookieManager _globalCookieManager = GlobalCookieManager();

  // Gọi từ bên ngoài (double-tap tab) hoặc từ JS handler
  void reload() => _refresh();

  Future<void> _refresh() async {
    if (_isRefreshing || _webViewController == null) return;
    print('🔄 [ACCOUNT] Bắt đầu refresh...');
    if (mounted) setState(() => _isRefreshing = true);
    await _webViewController!.reload();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Khởi tạo PullToRefreshController riêng cho màn tài khoản
    _pullToRefreshController = PullToRefreshController(
      settings: PullToRefreshSettings(
        enabled: true,
        color: const Color(0xFF1565C0),
        backgroundColor: Colors.white,
      ),
      onRefresh: () async {
        print('🔄 [ACCOUNT] PullToRefreshController kích hoạt');
        await _refresh();
      },
    );

    _initializeCookies();
    _startPeriodicCookieSaving();
  }

  Future<void> _initializeCookies() async {
    try {
      print('🌐 [ACCOUNT] Khởi tạo global cookies...');
      await _globalCookieManager.loadGlobalCookies();
    } catch (e) {
      print('❌ [ACCOUNT] Lỗi khởi tạo cookies: $e');
    }
  }

  void _startPeriodicCookieSaving() {
    _cookieSaveTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _saveCookies();
    });
  }

  Future<void> _saveCookies() async {
    if (_webViewController == null) return;
    try {
      final uri = Uri.parse(_accountUrl);
      final cookieManager = CookieManager.instance();
      final cookies =
          await cookieManager.getCookies(url: WebUri(_accountUrl));
      final prefs = await SharedPreferences.getInstance();
      final cookieString =
          cookies.map((c) => '${c.name}=${c.value}').join(';');
      await prefs.setString('cookies', cookieString);
      print('🍪 [ACCOUNT] Đã lưu ${cookies.length} cookies');

      if (uri.host.contains('maqr.vn')) {
        await _globalCookieManager.saveGlobalCookies();
      }
    } catch (e) {
      print('❌ [ACCOUNT] Lỗi lưu cookies: $e');
    }
  }

  Future<void> _loadCookies() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cookieString = prefs.getString('cookies');
      if (cookieString != null && cookieString.isNotEmpty) {
        final cookieManager = CookieManager.instance();
        for (var cookie in cookieString.split(';')) {
          final parts = cookie.split('=');
          if (parts.length >= 2) {
            final name = parts[0].trim();
            final value = parts.sublist(1).join('=').trim();
            if (name.isNotEmpty) {
              await cookieManager.setCookie(
                url: WebUri(_accountUrl),
                name: name,
                value: value,
                domain: 'maqr.vn',
                path: '/',
                isSecure: true,
                isHttpOnly: false,
                sameSite: HTTPCookieSameSitePolicy.NONE,
              );
            }
          }
        }
        print('🍪 [ACCOUNT] Đã load cookies');
      }
    } catch (e) {
      print('❌ [ACCOUNT] Lỗi load cookies: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        _saveCookies();
        break;
      case AppLifecycleState.resumed:
        _loadCookies();
        break;
      default:
        break;
    }
  }

  Future<bool> _handleSpecialScheme(String url) async {
    final uri = Uri.parse(url);
    try {
      switch (uri.scheme.toLowerCase()) {
        case 'tel':
        case 'sms':
        case 'mailto':
          return await launchUrl(uri);
        case 'zalo':
        case 'fb':
        case 'facebook':
        case 'whatsapp':
        case 'viber':
        case 'market':
        case 'play':
          return await launchUrl(uri, mode: LaunchMode.externalApplication);
        case 'intent':
          if (url.contains('S.browser_fallback_url=')) {
            final match =
                RegExp(r'S\.browser_fallback_url=([^;]+)').firstMatch(url);
            if (match != null) {
              final fallbackUrl = Uri.decodeComponent(match.group(1)!);
              await _webViewController?.loadUrl(
                  urlRequest: URLRequest(url: WebUri(fallbackUrl)));
              return true;
            }
          }
          return false;
        default:
          if (uri.scheme != 'http' &&
              uri.scheme != 'https' &&
              uri.scheme != 'file' &&
              uri.scheme != 'data') {
            return await launchUrl(uri, mode: LaunchMode.externalApplication);
          }
          return false;
      }
    } catch (e) {
      print('❌ [ACCOUNT] Lỗi xử lý scheme $url: $e');
      return false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cookieSaveTimer?.cancel();
    _pullToRefreshController?.dispose();
    _saveCookies();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        InAppWebView(
          pullToRefreshController: _pullToRefreshController,
          initialUrlRequest: URLRequest(url: WebUri(_accountUrl)),
          initialSettings: InAppWebViewSettings(
            cacheEnabled: false,
            clearCache: true,
            sharedCookiesEnabled: true,
            thirdPartyCookiesEnabled: true,
            domStorageEnabled: true,
            databaseEnabled: true,
            mixedContentMode:
                MixedContentMode.MIXED_CONTENT_COMPATIBILITY_MODE,
            allowsInlineMediaPlayback: true,
            supportZoom: true,
            mediaPlaybackRequiresUserGesture: false,
            useOnLoadResource: true,
            disableDefaultErrorPage: false,
            allowsLinkPreview: true,
            cacheMode: CacheMode.LOAD_NO_CACHE,
            applicationNameForUserAgent: 'QRScannerApp/1.0',
            userAgent:
                'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Mobile Safari/537.36 QRScannerApp/1.0',
            transparentBackground: false,
            // Bỏ useHybridComposition:true → Android PullToRefresh hoạt động
            // disallowOverScroll:false → iOS UIRefreshControl hoạt động
            disallowOverScroll: false,
          ),
          onWebViewCreated: (controller) async {
            _webViewController = controller;
            print('🌐 [ACCOUNT] WebView được tạo, đang load cookies...');
            await _loadCookies();
          },
          onLoadStart: (controller, url) {
            print('📄 [ACCOUNT] Bắt đầu load: $url');
            setState(() => _loadingProgress = 0.0);
          },
          onProgressChanged: (controller, progress) {
            setState(() => _loadingProgress = progress / 100);
          },
          onLoadStop: (controller, url) async {
            print('✅ [ACCOUNT] Load xong: $url');
            _pullToRefreshController?.endRefreshing();
            if (mounted) setState(() { _loadingProgress = 1.0; _isRefreshing = false; });
            await _saveCookies();
            // Inject JS để detect pull-to-refresh gesture trên trang SPA
            await _injectPullToRefreshJS(controller);
          },
          onReceivedError: (controller, request, error) async {
            print('❌ [ACCOUNT] Lỗi WebView: ${error.description}');
            _pullToRefreshController?.endRefreshing();
            if (mounted) setState(() { _loadingProgress = 1.0; _isRefreshing = false; });
            if (mounted) {
              String msg = 'Lỗi tải trang';
              if (error.description.contains('ERR_INTERNET_DISCONNECTED')) {
                msg = 'Không có kết nối internet';
              } else if (error.description.contains('ERR_CONNECTION_REFUSED')) {
                msg = 'Không thể kết nối đến máy chủ';
              } else if (error.description.contains('ERR_CONNECTION_TIMED_OUT')) {
                msg = 'Kết nối bị timeout';
              } else {
                msg = 'Lỗi: ${error.description}';
              }
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(msg),
                  action: SnackBarAction(
                    label: 'Thử lại',
                    onPressed: () => controller.reload(),
                  ),
                  duration: const Duration(seconds: 5),
                ),
              );
            }
          },
          onUpdateVisitedHistory: (controller, url, _) async {
            if (url != null) await _saveCookies();
          },
          shouldOverrideUrlLoading: (controller, navigationAction) async {
            final url = navigationAction.request.url.toString();
            final uri = Uri.parse(url);
            if (uri.scheme != 'http' && uri.scheme != 'https') {
              final handled = await _handleSpecialScheme(url);
              if (handled) return NavigationActionPolicy.CANCEL;
            }
            return NavigationActionPolicy.ALLOW;
          },
          onConsoleMessage: (controller, consoleMessage) {
            print('🌐 [ACCOUNT-WEB] ${consoleMessage.messageLevel}: ${consoleMessage.message}');
          },
        ),
          // Progress bar - dùng IgnorePointer để không chặn gesture
          if (_loadingProgress < 1.0)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: LinearProgressIndicator(
                  value: _loadingProgress,
                  backgroundColor: Colors.grey[200],
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(Color(0xFF1565C0)),
                ),
              ),
            ),
          // Hiển thị spinner khi đang refresh
          if (_isRefreshing)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  color: Colors.transparent,
                  alignment: Alignment.topCenter,
                  child: const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF1565C0)),
                    ),
                  ),
                ),
              ),
            ),
      ],
    );
  }

  /// Inject JavaScript vào trang để phát hiện gesture kéo xuống ngay cả khi
  /// trang dùng layout cố định (SPA) khiến native UIRefreshControl không hoạt động.
  Future<void> _injectPullToRefreshJS(InAppWebViewController controller) async {
    try {
      await controller.evaluateJavascript(source: '''
        (function() {
          if (window.__pullToRefreshInjected) return;
          window.__pullToRefreshInjected = true;

          var startY = -1;
          var startX = -1;
          var triggered = false;
          var threshold = 65; // px kéo xuống để trigger

          // Tìm phần tử scroll đầu tiên hoặc dùng document
          function getScrollTop() {
            var els = document.querySelectorAll('*');
            for (var i = 0; i < els.length; i++) {
              var el = els[i];
              var st = window.getComputedStyle(el);
              if ((st.overflowY === 'auto' || st.overflowY === 'scroll') &&
                  el.scrollHeight > el.clientHeight) {
                return el.scrollTop;
              }
            }
            return window.scrollY || 0;
          }

          document.addEventListener('touchstart', function(e) {
            startY = e.touches[0].clientY;
            startX = e.touches[0].clientX;
            triggered = false;
          }, {passive: true});

          document.addEventListener('touchmove', function(e) {
            if (triggered || startY < 0) return;
            var dy = e.touches[0].clientY - startY;
            var dx = Math.abs(e.touches[0].clientX - startX);
            // Kéo xuống đủ ngưỡng, chủ yếu theo chiều dọc,
            // và đang ở đầu trang (scroll == 0)
            if (dy > threshold && dx < 40 && getScrollTop() === 0) {
              triggered = true;
              window.flutter_inappwebview.callHandler('onCustomPullToRefresh');
            }
          }, {passive: true});

          console.log('[ACCOUNT] Pull-to-refresh JS injected');
        })();
      ''');
      print('✅ [ACCOUNT] Đã inject pull-to-refresh JS');
    } catch (e) {
      print('❌ [ACCOUNT] Lỗi inject JS: \$e');
    }
  }
}
