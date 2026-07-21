import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:player_shared/player_shared.dart';

import 'package:nexus_windows/app/controller/app_settings_controller.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = AppSettingsController.instance;

    return Scaffold(
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Content (full width on Windows)
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                // ── Appearance ────────────────────────────────────────
                const _Section(title: '外观'),
                Obx(() => _RadioTile(
                      title: '跟随系统',
                      value: 0,
                      groupValue: settings.themeMode.value,
                      onChanged: settings.setThemeMode,
                    )),
                Obx(() => _RadioTile(
                      title: '浅色',
                      value: 1,
                      groupValue: settings.themeMode.value,
                      onChanged: settings.setThemeMode,
                    )),
                Obx(() => _RadioTile(
                      title: '深色',
                      value: 2,
                      groupValue: settings.themeMode.value,
                      onChanged: settings.setThemeMode,
                    )),
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      const Text('主题颜色'),
                      const Spacer(),
                      Obx(() {
                        final current = Color(settings.seedColor.value);
                        return Row(
                          children: [
                            for (final c in _seedColors)
                              Padding(
                                padding:
                                    const EdgeInsets.only(left: 8),
                                child: GestureDetector(
                                  onTap: () => settings.setSeedColor(c),
                                  child: AnimatedContainer(
                                    duration:
                                        const Duration(milliseconds: 150),
                                    width: 28,
                                    height: 28,
                                    decoration: BoxDecoration(
                                      color: c,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: current == c
                                            ? Colors.white
                                            : Colors.transparent,
                                        width: 2,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: c.withAlpha(100),
                                          blurRadius: 4,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        );
                      }),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // ── Playback ──────────────────────────────────────────
                const _Section(title: '播放设置'),
                // 1. 视频播放后端（本地视频）
                Obx(() {
                  // Windows 端只提供 MPV / VLC 两个选项。onInit 已把存储里
                  // 残留的 auto 迁移为 mpv，这里再做一道防御：若值不是
                  // mpv/vlc（理论上不会发生），下拉框显示 mpv。
                  final current = settings.playerBackend.value;
                  final display = (current == PlayerBackendChoice.mpv ||
                          current == PlayerBackendChoice.vlc)
                      ? current
                      : PlayerBackendChoice.mpv;
                  return ListTile(
                    title: const Text('视频播放后端'),
                    subtitle: Text(_backendLabel(display, isIptv: false)),
                    trailing: DropdownButton<PlayerBackendChoice>(
                      value: display,
                      underline: const SizedBox(),
                      items: const [
                        DropdownMenuItem(
                            value: PlayerBackendChoice.mpv,
                            child: Text('MPV')),
                        DropdownMenuItem(
                            value: PlayerBackendChoice.vlc,
                            child: Text('VLC')),
                      ],
                      onChanged: (v) {
                        if (v != null) settings.setPlayerBackend(v);
                      },
                    ),
                  );
                }),
                // 2. IPTV 播放后端（独立于本地视频）
                Obx(() => ListTile(
                      title: const Text('IPTV 播放后端'),
                      subtitle: Text(_backendLabel(
                          settings.iptvBackend.value, isIptv: true)),
                      trailing: DropdownButton<PlayerBackendChoice>(
                        value: settings.iptvBackend.value,
                        underline: const SizedBox(),
                        items: const [
                          DropdownMenuItem(
                              value: PlayerBackendChoice.mpv,
                              child: Text('MPV')),
                          DropdownMenuItem(
                              value: PlayerBackendChoice.vlc,
                              child: Text('VLC')),
                        ],
                        onChanged: (v) {
                          if (v != null) settings.setIptvBackend(v);
                        },
                      ),
                    )),
                // 3. MPV 解码方式（仅对 MPV 后端生效）
                Obx(() => ListTile(
                      title: const Text('MPV 解码方式'),
                      subtitle: Text(settings.hardwareDecode.value
                          ? '硬解 — GPU 解码，降低 CPU 占用'
                          : '软解 — CPU 解码，兼容性更好'),
                      trailing: DropdownButton<bool>(
                        value: settings.hardwareDecode.value,
                        underline: const SizedBox(),
                        items: const [
                          DropdownMenuItem(value: true, child: Text('硬解')),
                          DropdownMenuItem(value: false, child: Text('软解')),
                        ],
                        onChanged: (v) {
                          if (v != null) settings.setHardwareDecode(v);
                        },
                      ),
                    )),
                // 4. MPV 画质预设（仅对 MPV 后端生效）
                Obx(() => ListTile(
                      title: const Text('MPV 画质预设'),
                      subtitle: Text(_profileLabel(settings.mpvProfile.value)),
                      trailing: DropdownButton<String>(
                        value: settings.mpvProfile.value,
                        underline: const SizedBox(),
                        items: const [
                          DropdownMenuItem(
                              value: 'performance',
                              child: Text('性能优先')),
                          DropdownMenuItem(
                              value: 'balanced',
                              child: Text('均衡')),
                          DropdownMenuItem(
                              value: 'quality',
                              child: Text('画质优先')),
                        ],
                        onChanged: (v) {
                          if (v != null) settings.setMpvProfile(v);
                        },
                      ),
                    )),
                // 5. VLC 解码方式（仅对 VLC 后端生效，独立于 MPV）
                Obx(() => ListTile(
                      title: const Text('VLC 解码方式'),
                      subtitle: Text(settings.vlcHardwareDecode.value
                          ? '硬解 — GPU 解码（D3D11VA/DXVA2 自动协商）'
                          : '软解 — CPU 解码，兼容性更好'),
                      trailing: DropdownButton<bool>(
                        value: settings.vlcHardwareDecode.value,
                        underline: const SizedBox(),
                        items: const [
                          DropdownMenuItem(value: true, child: Text('硬解')),
                          DropdownMenuItem(value: false, child: Text('软解')),
                        ],
                        onChanged: (v) {
                          if (v != null) settings.setVlcHardwareDecode(v);
                        },
                      ),
                    )),

                const SizedBox(height: 16),

                // ── About ────────────────────────────────────────────
                const _Section(title: '关于'),
                FutureBuilder<PackageInfo>(
                  future: PackageInfo.fromPlatform(),
                  builder: (_, snap) => ListTile(
                    title: const Text('Nexus for Windows'),
                    subtitle: Text(snap.hasData
                        ? 'v${snap.data!.version}+${snap.data!.buildNumber}'
                        : ''),
                    leading: const Icon(Icons.info_outline),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static const _seedColors = [
    Color(0xff3498db),
    Color(0xff2ecc71),
    Color(0xffe74c3c),
    Color(0xff9b59b6),
    Color(0xfff39c12),
    Color(0xff1abc9c),
  ];

  String _profileLabel(String p) {
    switch (p) {
      case 'performance': return '性能优先 — 最低延迟，适合低配设备';
      case 'quality':     return '画质优先 — 最佳画质，需要较强 GPU';
      default:            return '均衡 — 画质与性能平衡（推荐）';
    }
  }

  String _backendLabel(PlayerBackendChoice c, {required bool isIptv}) {
    switch (c) {
      case PlayerBackendChoice.mpv:
        return isIptv
            ? 'MPV — 画质调优丰富，seek 精准'
            : 'MPV — 画质调优丰富，seek 精准';
      case PlayerBackendChoice.vlc:
        return isIptv
            ? 'VLC — 对 HLS/TS/RTMP 直播流兼容性最好（默认）'
            : 'VLC — libVLC 引擎（画质预设仅对 MPV 生效）';
      // auto/exo 在 Windows 端不会出现（onInit 已迁移、UI 不展示），
      // 保留 default 分支仅为类型安全，避免 exhaustive switch 约束。
      default:
        return isIptv ? 'VLC' : 'MPV';
    }
  }
}

class _Section extends StatelessWidget {
  final String title;
  const _Section({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4, top: 8, left: 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

class _RadioTile extends StatelessWidget {
  final String title;
  final int value;
  final int groupValue;
  final void Function(int) onChanged;

  const _RadioTile({
    required this.title,
    required this.value,
    required this.groupValue,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return RadioListTile<int>(
      title: Text(title),
      value: value,
      groupValue: groupValue,
      onChanged: (v) { if (v != null) onChanged(v); },
      dense: true,
    );
  }
}
