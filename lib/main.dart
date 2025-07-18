import 'package:flutter/material.dart';
import 'screens/home_screen.dart';
import 'services/location_permission_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Khởi tạo location permission manager
  final permissionResult = await LocationPermissionManager.initialize();
  
  runApp(MyApp(permissionResult: permissionResult));
}

class MyApp extends StatelessWidget {
  final String? permissionResult;
  
  const MyApp({super.key, this.permissionResult});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'QR Scanner',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: _AppWrapper(permissionResult: permissionResult),
      debugShowCheckedModeBanner: false, // Ẩn banner debug
    );
  }
}

class _AppWrapper extends StatefulWidget {
  final String? permissionResult;

  const _AppWrapper({Key? key, this.permissionResult}) : super(key: key);

  @override
  State<_AppWrapper> createState() => _AppWrapperState();
}

class _AppWrapperState extends State<_AppWrapper> with WidgetsBindingObserver {
  String? get permissionResult => widget.permissionResult;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    LocationPermissionManager.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // App được mở lại, khởi tạo lại LocationPermissionManager
      LocationPermissionManager.initialize();
    }
  }

  @override
  Widget build(BuildContext context) {
    return const HomeScreen();
  }
}