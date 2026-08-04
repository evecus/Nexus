import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:player_shared/player_shared.dart';

import 'package:nexus/app/controller/app_settings_controller.dart';
import 'package:nexus/modules/video/local/video_library_page.dart';
import 'package:nexus/modules/music/library/music_library_page.dart';
import 'package:nexus/widgets/scan_progress_dialog.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> with WidgetsBindingObserver {
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
    // 用户从"所有文件访问权限"系统设置页返回 App 时，刷新一次状态，
    // 这样设置页里的开关文案能及时反映最新的授权结果，不需要手动退出
    // 重进设置页。
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
      // 已经开启：点击直接跳转系统设置，方便用户查看/关闭。
      await PermissionUtil.openAppSettingsPage();
    } else {
      await PermissionUtil.requestAllFilesAccess();
    }
    await _refreshAllFilesAccessStatus();
  }

  /// 触发"扫描视频"：弹出扫描进度弹窗，同时异步执行视频库的重新扫描，
  /// 扫描过程中每发现一个视频就往弹窗追加一行，扫描结束后弹窗按钮变为
  /// 可点击的"确定"，点击后关闭。
  Future<void> _scanVideos(BuildContext context) async {
    if (!Get.isRegistered<VideoLibraryController>(tag: 'video_library')) {
      // 理论上视频页作为首页四个 Tab 之一在 IndexedStack 中始终常驻，
      // 这里只是防御性兜底（例如极端情况下页面尚未完成首次 build）。
      return;
    }
    final ctrl =
        Get.find<VideoLibraryController>(tag: 'video_library');
    final progress = ScanProgressController();
    final future = showScanProgressDialog(
      context,
      title: '扫描视频',
      controller: progress,
    );
    ctrl
        .rescan(onFound: (name) => progress.appendLine(name))
        .whenComplete(progress.complete);
    await future;
    progress.dispose();
  }

  /// 触发"扫描音乐"，逻辑与 [_scanVideos] 对称。
  Future<void> _scanMusic(BuildContext context) async {
    if (!Get.isRegistered<MusicLibraryController>(tag: 'music_library')) {
      return;
    }
    final ctrl =
        Get.find<MusicLibraryController>(tag: 'music_library');
    final progress = ScanProgressController();
    final future = showScanProgressDialog(
      context,
      title: '扫描音乐',
      controller: progress,
    );
    ctrl
        .rescan(onFound: (name) => progress.appendLine(name))
        .whenComplete(progress.complete);
    await future;
    progress.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = AppSettingsController.instance;

    return Scaffold(
      body: SafeArea(
        child: ListView(
        children: [
          // ── 外观 ────────────────────────────────────────────────
          _sectionHeader(context, '外观'),
          Obx(() => Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.brightness_6_outlined),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('主题模式'),
                          const SizedBox(height: 10),
                          SegmentedButton<int>(
                            segments: const [
                              ButtonSegment(value: 0, label: Text('跟随系统')),
                              ButtonSegment(
                                  value: 1,
                                  icon: Icon(Icons.light_mode),
                                  label: Text('浅色')),
                              ButtonSegment(
                                  value: 2,
                                  icon: Icon(Icons.dark_mode),
                                  label: Text('深色')),
                            ],
                            selected: {settings.themeMode.value},
                            onSelectionChanged: (s) =>
                                settings.setThemeMode(s.first),
                            style: const ButtonStyle(
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              )),
          ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: const Text('主题色'),
            trailing: Obx(() => _ColorDot(color: Color(settings.seedColor.value))),
            onTap: () => _showColorPicker(context, settings),
          ),

          // ── 播放 ────────────────────────────────────────────────
          _sectionHeader(context, '播放'),
          // 视频播放后端（本地视频）— Exo / MPV 二选一，独立于 IPTV 后端
          Obx(() => _backendSelector(
                context: context,
                label: '视频播放后端',
                icon: Icons.play_circle_outline,
                value: settings.playerBackend.value,
                onChanged: settings.setPlayerBackend,
                subtitle: _backendLabel(
                    settings.playerBackend.value, isIptv: false),
              )),
          // IPTV 播放后端 — Exo / MPV 二选一，独立于本地视频后端
          Obx(() => _backendSelector(
                context: context,
                label: 'IPTV 播放后端',
                icon: Icons.live_tv_outlined,
                value: settings.iptvBackend.value,
                onChanged: settings.setIptvBackend,
                subtitle: _backendLabel(
                    settings.iptvBackend.value, isIptv: true),
              )),
          // MPV 解码方式（硬解/软解）— 仅在选择 MPV 相关时才有意义
          Obx(() {
            // ExoPlayer 后端固定硬解，无需此选项
            final backend = settings.playerBackend.value;
            final showHwDecSwitch = backend != PlayerBackendChoice.exo;
            if (!showHwDecSwitch) {
              return ListTile(
                leading: const Icon(Icons.memory_outlined),
                title: const Text('MPV 解码方式'),
                subtitle: const Text('ExoPlayer 后端固定硬件解码，无需切换'),
                enabled: false,
              );
            }
            return ListTile(
              leading: const Icon(Icons.memory_outlined),
              title: const Text('MPV 解码方式'),
              subtitle: const Text('硬解：GPU 解码低 CPU；软解：兼容性更好'),
              trailing: SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 1, label: Text('硬解')),
                  ButtonSegment(value: 0, label: Text('软解')),
                ],
                selected: {settings.hardwareDecode.value ? 1 : 0},
                onSelectionChanged: (s) =>
                    settings.setHardwareDecode(s.first == 1),
                style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                ),
              ),
            );
          }),
          if (Platform.isAndroid)
            Obx(() => SwitchListTile(
                  secondary: const Icon(Icons.android_outlined),
                  title: const Text('兼容模式（Android）'),
                  subtitle: const Text('强制使用 MediaCodec Surface，解决部分机型花屏问题'),
                  value: settings.compatMode.value,
                  onChanged: settings.setCompatMode,
                )),
          Obx(() => ListTile(
                leading: const Icon(Icons.tune_outlined),
                title: const Text('画质预设'),
                subtitle: Text(_profileLabel(settings.mpvProfile.value)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _showProfilePicker(context, settings),
              )),

          // ── 存储权限 ────────────────────────────────────────────
          if (Platform.isAndroid) ...[
            _sectionHeader(context, '存储权限'),
            ListTile(
              leading: Icon(
                _hasAllFilesAccess == true
                    ? Icons.sd_storage
                    : Icons.sd_storage_outlined,
              ),
              title: const Text('外部存储权限（SD卡 / U盘）'),
              subtitle: Text(
                _hasAllFilesAccess == null
                    ? '检测中…'
                    : _hasAllFilesAccess!
                        ? '已开启，可以扫描SD卡/U盘中的视频和音乐'
                        : '如果你的设备插了SD卡或U盘，需要开启此权限才能扫描到里面的视频/音乐',
              ),
              trailing: _hasAllFilesAccess == true
                  ? const Icon(Icons.check_circle, color: Colors.green)
                  : const Icon(Icons.chevron_right),
              onTap: _onTapAllFilesAccess,
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Text(
                '仅使用手机/平板内部存储的视频音乐无需开启此项，普通媒体权限已在启动时自动申请。',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ),
          ],

          // ── 媒体扫描 ────────────────────────────────────────────
          _sectionHeader(context, '媒体扫描'),
          ListTile(
            leading: const Icon(Icons.video_library_outlined),
            title: const Text('扫描视频'),
            subtitle: const Text('重新扫描设备中的本地视频（原视频页"刷新"）'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _scanVideos(context),
          ),
          ListTile(
            leading: const Icon(Icons.music_note_outlined),
            title: const Text('扫描音乐'),
            subtitle: const Text('重新扫描设备中的本地音乐（原音乐页"刷新"）'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _scanMusic(context),
          ),

          // ── 关于 ────────────────────────────────────────────────
          _sectionHeader(context, '关于'),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('Nexus'),
            trailing: FutureBuilder<PackageInfo>(
              future: PackageInfo.fromPlatform(),
              builder: (_, snap) => Text(
                snap.hasData ? 'v${snap.data!.version}' : '',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.code_outlined),
            title: const Text('基于 media_kit (libmpv)'),
            subtitle: const Text('支持几乎所有音视频格式'),
          ),

          const SizedBox(height: 32),
        ],
        ),
      ),
    );
  }

  Widget _sectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
      ),
    );
  }

  String _profileLabel(String profile) {
    switch (profile) {
      case 'performance':
        return '性能优先（低端设备推荐）';
      case 'quality':
        return '画质优先（高端设备推荐）';
      default:
        return '均衡（默认）';
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
      // auto/vlc 在 Android 端 UI 不展示（onInit 已迁移），保留分支
      // 仅为类型安全，避免 exhaustive switch 约束。
      case PlayerBackendChoice.vlc:
        return 'VLC（仅 Windows 支持）';
      case PlayerBackendChoice.auto:
        return isIptv ? 'MPV' : 'ExoPlayer';
    }
  }

  /// 视频播放后端 / IPTV 播放后端共用的选择器：Exo / MPV 两个选项。
  /// 两个后端独立设置，互不影响。
  Widget _backendSelector({
    required BuildContext context,
    required String label,
    required IconData icon,
    required PlayerBackendChoice value,
    required ValueChanged<PlayerBackendChoice> onChanged,
    required String subtitle,
  }) {
    // 防御：onInit 已迁移 auto/vlc 为 exo/mpv，但若存储出现异常值，
    // 这里把非 exo/mpv 的值映射成 Exo，避免 SegmentedButton 因 selected
    // 集合不在 segments 中而断言失败。
    final display = (value == PlayerBackendChoice.exo ||
            value == PlayerBackendChoice.mpv)
        ? value
        : PlayerBackendChoice.exo;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 10),
                SegmentedButton<PlayerBackendChoice>(
                  segments: const [
                    ButtonSegment(
                        value: PlayerBackendChoice.exo, label: Text('Exo')),
                    ButtonSegment(
                        value: PlayerBackendChoice.mpv, label: Text('MPV')),
                  ],
                  selected: {display},
                  onSelectionChanged: (s) => onChanged(s.first),
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showProfilePicker(BuildContext context, AppSettingsController settings) {
    showModalBottomSheet(
      context: context,
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child:
                Text('画质预设', style: Theme.of(context).textTheme.titleMedium),
          ),
          Obx(() => RadioGroup<String>(
                groupValue: settings.mpvProfile.value,
                onChanged: (String? v) {
                  if (v != null) settings.setMpvProfile(v);
                  Navigator.pop(context);
                },
                child: Column(
                  children: ['performance', 'balanced', 'quality']
                      .map((p) => RadioListTile<String>(
                            title: Text(_profileLabel(p)),
                            value: p,
                          ))
                      .toList(),
                ),
              )),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  void _showColorPicker(BuildContext context, AppSettingsController settings) {
    const colors = [
      Color(0xff3498db), // default blue
      Color(0xff2ecc71), // green
      Color(0xffe74c3c), // red
      Color(0xff9b59b6), // purple
      Color(0xfff39c12), // orange
      Color(0xff1abc9c), // teal
      Color(0xffe91e63), // pink
      Color(0xff607d8b), // blue grey
    ];
    showModalBottomSheet(
      context: context,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('选择主题色', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: colors
                  .map((c) => GestureDetector(
                        onTap: () {
                          settings.setSeedColor(c);
                          Navigator.pop(context);
                        },
                        child: Obx(() => AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: c,
                                shape: BoxShape.circle,
                                border: settings.seedColor.value == c.toARGB32()
                                    ? Border.all(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurface,
                                        width: 3)
                                    : null,
                                boxShadow: [
                                  BoxShadow(
                                      color: c.withAlpha(100),
                                      blurRadius: 8)
                                ],
                              ),
                            )),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class _ColorDot extends StatelessWidget {
  final Color color;
  const _ColorDot({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: color.withAlpha(80), blurRadius: 6)],
      ),
    );
  }
}
