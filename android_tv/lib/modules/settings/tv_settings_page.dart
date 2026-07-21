import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:player_shared/player_shared.dart';

import 'package:nexus_tv/app/controller/tv_settings_controller.dart';
import 'package:nexus_tv/app/theme/tv_theme.dart';
import 'package:nexus_tv/app/tv_focus_node.dart';
import 'package:nexus_tv/app/tv_style.dart';
import 'package:nexus_tv/widgets/tv_highlight.dart';

class TvSettingsPage extends StatefulWidget {
  const TvSettingsPage({super.key});

  @override
  State<TvSettingsPage> createState() => _TvSettingsPageState();
}

class _TvSettingsPageState extends State<TvSettingsPage>
    with WidgetsBindingObserver {
  /// null = 尚未查询完成；true/false = 查询结果。
  bool? _hasAllFilesAccess;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshAllFilesAccessStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 用户从"所有文件访问权限"系统设置页返回 App 时刷新一次状态。
    if (state == AppLifecycleState.resumed) {
      _refreshAllFilesAccessStatus();
    }
  }

  Future<void> _refreshAllFilesAccessStatus() async {
    if (!Platform.isAndroid) return;
    final granted = await PermissionUtil.hasAllFilesAccess();
    if (mounted) setState(() => _hasAllFilesAccess = granted);
  }

  Future<void> _onTapAllFilesAccess() async {
    if (_hasAllFilesAccess == true) {
      await PermissionUtil.openAppSettingsPage();
    } else {
      await PermissionUtil.requestAllFilesAccess();
    }
    await _refreshAllFilesAccessStatus();
  }

  @override
  Widget build(BuildContext context) {
    final settings = TvSettingsController.instance;

    return Obx(() => Scaffold(
      backgroundColor: TvColors.background,
      body: Row(
        children: [
          // Sidebar
          Container(
            width: 220.w,
            color: TvColors.surface,
            child: Column(
              children: [
                SizedBox(height: 32.w),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24.w),
                  child: Row(children: [
                    Text('设置', style: TvStyle.titleMedium),
                  ]),
                ),
              ],
            ),
          ),
          VerticalDivider(width: 1, color: TvColors.divider),
          // Content
          Expanded(
            child: ListView(
              padding: EdgeInsets.all(32.w),
              children: [
                _section('外观'),
                // 主题模式:跟随系统 / 浅色 / 深色
                _ThemeModeTile(settings: settings),
                SizedBox(height: 8.w),
                // 主题色选择
                Obx(() => _SelectTile(
                      label: '主题色',
                      subtitle: '',
                      icon: Icons.palette_outlined,
                      trailingColorDot: Color(settings.seedColor.value),
                      onTap: () => _showColorPicker(settings),
                    )),

                SizedBox(height: 24.w),
                _section('播放设置'),
                // 视频播放后端（本地视频）— Exo / MPV 二选一，独立于 IPTV 后端
                Obx(() => _SelectTile(
                      label: '视频播放后端',
                      subtitle: _backendLabel(
                          settings.playerBackend.value, isIptv: false),
                      icon: Icons.play_circle_outline,
                      onTap: () =>
                          _showBackendPicker(settings, isIptv: false),
                    )),
                SizedBox(height: 8.w),
                // IPTV 播放后端 — Exo / MPV 二选一，独立于本地视频后端
                Obx(() => _SelectTile(
                      label: 'IPTV 播放后端',
                      subtitle: _backendLabel(
                          settings.iptvBackend.value, isIptv: true),
                      icon: Icons.live_tv_outlined,
                      onTap: () =>
                          _showBackendPicker(settings, isIptv: true),
                    )),
                SizedBox(height: 8.w),
                // MPV 解码方式（硬解/软解）
                Obx(() {
                  final backend = settings.playerBackend.value;
                  if (backend == PlayerBackendChoice.exo) {
                    return _InfoTile(
                      label: 'MPV 解码方式',
                      subtitle: 'ExoPlayer 后端固定硬解，无需切换',
                      icon: Icons.memory_outlined,
                    );
                  }
                  return _SelectTile(
                    label: 'MPV 解码方式',
                    subtitle: settings.hardwareDecode.value
                        ? '硬件解码（GPU 解码，低 CPU）'
                        : '软件解码（兼容性更好）',
                    icon: Icons.memory_outlined,
                    onTap: () => _showHwDecodePicker(settings),
                  );
                }),
                SizedBox(height: 8.w),
                // Hardware decode（旧开关，保留兼容老用户的偏好读取，但 UI 上不再显示）
                // Compat mode
                Obx(() => _SwitchTile(
                      label: '兼容模式（Android TV）',
                      subtitle: '强制 MediaCodec Surface，解决部分机型花屏',
                      icon: Icons.tv,
                      value: settings.compatMode.value,
                      onChanged: settings.setCompatMode,
                    )),
                SizedBox(height: 8.w),
                // MPV profile
                Obx(() => _SelectTile(
                      label: '画质预设',
                      subtitle: _profileLabel(settings.mpvProfile.value),
                      icon: Icons.tune_outlined,
                      onTap: () => _showProfilePicker(settings),
                    )),

                SizedBox(height: 24.w),
                if (Platform.isAndroid) ...[
                  _section('存储权限'),
                  _SelectTile(
                    label: '外部存储权限（SD卡 / U盘）',
                    subtitle: _hasAllFilesAccess == null
                        ? '检测中…'
                        : _hasAllFilesAccess!
                            ? '已开启，可以扫描SD卡/U盘中的视频和音乐'
                            : '如果设备插了SD卡或U盘，需要开启此权限才能扫描到里面的视频/音乐',
                    icon: _hasAllFilesAccess == true
                        ? Icons.sd_storage
                        : Icons.sd_storage_outlined,
                    onTap: _onTapAllFilesAccess,
                  ),
                  SizedBox(height: 24.w),
                ],
                _section('IPTV 播放源'),
                Obx(() {
                  if (settings.iptvSources.isEmpty) {
                    return Padding(
                      padding: EdgeInsets.symmetric(vertical: 8.w),
                      child: Text('暂无保存的源',
                          style: TvStyle.labelSmall),
                    );
                  }
                  return Column(
                    children: settings.iptvSources
                        .asMap()
                        .entries
                        .map((e) => Padding(
                              padding: EdgeInsets.only(bottom: 6.w),
                              child: _InfoTile(
                                label: e.value['name'] ?? '',
                                subtitle: e.value['url'] ?? '',
                                icon: Icons.live_tv_outlined,
                                trailing: _DeleteBtn(
                                  onTap: () =>
                                      settings.removeIptvSource(e.key),
                                ),
                              ),
                            ))
                        .toList(),
                  );
                }),

                SizedBox(height: 24.w),
                _section('关于'),
                FutureBuilder<PackageInfo>(
                  future: PackageInfo.fromPlatform(),
                  builder: (_, snap) => _InfoTile(
                    label: 'Nexus TV',
                    subtitle: snap.hasData
                        ? 'v${snap.data!.version}'
                        : '',
                    icon: Icons.info_outline,
                  ),
                ),
                SizedBox(height: 8.w),
                _InfoTile(
                  label: '基于 media_kit (libmpv)',
                  subtitle: '支持几乎所有音视频格式',
                  icon: Icons.play_circle_outline,
                ),
                SizedBox(height: 32.w),
              ],
            ),
          ),
        ],
      ),
    ));
  }

  Widget _section(String title) => Padding(
        padding: EdgeInsets.only(bottom: 12.w, top: 4.w),
        child: Text(
          title,
          style: TvStyle.bodyMedium.copyWith(
            color: TvColors.primary,
            fontWeight: FontWeight.w600,
          ),
        ),
      );

  String _profileLabel(String p) {
    switch (p) {
      case 'performance': return '性能优先（低端设备推荐）';
      case 'quality':     return '画质优先（高端设备推荐）';
      default:            return '均衡（默认）';
    }
  }

  String _backendLabel(PlayerBackendChoice c, {required bool isIptv}) {
    switch (c) {
      case PlayerBackendChoice.exo:
        return isIptv
            ? 'ExoPlayer — 系统播放器，启动快'
            : 'ExoPlayer — 默认，本地视频硬解兼容性好';
      case PlayerBackendChoice.mpv:
        return isIptv
            ? 'MPV — 对 HLS/TS 直播流兼容性好（默认）'
            : 'MPV — 格式兼容性好，画质可调';
      // auto/vlc 在 Android TV 端 UI 不展示（onInit 已迁移），保留分支
      // 仅为类型安全，避免 exhaustive switch 约束。
      case PlayerBackendChoice.vlc:
        return 'VLC（仅 Windows 支持）';
      case PlayerBackendChoice.auto:
        return isIptv ? 'MPV' : 'ExoPlayer';
    }
  }

  /// 视频后端 / IPTV 后端共用的选择弹窗：只展示 Exo / MPV 两个选项。
  /// [isIptv] 决定读写的是 [TvSettingsController.iptvBackend] 还是
  /// [TvSettingsController.playerBackend]，两个后端独立设置。
  void _showBackendPicker(TvSettingsController settings,
      {required bool isIptv}) {
    // onInit 已迁移 auto/vlc，这里只提供 exo/mpv 两个可选值。
    final options = const [
      PlayerBackendChoice.exo,
      PlayerBackendChoice.mpv,
    ];
    final Rx<PlayerBackendChoice> current =
        isIptv ? settings.iptvBackend : settings.playerBackend;
    final ValueChanged<PlayerBackendChoice> setter = isIptv
        ? settings.setIptvBackend
        : settings.setPlayerBackend;
    final title = isIptv ? 'IPTV 播放后端' : '视频播放后端';
    showDialog(
      context: Get.context!,
      builder: (_) => AlertDialog(
        backgroundColor: TvColors.surface,
        title: Text(title, style: TvStyle.titleMedium),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: options.map((c) {
            final focus = TvFocusNode();
            return TvHighlight(
              focusNode: focus,
              autofocus: current.value == c,
              onTap: () {
                setter(c);
                Get.back();
              },
              borderRadius: TvStyle.radius8,
              child: Padding(
                padding: EdgeInsets.symmetric(
                    horizontal: 20.w, vertical: 16.w),
                child: Row(children: [
                  Expanded(
                      child: Text(_backendLabel(c, isIptv: isIptv),
                          style: TvStyle.bodyLarge)),
                  Obx(() => current.value == c
                      ? Icon(Icons.check,
                          color: TvColors.primary, size: 28.w)
                      : const SizedBox()),
                ]),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  void _showHwDecodePicker(TvSettingsController settings) {
    showDialog(
      context: Get.context!,
      builder: (_) => AlertDialog(
        backgroundColor: TvColors.surface,
        title: Text('MPV 解码方式', style: TvStyle.titleMedium),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHwOption(settings, true, '硬件解码', 'GPU 解码，CPU 占用低'),
            SizedBox(height: 8.w),
            _buildHwOption(settings, false, '软件解码', '兼容性更好'),
          ],
        ),
      ),
    );
  }

  Widget _buildHwOption(
      TvSettingsController settings, bool hw, String title, String subtitle) {
    final focus = TvFocusNode();
    return TvHighlight(
      focusNode: focus,
      autofocus: settings.hardwareDecode.value == hw,
      onTap: () {
        settings.setHardwareDecode(hw);
        Get.back();
      },
      borderRadius: TvStyle.radius8,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 16.w),
        child: Row(children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TvStyle.bodyLarge),
                Text(subtitle, style: TvStyle.labelSmall),
              ],
            ),
          ),
          Obx(() => settings.hardwareDecode.value == hw
              ? Icon(Icons.check, color: TvColors.primary, size: 28.w)
              : const SizedBox()),
        ]),
      ),
    );
  }

  void _showProfilePicker(TvSettingsController settings) {
    showDialog(
      context: Get.context!,
      builder: (_) => AlertDialog(
        backgroundColor: TvColors.surface,
        title: Text('画质预设', style: TvStyle.titleMedium),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: ['performance', 'balanced', 'quality'].map((p) {
            final focus = TvFocusNode();
            return TvHighlight(
              focusNode: focus,
              autofocus: settings.mpvProfile.value == p,
              onTap: () {
                settings.setMpvProfile(p);
                Get.back();
              },
              borderRadius: TvStyle.radius8,
              child: Padding(
                padding: EdgeInsets.symmetric(
                    horizontal: 20.w, vertical: 16.w),
                child: Row(children: [
                  Expanded(
                      child: Text(_profileLabel(p),
                          style: TvStyle.bodyLarge)),
                  Obx(() => settings.mpvProfile.value == p
                      ? Icon(Icons.check,
                          color: TvColors.primary, size: 28.w)
                      : const SizedBox()),
                ]),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  void _showColorPicker(TvSettingsController settings) {
    const colors = [
      Color(0xff3498db), // 默认蓝
      Color(0xff2ecc71), // 绿
      Color(0xffe74c3c), // 红
      Color(0xff9b59b6), // 紫
      Color(0xfff39c12), // 橙
      Color(0xff1abc9c), // 青
      Color(0xffe91e63), // 粉
      Color(0xff607d8b), // 蓝灰
    ];
    showDialog(
      context: Get.context!,
      builder: (_) => AlertDialog(
        backgroundColor: TvColors.surface,
        title: Text('选择主题色', style: TvStyle.titleMedium),
        content: SizedBox(
          width: 560.w,
          child: Wrap(
            spacing: 20.w,
            runSpacing: 20.w,
            children: colors.map((c) {
              final focus = TvFocusNode();
              return TvHighlight(
                focusNode: focus,
                autofocus: settings.seedColor.value == c.toARGB32(),
                onTap: () {
                  settings.setSeedColor(c);
                  Get.back();
                },
                borderRadius: BorderRadius.circular(100),
                child: Padding(
                  padding: EdgeInsets.all(6.w),
                  child: Obx(() => Container(
                        width: 56.w,
                        height: 56.w,
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                          border: settings.seedColor.value == c.toARGB32()
                              ? Border.all(color: Colors.white, width: 3.w)
                              : null,
                          boxShadow: [
                            BoxShadow(color: c.withAlpha(120), blurRadius: 10),
                          ],
                        ),
                        child: settings.seedColor.value == c.toARGB32()
                            ? Icon(Icons.check, color: Colors.white, size: 28.w)
                            : null,
                      )),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}

// ── Reusable tile widgets ────────────────────────────────────────────────

class _SwitchTile extends StatefulWidget {
  final String label, subtitle;
  final IconData icon;
  final bool value;
  final void Function(bool) onChanged;
  const _SwitchTile(
      {required this.label,
      required this.subtitle,
      required this.icon,
      required this.value,
      required this.onChanged});
  @override
  State<_SwitchTile> createState() => _SwitchTileState();
}

class _SwitchTileState extends State<_SwitchTile> {
  final _focus = TvFocusNode();
  @override
  void dispose() { _focus.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => TvHighlight(
        focusNode: _focus,
        onTap: () => widget.onChanged(!widget.value),
        borderRadius: TvStyle.radius8,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 16.w),
          child: Row(children: [
            Icon(widget.icon, color: TvColors.primary, size: 32.w),
            SizedBox(width: 16.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.label, style: TvStyle.bodyLarge),
                  Text(widget.subtitle, style: TvStyle.labelSmall),
                ],
              ),
            ),
            Switch(
              value: widget.value,
              onChanged: widget.onChanged,
              activeThumbColor: TvColors.primary,
            ),
          ]),
        ),
      );
}

class _SelectTile extends StatefulWidget {
  final String label, subtitle;
  final IconData icon;
  final VoidCallback? onTap;
  final Color? trailingColorDot;
  const _SelectTile(
      {required this.label,
      required this.subtitle,
      required this.icon,
      this.onTap,
      this.trailingColorDot});
  @override
  State<_SelectTile> createState() => _SelectTileState();
}

class _SelectTileState extends State<_SelectTile> {
  final _focus = TvFocusNode();
  @override
  void dispose() { _focus.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => TvHighlight(
        focusNode: _focus,
        onTap: widget.onTap,
        borderRadius: TvStyle.radius8,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 16.w),
          child: Row(children: [
            Icon(widget.icon, color: TvColors.primary, size: 32.w),
            SizedBox(width: 16.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.label, style: TvStyle.bodyLarge),
                  if (widget.subtitle.isNotEmpty)
                    Text(widget.subtitle, style: TvStyle.labelSmall),
                ],
              ),
            ),
            if (widget.trailingColorDot != null) ...[
              Container(
                width: 28.w,
                height: 28.w,
                decoration: BoxDecoration(
                  color: widget.trailingColorDot,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                        color: widget.trailingColorDot!.withAlpha(120),
                        blurRadius: 8),
                  ],
                ),
              ),
              SizedBox(width: 12.w),
            ],
            Icon(Icons.chevron_right, color: TvColors.textSecondary, size: 32.w),
          ]),
        ),
      );
}

/// 主题模式选择行:跟随系统 / 浅色 / 深色,三个选项横向排列可遥控器聚焦。
class _ThemeModeTile extends StatelessWidget {
  final TvSettingsController settings;
  const _ThemeModeTile({required this.settings});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 16.w),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.brightness_6_outlined, color: TvColors.primary, size: 32.w),
          SizedBox(width: 16.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('主题模式', style: TvStyle.bodyLarge),
                SizedBox(height: 10.w),
                Row(
                  children: [
                    _ThemeModeOption(
                      label: '跟随系统',
                      icon: Icons.brightness_auto,
                      mode: 0,
                      settings: settings,
                    ),
                    SizedBox(width: 12.w),
                    _ThemeModeOption(
                      label: '浅色',
                      icon: Icons.light_mode,
                      mode: 1,
                      settings: settings,
                    ),
                    SizedBox(width: 12.w),
                    _ThemeModeOption(
                      label: '深色',
                      icon: Icons.dark_mode,
                      mode: 2,
                      settings: settings,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ThemeModeOption extends StatefulWidget {
  final String label;
  final IconData icon;
  final int mode;
  final TvSettingsController settings;
  const _ThemeModeOption({
    required this.label,
    required this.icon,
    required this.mode,
    required this.settings,
  });
  @override
  State<_ThemeModeOption> createState() => _ThemeModeOptionState();
}

class _ThemeModeOptionState extends State<_ThemeModeOption> {
  final _focus = TvFocusNode();
  @override
  void dispose() { _focus.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final selected = widget.settings.themeMode.value == widget.mode;
      return TvHighlight(
        focusNode: _focus,
        selected: selected,
        onTap: () => widget.settings.setThemeMode(widget.mode),
        borderRadius: TvStyle.radius8,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 18.w, vertical: 10.w),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon,
                  size: 24.w,
                  color: selected ? Colors.white : TvColors.textSecondary),
              SizedBox(width: 8.w),
              Text(widget.label,
                  style: TvStyle.bodyMedium.copyWith(
                    color: selected ? Colors.white : TvColors.textSecondary,
                  )),
            ],
          ),
        ),
      );
    });
  }
}

class _InfoTile extends StatelessWidget {
  final String label, subtitle;
  final IconData icon;
  final Widget? trailing;
  final VoidCallback? onTap;
  const _InfoTile(
      {required this.label,
      required this.subtitle,
      required this.icon,
      this.trailing,
      this.onTap});
  @override
  Widget build(BuildContext context) {
    if (onTap == null && trailing == null) {
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 12.w),
        child: Row(children: [
          Icon(icon, color: TvColors.textSecondary, size: 28.w),
          SizedBox(width: 16.w),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TvStyle.bodyMedium),
                if (subtitle.isNotEmpty)
                  Text(subtitle,
                      style: TvStyle.labelSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ]),
      );
    }
    return _SelectableTile(
        label: label,
        subtitle: subtitle,
        icon: icon,
        trailing: trailing,
        onTap: onTap);
  }
}

class _SelectableTile extends StatefulWidget {
  final String label, subtitle;
  final IconData icon;
  final Widget? trailing;
  final VoidCallback? onTap;
  const _SelectableTile(
      {required this.label,
      required this.subtitle,
      required this.icon,
      this.trailing,
      this.onTap});
  @override
  State<_SelectableTile> createState() => _SelectableTileState();
}

class _SelectableTileState extends State<_SelectableTile> {
  final _focus = TvFocusNode();
  @override
  void dispose() { _focus.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => TvHighlight(
        focusNode: _focus,
        onTap: widget.onTap,
        borderRadius: TvStyle.radius8,
        child: Padding(
          padding:
              EdgeInsets.symmetric(horizontal: 24.w, vertical: 12.w),
          child: Row(children: [
            Icon(widget.icon, color: TvColors.textSecondary, size: 28.w),
            SizedBox(width: 16.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.label, style: TvStyle.bodyMedium),
                  if (widget.subtitle.isNotEmpty)
                    Text(widget.subtitle,
                        style: TvStyle.labelSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            if (widget.trailing != null) widget.trailing!,
          ]),
        ),
      );
}

class _DeleteBtn extends StatefulWidget {
  final VoidCallback? onTap;
  const _DeleteBtn({this.onTap});
  @override
  State<_DeleteBtn> createState() => _DeleteBtnState();
}

class _DeleteBtnState extends State<_DeleteBtn> {
  final _focus = TvFocusNode();
  @override
  void dispose() { _focus.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => TvHighlight(
        focusNode: _focus,
        onTap: widget.onTap,
        borderRadius: TvStyle.radius8,
        child: Padding(
          padding: EdgeInsets.all(8.w),
          child: Icon(Icons.delete_outline,
              color: Colors.redAccent, size: 28.w),
        ),
      );
}
