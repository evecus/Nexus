import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:player_shared/player_shared.dart';

import 'package:nexus_tv/app/tv_focus_node.dart';
import 'package:nexus_tv/app/tv_style.dart';
import 'package:nexus_tv/app/theme/tv_theme.dart';
import 'package:nexus_tv/app/routes/tv_routes.dart';
import 'package:nexus_tv/widgets/tv_highlight.dart';
import 'package:nexus_tv/widgets/tv_playback_entry.dart';

class TvHomePage extends StatefulWidget {
  const TvHomePage({super.key});

  @override
  State<TvHomePage> createState() => _TvHomePageState();
}

class _TvHomePageState extends State<TvHomePage> {
  @override
  void initState() {
    super.initState();
    // 启动时请求基础媒体权限（READ_MEDIA_VIDEO/AUDIO），标准系统弹窗，
    // 不会跳转设置页。TV 端之前一直没有在首页主动请求过，只在进入视频/
    // 音乐库页面时才临时请求，这里补上和手机端一致的启动即请求行为。
    // "所有文件访问权限"（SD卡/U盘）不在这里申请，由用户在设置页按需开启。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      PermissionUtil.requestMediaPermissions();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() => Scaffold(
          backgroundColor: TvColors.background,
          body: SafeArea(
            child: Column(
              children: [
                // Header
                Padding(
                  padding: EdgeInsets.fromLTRB(48.w, 16.w, 48.w, 0),
                  child: Row(
                    children: [
                      Icon(Icons.play_circle_filled,
                          color: TvColors.primary, size: 52.w),
                      SizedBox(width: 16.w),
                      Text('Nexus', style: TvStyle.titleLarge),
                      const Spacer(),
                      const TvPlaybackEntry(),
                      SizedBox(width: 16.w),
                      TvHighlight(
                        focusNode: TvFocusNode(),
                        onTap: () => Get.toNamed(TvRoutes.settings),
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                              horizontal: 20.w, vertical: 12.w),
                          child: Row(
                            children: [
                              Icon(Icons.settings,
                                  color: TvColors.primary, size: 32.w),
                              SizedBox(width: 8.w),
                              Text('设置', style: TvStyle.bodyMedium),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                SizedBox(height: 32.w),

                // Main module cards
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(48.w, 0, 48.w, 24.w),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxHeight: 560.w),
                        child: FocusTraversalGroup(
                          policy: OrderedTraversalPolicy(),
                          child: Row(
                            children: [
                              _ModuleCard(
                                autofocus: true,
                                icon: Icons.video_library,
                                label: '视频',
                                subtitle: '本地媒体库 · 网络链接',
                                color: const Color(0xFF1A6BA0),
                                route: TvRoutes.video,
                                order: 1,
                              ),
                              SizedBox(width: 32.w),
                              _ModuleCard(
                                icon: Icons.live_tv,
                                label: 'IPTV',
                                subtitle: '网络直播源 · m3u 文件',
                                color: const Color(0xFF8E2020),
                                route: TvRoutes.iptv,
                                order: 2,
                              ),
                              SizedBox(width: 32.w),
                              _ModuleCard(
                                icon: Icons.library_music,
                                label: '音乐',
                                subtitle: '本地音乐库',
                                color: const Color(0xFF1A7A4A),
                                route: TvRoutes.music,
                                order: 3,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ));
  }
}

class _ModuleCard extends StatefulWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final String route;
  final bool autofocus;
  final int order;

  const _ModuleCard({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.route,
    this.autofocus = false,
    this.order = 0,
  });

  @override
  State<_ModuleCard> createState() => _ModuleCardState();
}

class _ModuleCardState extends State<_ModuleCard> {
  final _focus = TvFocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: FocusTraversalOrder(
        order: NumericFocusOrder(widget.order.toDouble()),
        child: TvHighlight(
          focusNode: _focus,
          autofocus: widget.autofocus,
          onTap: () => Get.toNamed(widget.route),
          borderRadius: BorderRadius.circular(20.w),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20.w),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  widget.color,
                  widget.color.withAlpha(160),
                ],
              ),
            ),
            child: Padding(
              padding: EdgeInsets.all(40.w),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Obx(() => Icon(
                        widget.icon,
                        size: 80.w,
                        color: _focus.isFocused.value
                            ? Colors.white
                            : Colors.white70,
                      )),
                  const Spacer(),
                  Text(widget.label,
                      style: TvStyle.titleLarge.copyWith(color: Colors.white)),
                  SizedBox(height: 8.w),
                  Text(widget.subtitle,
                      style: TvStyle.labelSmall
                          .copyWith(color: Colors.white70)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
