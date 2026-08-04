import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:player_shared/player_shared.dart';

import 'package:nexus/app/routes/tv_routes.dart';
import 'package:nexus/app/theme/tv_theme.dart';
import 'package:nexus/app/tv_focus_node.dart';
import 'package:nexus/app/tv_style.dart';
import 'package:nexus/modules/music/player/tv_music_player_page.dart'
    show TvMusicPlayerController;
import 'package:nexus/widgets/tv_highlight.dart';

/// TV 端顶部"播放入口"：图标 + 当前播放标题，用于快捷跳回播放页。
///
/// 只在有内容可跳转时显示（音乐正在播放中，或视频/IPTV 有退出播放页时
/// 保留的快照），三者按"音乐 > 视频/IPTV 快照"的优先级只展示一条，
/// 避免在寸土寸金的顶部导航栏里占用过多空间。
///
/// 逻辑与安卓手机端完全一致：
/// - 音乐是 App 级常驻单例，退出播放页不会停止，这里点击直接回到播放页。
/// - 视频/IPTV 退出播放页即停止，但保留快照；点击后重新进入播放页，
///   视频从原进度续播，IPTV 重新连接回同一频道。
class TvPlaybackEntry extends StatefulWidget {
  const TvPlaybackEntry({super.key});

  @override
  State<TvPlaybackEntry> createState() => _TvPlaybackEntryState();
}

class _TvPlaybackEntryState extends State<TvPlaybackEntry> {
  final _focus = TvFocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final music = Get.isRegistered<TvMusicPlayerController>()
        ? TvMusicPlayerController.instance
        : null;
    final bar = PlaybackBarController.instance;

    return Obx(() {
      final showMusic = music?.hasContent.value ?? false;
      final showSnapshot = !showMusic && bar.hasSnapshot;
      if (!showMusic && !showSnapshot) return const SizedBox.shrink();

      final IconData icon;
      final String label;
      final VoidCallback onTap;

      if (showMusic) {
        icon = Icons.music_note;
        label = music!.title.value.isEmpty ? '音乐播放中' : music.title.value;
        onTap = () => TvNavigator.toMusicPlayerResume();
      } else {
        final isVideo = bar.kind.value == PlaybackBarKind.video;
        icon = isVideo ? Icons.movie : Icons.live_tv;
        label = isVideo ? bar.videoTitle.value : bar.iptvChannelName.value;
        onTap = () {
          if (isVideo) {
            TvNavigator.toVideoPlayer(
              playlist: bar.videoPlaylist,
              index: bar.videoIndex,
              resumePosition: bar.videoPosition.value,
            );
          } else {
            TvNavigator.toIptvPlayer(
              sourceIndex: bar.iptvSourceIndex,
              channelName: bar.iptvChannelName.value,
              groupName: bar.iptvGroupName.value,
            );
          }
        };
      }

      return TvHighlight(
        focusNode: _focus,
        onTap: onTap,
        borderRadius: TvStyle.radius8,
        child: Container(
          constraints: BoxConstraints(maxWidth: 320.w),
          padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.w),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 28.w, color: TvColors.primary),
              SizedBox(width: 10.w),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TvStyle.bodyMedium,
                ),
              ),
            ],
          ),
        ),
      );
    });
  }
}
