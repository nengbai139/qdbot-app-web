import 'package:flutter/material.dart';
import 'session.dart';
import 'app_nav.dart';
import 'ui/app_theme.dart';
import 'ui/app_theme_controller.dart';
import 'ui/login_page.dart';
import 'util/file_picker_init_stub.dart' if (dart.library.html) 'util/file_picker_init_web.dart';
import 'util/connectivity_init_stub.dart' if (dart.library.html) 'util/connectivity_init_web.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerFilePickerWeb();
  registerConnectivityWeb();
  await AppTheme.ensureFontsLoaded();
  runApp(const QDBotApp());
}

class QDBotApp extends StatefulWidget {
  const QDBotApp({super.key});

  @override
  State<QDBotApp> createState() => _QDBotAppState();
}

class _QDBotAppState extends State<QDBotApp> {
  ThemeMode _themeMode = ThemeMode.system;

  @override
  void initState() {
    super.initState();
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final mode = await loadSavedThemeMode();
    if (mounted) setState(() => _themeMode = mode);
  }

  Future<void> _setThemeMode(ThemeMode mode) async {
    await SessionStore.saveThemeModeRaw(themeModeToRaw(mode));
    if (mounted) setState(() => _themeMode = mode);
  }

  @override
  Widget build(BuildContext context) {
    return AppThemeController(
      themeMode: _themeMode,
      setThemeMode: _setThemeMode,
      child: MaterialApp(
        navigatorKey: rootNavigatorKey,
        title: 'QDBot App',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: _themeMode,
        home: const LoginPage(),
      ),
    );
  }
}
