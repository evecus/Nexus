import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:nexus/app/tv_focus_node.dart';
import 'package:nexus/app/theme/tv_theme.dart';
import 'package:nexus/app/tv_style.dart';

typedef TvKeyCallback = KeyEventResult Function();

/// Universal focusable + remote-navigable widget for TV.
/// Wraps any child with:
///   - focus highlight (scale + blue glow)
///   - D-pad key routing (up/down/left/right/select/back)
///   - onTap for touch fallback
class TvHighlight extends StatelessWidget {
  final TvFocusNode focusNode;
  final Widget child;
  final bool autofocus;
  final bool selected;
  final VoidCallback? onTap;
  final TvKeyCallback? onUp;
  final TvKeyCallback? onDown;
  final TvKeyCallback? onLeft;
  final TvKeyCallback? onRight;
  final TvKeyCallback? onBack;
  final BorderRadius? borderRadius;
  final Color? color;
  final Color? focusedColor;
  final double scaleOnFocus;

  const TvHighlight({
    super.key,
    required this.focusNode,
    required this.child,
    this.autofocus = false,
    this.selected = false,
    this.onTap,
    this.onUp,
    this.onDown,
    this.onLeft,
    this.onRight,
    this.onBack,
    this.borderRadius,
    this.color,
    this.focusedColor,
    this.scaleOnFocus = 1.08,
  });

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: focusNode,
      autofocus: autofocus,
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.arrowUp)    return onUp?.call()    ?? KeyEventResult.ignored;
        if (key == LogicalKeyboardKey.arrowDown)  return onDown?.call()  ?? KeyEventResult.ignored;
        if (key == LogicalKeyboardKey.arrowLeft)  return onLeft?.call()  ?? KeyEventResult.ignored;
        if (key == LogicalKeyboardKey.arrowRight) return onRight?.call() ?? KeyEventResult.ignored;
        if (key == LogicalKeyboardKey.goBack ||
            key == LogicalKeyboardKey.escape)     return onBack?.call()  ?? KeyEventResult.ignored;
        if (key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.space) {
          onTap?.call();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: onTap,
        child: Obx(
          () => AnimatedScale(
            scale: focusNode.isFocused.value ? scaleOnFocus : 1.0,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              decoration: BoxDecoration(
                borderRadius: borderRadius ?? TvStyle.radius12,
                color: (focusNode.isFocused.value || selected)
                    ? (focusedColor ?? TvColors.primary.withAlpha(200))
                    : (color ?? Colors.transparent),
                boxShadow: focusNode.isFocused.value
                    ? TvColors.focusShadow
                    : null,
                border: focusNode.isFocused.value
                    ? Border.all(color: TvColors.primary, width: 2.w)
                    : null,
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// Large card button for TV home grid
class TvCardButton extends StatelessWidget {
  final TvFocusNode focusNode;
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool autofocus;
  final Color? iconColor;

  const TvCardButton({
    super.key,
    required this.focusNode,
    required this.icon,
    required this.label,
    this.onTap,
    this.autofocus = false,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return TvHighlight(
      focusNode: focusNode,
      autofocus: autofocus,
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 32.w, horizontal: 24.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Obx(() => Icon(
                  icon,
                  size: 64.w,
                  color: focusNode.isFocused.value
                      ? TvColors.textPrimary
                      : (iconColor ?? TvColors.primary),
                )),
            SizedBox(height: 16.w),
            Obx(() => Text(
                  label,
                  style: TvStyle.bodyMedium.copyWith(
                    color: focusNode.isFocused.value
                        ? TvColors.textPrimary
                        : TvColors.textSecondary,
                    fontWeight: focusNode.isFocused.value
                        ? FontWeight.w600
                        : FontWeight.normal,
                  ),
                )),
          ],
        ),
      ),
    );
  }
}

/// List tile for TV (channel / file list rows)
class TvListTile extends StatelessWidget {
  final TvFocusNode focusNode;
  final Widget? leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool autofocus;
  final TvKeyCallback? onUp;
  final TvKeyCallback? onDown;

  const TvListTile({
    super.key,
    required this.focusNode,
    required this.title,
    this.leading,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.autofocus = false,
    this.onUp,
    this.onDown,
  });

  @override
  Widget build(BuildContext context) {
    return TvHighlight(
      focusNode: focusNode,
      autofocus: autofocus,
      onTap: onTap,
      onUp: onUp,
      onDown: onDown,
      borderRadius: TvStyle.radius8,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 16.w),
        child: Row(
          children: [
            if (leading != null) ...[
              leading!,
              SizedBox(width: 20.w),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Obx(() => Text(
                        title,
                        style: TvStyle.bodyLarge.copyWith(
                          color: focusNode.isFocused.value
                              ? TvColors.textPrimary
                              : TvColors.textPrimary,
                          fontWeight: focusNode.isFocused.value
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      )),
                  if (subtitle != null) ...[
                    SizedBox(height: 4.w),
                    Text(subtitle!, style: TvStyle.labelSmall,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ],
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}
