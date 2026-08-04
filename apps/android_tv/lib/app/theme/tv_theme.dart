import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// TV 默认主题色(与其它端保持一致的默认蓝色)。
const Color kTvDefaultSeed = Color(0xFF3498DB);

/// 可动态切换的 TV 配色。
///
/// 为了不用改动几乎所有页面里对 `TvColors.xxx` 的静态引用,这里把原先的
/// `static const` 颜色值改成了会随"主题色/主题模式"变化的响应式取值:
///   - 所有取值都通过 [_seed]/[_isDark] 的 Rx 状态计算得到;
///   - 页面里凡是包在 `Obx(...)` 里读取 `TvColors.xxx` 的地方,会在设置变更时
///     自动重新构建;不在 Obx 内的静态读取(如 build 方法顶层)则会在
///     该页面下次重建(如路由切换、setState)时拿到最新颜色。
/// 这样只需要在设置页调用 [TvColors.update] 即可全局生效,无需逐个文件重写。
class TvColors {
  static final Rx<Color> _seed = kTvDefaultSeed.obs;
  static final RxBool _isDark = true.obs;

  /// 由 TvSettingsController 在启动时 / 修改设置时调用。
  static void update({Color? seedColor, bool? isDark}) {
    if (seedColor != null) _seed.value = seedColor;
    if (isDark != null) _isDark.value = isDark;
  }

  static bool get isDark => _isDark.value;
  static Color get seed => _seed.value;

  // 深色模式基础色板(默认),浅色模式使用更亮的背景与深色文字。
  static Color get background => _isDark.value
      ? const Color(0xFF0F0F1A)
      : const Color(0xFFF2F3F7);
  static Color get surface => _isDark.value
      ? const Color(0xFF1C1C2E)
      : const Color(0xFFFFFFFF);
  static Color get card => _isDark.value
      ? const Color(0xFF252538)
      : const Color(0xFFFFFFFF);
  static Color get primary => _seed.value;
  static Color get primaryLight => Color.lerp(_seed.value, Colors.white, 0.3)!;
  static Color get accent => _isDark.value
      ? const Color(0xFF2ECC71)
      : const Color(0xFF27AE60);
  static Color get textPrimary =>
      _isDark.value ? Colors.white : const Color(0xFF1A1A2A);
  static Color get textSecondary => _isDark.value
      ? const Color(0xFFAAAAAA)
      : const Color(0xFF6B6B78);
  static Color get divider => _isDark.value
      ? const Color(0xFF2A2A3E)
      : const Color(0xFFE0E0E8);
  static const liveRed = Color(0xFFE74C3C);

  static List<BoxShadow> get focusShadow => [
        BoxShadow(
          color: _seed.value.withAlpha(0xBB),
          blurRadius: 20,
          spreadRadius: 2,
        ),
      ];
}

class TvTheme {
  /// 根据当前主题色 + 亮/暗模式生成 ThemeData。
  static ThemeData themeFor({required Color seedColor, required bool isDark}) {
    final brightness = isDark ? Brightness.dark : Brightness.light;
    final scheme = ColorScheme.fromSeed(seedColor: seedColor, brightness: brightness);
    final base = isDark
        ? ThemeData.dark(useMaterial3: true)
        : ThemeData.light(useMaterial3: true);
    return base.copyWith(
      colorScheme: scheme.copyWith(
        primary: seedColor,
        secondary: isDark ? const Color(0xFF2ECC71) : const Color(0xFF27AE60),
      ),
      scaffoldBackgroundColor:
          isDark ? const Color(0xFF0F0F1A) : const Color(0xFFF2F3F7),
      cardColor: isDark ? const Color(0xFF252538) : Colors.white,
      dividerColor: isDark ? const Color(0xFF2A2A3E) : const Color(0xFFE0E0E8),
      dialogTheme: DialogThemeData(
        backgroundColor: isDark ? const Color(0xFF1C1C2E) : Colors.white,
      ),
    );
  }

  /// 兼容旧引用:默认深色主题(默认蓝色种子)。
  static ThemeData get dark => themeFor(seedColor: kTvDefaultSeed, isDark: true);
}
