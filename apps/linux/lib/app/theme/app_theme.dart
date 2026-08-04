import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppColors {
  static const Color defaultSeed = Color(0xff3498db);
}

class AppTheme {
  static const _font = 'Microsoft YaHei';

  static ThemeData light(int seedColorValue) {
    final seed   = Color(seedColorValue);
    final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.light);
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      fontFamily: _font,
      // Desktop benefits from slightly denser layout than Material default
      visualDensity: VisualDensity.comfortable,
      appBarTheme: const AppBarTheme(
        centerTitle: false,           // left-aligned titles on desktop
        elevation: 0,
        scrolledUnderElevation: 1,
        foregroundColor: Color(0xFF333333),
        systemOverlayStyle: SystemUiOverlayStyle.dark,
      ),
      // On desktop we use NavigationRail, not NavigationBar
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: scheme.surface,
        selectedIconTheme: IconThemeData(color: scheme.onPrimaryContainer),
        unselectedIconTheme: IconThemeData(color: scheme.onSurfaceVariant),
        indicatorColor: scheme.primaryContainer,
        labelType: NavigationRailLabelType.all,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: scheme.outlineVariant.withAlpha(80)),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbVisibility: WidgetStateProperty.all(true),
        thickness: WidgetStateProperty.all(6),
        radius: const Radius.circular(3),
      ),
    );
  }

  static ThemeData dark(int seedColorValue) {
    final seed   = Color(seedColorValue);
    final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark);
    final base   = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      colorScheme: scheme,
      textTheme: base.textTheme.apply(fontFamily: _font),
      visualDensity: VisualDensity.comfortable,
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 1,
        foregroundColor: Colors.white,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: scheme.surface,
        selectedIconTheme: IconThemeData(color: scheme.onPrimaryContainer),
        unselectedIconTheme: IconThemeData(color: scheme.onSurfaceVariant),
        indicatorColor: scheme.primaryContainer,
        labelType: NavigationRailLabelType.all,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: scheme.outlineVariant.withAlpha(60)),
        ),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbVisibility: WidgetStateProperty.all(true),
        thickness: WidgetStateProperty.all(6),
        radius: const Radius.circular(3),
      ),
    );
  }
}
