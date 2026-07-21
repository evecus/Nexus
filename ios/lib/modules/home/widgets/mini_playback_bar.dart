import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:player_shared/player_shared.dart';

import '../../../app/routes.dart';
import '../../music/player/music_player_page.dart';

String _fmt(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60);
  if (h > 0) {
    return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
  return '$m:${s.toString().padLeft(2, '0')}';
}

/// 首页底部迷你播放栏。
///
/// 只在四个主页面（视频/IPTV/音乐/设置）显示，进入任意播放页时会被
/// push 到栈上层的播放页自然遮盖，不需要额外的显隐逻辑。
///
/// 视频 / IPTV / 音乐三种媒体播放互斥，同一时刻只会有一种"最近播放"，
/// 因此迷你播放栏始终只展示单行，由 [PlaybackBarController.kind] 决定
/// 展示哪一种：
/// - kind == music：音乐行，可直接暂停/播放/上一首/下一首，点击主体区域
///   进入音乐播放页。
/// - kind == video / iptv：视频/IPTV 快照行，点击后重新进入播放页并恢复
///   播放（视频续播进度；IPTV 重新连接同一频道）。
class MiniPlaybackBar extends StatelessWidget {
  const MiniPlaybackBar({super.key});

  @override
  Widget build(BuildContext context) {
    final music = Get.isRegistered<MusicPlayerController>()
        ? MusicPlayerController.instance
        : null;
    final bar = PlaybackBarController.instance;

    return Obx(() {
      final kind = bar.kind.value;
      // 音乐已被其他媒体打断（hasContent=false）时，即使 kind 还没被
      // 覆盖也不展示音乐行，避免残留过期状态；正常情况下 kind 会在
      // stopForOtherMedia 之后被视频/IPTV 的 clear()/save 快速覆盖。
      final showMusic =
          kind == PlaybackBarKind.music && (music?.hasContent.value ?? false);
      final showSnapshot = kind == PlaybackBarKind.video || kind == PlaybackBarKind.iptv;
      if (!showMusic && !showSnapshot) return const SizedBox.shrink();

      final scheme = Theme.of(context).colorScheme;
      return Material(
        color: scheme.surfaceContainerHigh,
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: 1,
                color: scheme.outlineVariant.withAlpha(60),
              ),
              if (showSnapshot) _SnapshotRow(bar: bar),
              if (showMusic) _MusicRow(music: music!),
            ],
          ),
        ),
      );
    });
  }
}

/// 视频/IPTV 快照行：展示上次退出播放页时的信息，点击恢复播放。
class _SnapshotRow extends StatelessWidget {
  const _SnapshotRow({required this.bar});
  final PlaybackBarController bar;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isVideo = bar.kind.value == PlaybackBarKind.video;

    return InkWell(
      onTap: () {
        if (isVideo) {
          AppNavigator.toVideoPlayer(
            playlist: bar.videoPlaylist,
            index: bar.videoIndex,
            resumePosition: bar.videoPosition.value,
          );
        } else {
          AppNavigator.toIptvPlayer(
            url: bar.iptvUrl.value,
            channelName: bar.iptvChannelName.value,
            groupName: bar.iptvGroupName.value,
            sourceIndex: bar.iptvSourceIndex,
          );
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                isVideo ? Icons.movie_outlined : Icons.live_tv_outlined,
                size: 20,
                color: scheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Obx(() => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        isVideo ? bar.videoTitle.value : bar.iptvChannelName.value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isVideo
                            ? '${_fmt(bar.videoPosition.value)} / ${_fmt(bar.videoDuration.value)}'
                            : (bar.iptvGroupName.value.isEmpty
                                ? '继续观看'
                                : bar.iptvGroupName.value),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  )),
            ),
            const SizedBox(width: 8),
            Icon(Icons.play_circle_fill, size: 30, color: scheme.primary),
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              onPressed: bar.clear,
              tooltip: '关闭',
            ),
          ],
        ),
      ),
    );
  }
}

/// 音乐行：展示当前播放曲目，可直接控制播放，点击主体进入音乐播放页。
class _MusicRow extends StatelessWidget {
  const _MusicRow({required this.music});
  final MusicPlayerController music;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: () => Get.toNamed(AppRoutes.musicPlayer),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Obx(() {
              final cover = music.coverBytes.value;
              return Container(
                width: 36,
                height: 36,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: scheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: cover != null
                    ? Image.memory(cover, fit: BoxFit.cover)
                    : Icon(Icons.music_note,
                        size: 20, color: scheme.onSecondaryContainer),
              );
            }),
            const SizedBox(width: 10),
            Expanded(
              child: Obx(() => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        music.title.value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        music.artist.value.isEmpty ? '本地音乐' : music.artist.value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                      ),
                    ],
                  )),
            ),
            IconButton(
              icon: const Icon(Icons.skip_previous, size: 22),
              onPressed: music.prev,
            ),
            Obx(() => IconButton(
                  icon: Icon(
                    music.isPlaying.value
                        ? Icons.pause_circle_filled
                        : Icons.play_circle_fill,
                    size: 32,
                  ),
                  color: scheme.primary,
                  onPressed: music.togglePlay,
                )),
            IconButton(
              icon: const Icon(Icons.skip_next, size: 22),
              onPressed: music.next,
            ),
          ],
        ),
      ),
    );
  }
}
