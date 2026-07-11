import 'package:flutter/material.dart';
import '../session.dart';

/// 全局外观切换（聊天偏好页可调）
class AppThemeController extends InheritedWidget {
  final ThemeMode themeMode;
  final Future<void> Function(ThemeMode mode) setThemeMode;

  const AppThemeController({
    super.key,
    required this.themeMode,
    required this.setThemeMode,
    required super.child,
  });

  static AppThemeController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppThemeController>();

  static ThemeMode themeModeOf(BuildContext context) =>
      maybeOf(context)?.themeMode ?? ThemeMode.system;

  static Future<void> setThemeModeOf(BuildContext context, ThemeMode mode) async {
    await maybeOf(context)?.setThemeMode(mode);
  }

  @override
  bool updateShouldNotify(AppThemeController oldWidget) => themeMode != oldWidget.themeMode;
}

ThemeMode themeModeFromRaw(String raw) {
  switch (raw) {
    case 'light':
      return ThemeMode.light;
    case 'dark':
      return ThemeMode.dark;
    default:
      return ThemeMode.system;
  }
}

String themeModeToRaw(ThemeMode mode) {
  switch (mode) {
    case ThemeMode.light:
      return 'light';
    case ThemeMode.dark:
      return 'dark';
    case ThemeMode.system:
      return 'system';
  }
}

String themeModeLabel(ThemeMode mode) {
  switch (mode) {
    case ThemeMode.light:
      return '浅色';
    case ThemeMode.dark:
      return '深色';
    case ThemeMode.system:
      return '跟随系统';
  }
}

Future<ThemeMode> loadSavedThemeMode() async =>
    themeModeFromRaw(await SessionStore.loadThemeModeRaw());
