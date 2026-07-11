import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// QDBot 设计 token（Phase 0）
abstract final class AppTheme {
  static const brandBlue = Color(0xFF1677FF);
  static const bubbleOther = Color(0xFFF0F0F0);
  static const bubbleBot = Color(0xFFF3E8FF);
  static const bubbleOtherDark = Color(0xFF2C2C2E);
  static const bubbleBotDark = Color(0xFF3A2E48);

  static String? _sansScFamily;
  static List<String> _loadedFallback = const [];
  static bool _fontsReady = false;

  static const fontFallback = [
    'Noto Sans SC',
    'Noto Sans',
    'PingFang SC',
    'Microsoft YaHei',
    'Apple Color Emoji',
    'Segoe UI Emoji',
    'sans-serif',
  ];

  static Future<void> ensureFontsLoaded() async {
    try {
      // Web: bundled google_fonts/NotoSansSC-Regular.ttf; no gstatic fetch in CN.
      GoogleFonts.config.allowRuntimeFetching = !kIsWeb;
      final pending = <TextStyle>[GoogleFonts.notoSansSc()];
      if (!kIsWeb) pending.add(GoogleFonts.notoColorEmoji());
      await GoogleFonts.pendingFonts(pending);
      _sansScFamily = GoogleFonts.notoSansSc().fontFamily;
      _fontsReady = true;
      if (!kIsWeb) {
        final emoji = GoogleFonts.notoColorEmoji().fontFamily;
        _loadedFallback = emoji == null ? const [] : [emoji];
      }
    } catch (_) {
      // ponytail: fall back to system/CJK stack; never crash startup on missing asset
      _fontsReady = false;
      _sansScFamily = null;
    }
  }

  static List<String> get _effectiveFallback =>
      kIsWeb
          ? (_loadedFallback.isNotEmpty ? _loadedFallback : fontFallback)
          : (_loadedFallback.isNotEmpty ? _loadedFallback : fontFallback);

  static Color bubbleOtherFor(Brightness brightness) =>
      brightness == Brightness.dark ? bubbleOtherDark : bubbleOther;

  static Color bubbleBotFor(Brightness brightness) =>
      brightness == Brightness.dark ? bubbleBotDark : bubbleBot;

  static ThemeData light() => _base(Brightness.light);

  static ThemeData dark() => _base(Brightness.dark);

  static ThemeData _base(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(seedColor: brandBlue, brightness: brightness);
    final textTheme = _textTheme(brightness);
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      brightness: brightness,
      fontFamily: _fontFamily(),
      fontFamilyFallback: _effectiveFallback,
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      scaffoldBackgroundColor: brightness == Brightness.dark ? scheme.surface : Colors.grey.shade50,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: brightness == Brightness.dark ? scheme.surface : Colors.grey.shade50,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0.5,
      ),
      navigationBarTheme: NavigationBarThemeData(
        indicatorColor: brandBlue.withValues(alpha: 0.12),
        labelTextStyle: WidgetStateProperty.resolveWith((s) {
          final selected = s.contains(WidgetState.selected);
          return TextStyle(fontSize: 12, fontWeight: selected ? FontWeight.w600 : FontWeight.normal);
        }),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(backgroundColor: brandBlue),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
        ),
      ),
    );
  }

  static String? _fontFamily() => _fontsReady ? _sansScFamily : null;

  static TextTheme _textTheme(Brightness brightness) {
    final base = brightness == Brightness.dark ? ThemeData.dark().textTheme : ThemeData.light().textTheme;
    if (!_fontsReady) {
      return base.apply(fontFamilyFallback: fontFallback);
    }
    return GoogleFonts.notoSansScTextTheme(base).apply(fontFamilyFallback: _effectiveFallback);
  }
}
