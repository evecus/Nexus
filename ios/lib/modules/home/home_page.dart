import 'package:flutter/material.dart';
import 'package:player_shared/player_shared.dart';

import '../video/video_tab_page.dart';
import '../iptv/iptv_tab_page.dart';
import '../music/music_tab_page.dart';
import '../settings/settings_page.dart';
import 'widgets/mini_playback_bar.dart';

class _NavItem {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  const _NavItem(this.icon, this.selectedIcon, this.label);
}

const _items = [
  _NavItem(Icons.video_library_outlined,  Icons.video_library,  '视频'),
  _NavItem(Icons.live_tv_outlined,        Icons.live_tv,        'IPTV'),
  _NavItem(Icons.music_note_outlined,     Icons.music_note,     '音乐'),
  _NavItem(Icons.settings_outlined,       Icons.settings,       '设置'),
];

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _index = 0;

  final _pages = const [
    VideoTabPage(),
    IptvTabPage(),
    MusicTabPage(),
    SettingsPage(),
  ];

  @override
  void initState() {
    super.initState();
    // 启动时请求视频和音频访问权限。
    // 注意:`PermissionUtil.requestMediaPermissions` 在非 Android 平台上
    // 直接返回 true、不做任何事(见 permission_util.dart),iOS 端真正的
    // "本地文件访问权限"是按目录逐个申请的(用户在"设置 → 管理目录"里
    // 通过系统文件夹选择器添加,见 DirectoryManagerPage),不需要也无法
    // 在这里统一申请,保留这行调用只是为了不与 Android/TV 端产生代码
    // 分支差异,对 iOS 无实际作用。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      PermissionUtil.requestMediaPermissions();
    });
  }

  @override
  Widget build(BuildContext context) {
    // On Android a narrow portrait screen uses top text nav;
    // landscape or large (tablet ≥600 dp) uses a side rail (类似 Windows 端布局)。
    final width  = MediaQuery.sizeOf(context).width;
    final isWide = width >= 600;

    if (isWide) {
      return _buildTabletLayout(context);
    }
    return _buildPhoneLayout(context);
  }

  /// 手机端：顶部纯文字导航栏 + 内容区 + 底部迷你播放栏。
  Widget _buildPhoneLayout(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _buildTopTextNav(context),
            Container(
              height: 1,
              color: scheme.outlineVariant.withAlpha(60),
            ),
            Expanded(
              child: IndexedStack(index: _index, children: _pages),
            ),
            const MiniPlaybackBar(),
          ],
        ),
      ),
    );
  }

  /// 顶部纯文字导航栏：四个标签平分宽度，选中态加粗+主题色+下划线。
  Widget _buildTopTextNav(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 48,
      child: Row(
        children: List.generate(_items.length, (i) {
          final selected = i == _index;
          return Expanded(
            child: InkWell(
              onTap: () => setState(() => _index = i),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _items[i].label,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                      color: selected ? scheme.primary : scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 6),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    height: 2.5,
                    width: selected ? 20 : 0,
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }

  /// 平板端：左侧图标导航栏 + 内容区，内容区下方加迷你播放栏(样式类似 Windows 端)。
  Widget _buildTabletLayout(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          SafeArea(
            child: NavigationRail(
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              labelType: NavigationRailLabelType.all,
              groupAlignment: -1,
              leading: const SizedBox(height: 8),
              destinations: _items
                  .map((it) => NavigationRailDestination(
                        icon: Icon(it.icon),
                        selectedIcon: Icon(it.selectedIcon),
                        label: Text(it.label),
                        padding: const EdgeInsets.symmetric(vertical: 4),
                      ))
                  .toList(),
            ),
          ),
          VerticalDivider(
            width: 1,
            thickness: 1,
            color: Theme.of(context).colorScheme.outlineVariant.withAlpha(60),
          ),
          Expanded(
            child: Column(
              children: [
                Expanded(
                  child: IndexedStack(index: _index, children: _pages),
                ),
                const MiniPlaybackBar(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
