import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../app/controller/global_player_controller.dart';
import '../video/video_tab_page.dart';
import '../iptv/iptv_tab_page.dart';
import '../music/music_tab_page.dart';
import '../settings/settings_page.dart';
import 'mini_player_bar.dart';

class _Dest {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  const _Dest(this.icon, this.selectedIcon, this.label);
}

const _dests = [
  _Dest(Icons.video_library_outlined, Icons.video_library, '视频'),
  _Dest(Icons.live_tv_outlined, Icons.live_tv, 'IPTV'),
  _Dest(Icons.music_note_outlined, Icons.music_note, '音乐'),
  _Dest(Icons.settings_outlined, Icons.settings, '设置'),
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
    // 预热音乐播放器：提前创建好 mpv Player + VideoController，让下面
    // 的 _HiddenMusicVideoSink 尽早绑定上真实渲染纹理，避免用户第一次
    // 点歌时出现"没有立即播放，需要手动点一次播放按钮"的竞态问题。
    // 只创建播放器本身，不会播放任何东西、也不会产生声音。
    GlobalPlayerController.instance.warmupMusicPlayer();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Row(
        children: [
          // ── Left navigation rail ─────────────────────────────────────────
          NavigationRail(
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            labelType: NavigationRailLabelType.all,
            backgroundColor: scheme.surface,
            destinations: _dests
                .map(
                  (d) => NavigationRailDestination(
                    icon: Icon(d.icon),
                    selectedIcon: Icon(d.selectedIcon),
                    label: Text(d.label),
                  ),
                )
                .toList(),
          ),
          VerticalDivider(
            width: 1,
            thickness: 1,
            color: scheme.outlineVariant.withAlpha(80),
          ),
          // ── Content + bottom mini player bar ─────────────────────────────
          Expanded(
            child: Column(
              children: [
                Expanded(
                  child: IndexedStack(index: _index, children: _pages),
                ),
                // 底部播放栏：只在这四个主页面显示，进入任何播放页都不显示
                // （播放页是通过 Get.toNamed 推入的独立全屏路由，不会经过
                // 这里的 Scaffold，因此天然满足"播放页都不显示"的要求）。
                const MiniPlayerBar(),
              ],
            ),
          ),
          // 全局隐藏的音乐播放渲染挂载点（1x1，不可见）。
          // media_kit/mpv 在桌面端即使只播放纯音频，也需要一个真正被
          // Video widget 消费的 VideoController/纹理，播放管线才能正常
          // 跑起来；否则会出现"点击歌曲后不会立即播放，需要手动点一次
          // 播放按钮才真正出声"的问题。这里让它常驻在四个主页面共用的
          // Scaffold 里（而不是只在音乐播放页里），这样：
          // 1) 从音乐库第一次点歌时就已经有渲染管线在跑；
          // 2) 退出音乐播放页回到主页后音乐仍可继续播放，不受页面切换影响。
          const _HiddenMusicVideoSink(),
        ],
      ),
    );
  }
}

/// 见上方注释：绑定全局音乐播放器的 VideoController，尺寸压缩为 0，
/// 用户不可见，仅用于保活 mpv 的渲染管线。
class _HiddenMusicVideoSink extends StatelessWidget {
  const _HiddenMusicVideoSink();

  @override
  Widget build(BuildContext context) {
    final g = GlobalPlayerController.instance;
    return Obx(() {
      // 音乐播放器懒初始化：还没播放过任何歌曲之前 backend 不存在，
      // 不能访问 videoController，这里用 musicPlayerReady 做保护。
      if (!g.musicPlayerReady) return const SizedBox.shrink();
      return IgnorePointer(
        child: SizedBox(
          width: 0,
          height: 0,
          child: OverflowBox(
            maxWidth: 1,
            maxHeight: 1,
            child: SizedBox(
              width: 1,
              height: 1,
              child: Video(
                controller: g.musicVideoController,
                controls: NoVideoControls,
              ),
            ),
          ),
        ),
      );
    });
  }
}
