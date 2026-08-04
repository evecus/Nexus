import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'theme/tv_theme.dart';

class TvStyle {
  // Gaps
  static SizedBox get vGap8  => SizedBox(height: 8.w);
  static SizedBox get vGap16 => SizedBox(height: 16.w);
  static SizedBox get vGap24 => SizedBox(height: 24.w);
  static SizedBox get vGap32 => SizedBox(height: 32.w);
  static SizedBox get vGap48 => SizedBox(height: 48.w);
  static SizedBox get hGap8  => SizedBox(width: 8.w);
  static SizedBox get hGap16 => SizedBox(width: 16.w);
  static SizedBox get hGap24 => SizedBox(width: 24.w);
  static SizedBox get hGap32 => SizedBox(width: 32.w);
  static SizedBox get hGap48 => SizedBox(width: 48.w);

  // Padding
  static EdgeInsets get padA24  => EdgeInsets.all(24.w);
  static EdgeInsets get padA32  => EdgeInsets.all(32.w);
  static EdgeInsets get padH48  => EdgeInsets.symmetric(horizontal: 48.w);
  static EdgeInsets get padV32  => EdgeInsets.symmetric(vertical: 32.w);
  static EdgeInsets get padH32V16 =>
      EdgeInsets.symmetric(horizontal: 32.w, vertical: 16.w);

  // Border radius
  static BorderRadius get radius8  => BorderRadius.circular(8.w);
  static BorderRadius get radius12 => BorderRadius.circular(12.w);
  static BorderRadius get radius16 => BorderRadius.circular(16.w);

  // Text styles
  static TextStyle get titleLarge => TextStyle(
        color: TvColors.textPrimary,
        fontSize: 40.sp,
        fontWeight: FontWeight.bold,
      );
  static TextStyle get titleMedium => TextStyle(
        color: TvColors.textPrimary,
        fontSize: 32.sp,
        fontWeight: FontWeight.w600,
      );
  static TextStyle get bodyLarge => TextStyle(
        color: TvColors.textPrimary,
        fontSize: 28.sp,
      );
  static TextStyle get bodyMedium => TextStyle(
        color: TvColors.textPrimary,
        fontSize: 24.sp,
      );
  static TextStyle get labelSmall => TextStyle(
        color: TvColors.textSecondary,
        fontSize: 20.sp,
      );
}
