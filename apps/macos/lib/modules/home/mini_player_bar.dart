import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:nexus/app/controller/global_player_controller.dart';
import 'package:nexus/app/routes.dart';
import 'package:nexus/modules/video/player/video_player_page.dart';

/// 底部播放栏 —— 仅在四个主页面（视频/IPTV/音乐/设置）显示，播放页不显示。
///
/// 展示当前"活跃"的媒体（video / iptv / music 三选一，由
/// [GlobalPlayerController.miniBarKind] 决定），点击后进入对应播放页：
/// - 本地视频：按保存的进度续播
/// - IPTV：回到之前的频道继续播放
/// - 音乐：音乐本身在后台一直播放，点击只是重新打开播放页 UI
class MiniPlayerBar extends StatelessWidget {
  const MiniPlayerBar({super.key});

  @override
  Widget build(BuildContext context) {
    final g = GlobalPlayerController.instance;
    final scheme = Theme.of(context).colorScheme;

    return Obx(() {
      final kind = g.miniBarKind.value;
      if (kind == MiniBarKind.none) return const SizedBox.shrink();

      return Material(
        color: scheme.surfaceContainerHigh,
        child: Container(
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: scheme.outlineVariant.withAlpha(80)),
            ),
          ),
          child: switch (kind) {
            MiniBarKind.video => InkWell(
                onTap: () => _handleTap(kind, g),
                child: _VideoMiniContent(g: g, scheme: scheme),
              ),
            MiniBarKind.iptv => InkWell(
                onTap: () => _handleTap(kind, g),
                child: _IptvMiniContent(g: g, scheme: scheme),
              ),
            MiniBarKind.music => _MusicMiniContent(
                g: g,
                scheme: scheme,
                onOpenPlayer: () => _handleTap(kind, g),
              ),
            MiniBarKind.none => const SizedBox.shrink(),
          },
        ),
      );
    });
  }

  void _handleTap(MiniBarKind kind, GlobalPlayerController g) {
    switch (kind) {
      case MiniBarKind.video:
        final args = g.videoResumeArgs;
        if (args != null) AppNavigatorPlayer.resumeVideoPlayer(args);
        break;
      case MiniBarKind.iptv:
        final args = g.iptvResumeArgs;
        if (args != null) AppNavigator.resumeIptvPlayer(args);
        break;
      case MiniBarKind.music:
        if (g.musicPlaylist.isNotEmpty) {
          AppNavigator.toMusicPlayer(
            playlist: g.musicPlaylist,
            index: g.musicCurrentIdx.value,
          );
        }
        break;
      case MiniBarKind.none:
        break;
    }
  }
}

// ── 图标 + 标题 通用外壳 ───────────────────────────────────────────────────

class _MiniIcon extends StatelessWidget {
  final IconData icon;
  final ColorScheme scheme;
  const _MiniIcon({required this.icon, required this.scheme});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withAlpha(140),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, size: 20, color: scheme.primary),
    );
  }
}

// ── 视频内容 ──────────────────────────────────────────────────────────────

class _VideoMiniContent extends StatelessWidget {
  final GlobalPlayerController g;
  final ColorScheme scheme;
  const _VideoMiniContent({required this.g, required this.scheme});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _MiniIcon(icon: Icons.movie_rounded, scheme: scheme),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Obx(() => Text(
                    g.videoTitle.value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600),
                  )),
              const SizedBox(height: 4),
              Obx(() {
                final pos = g.videoPosition.value;
                final dur = g.videoDuration.value;
                final pct = dur.inMilliseconds > 0
                    ? (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0)
                    : 0.0;
                return Row(
                  children: [
                    Text(_fmt(pos),
                        style: TextStyle(
                            fontSize: 10, color: scheme.onSurfaceVariant)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: pct,
                          minHeight: 3,
                          backgroundColor:
                              scheme.outlineVariant.withAlpha(80),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(_fmt(dur),
                        style: TextStyle(
                            fontSize: 10, color: scheme.onSurfaceVariant)),
                  ],
                );
              }),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Icon(Icons.play_circle_outline, color: scheme.primary, size: 26),
      ],
    );
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }
}

// ── IPTV 内容 ─────────────────────────────────────────────────────────────

class _IptvMiniContent extends StatelessWidget {
  final GlobalPlayerController g;
  final ColorScheme scheme;
  const _IptvMiniContent({required this.g, required this.scheme});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _MiniIcon(icon: Icons.live_tv_rounded, scheme: scheme),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Obx(() => Text(
                    g.iptvChannelName.value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600),
                  )),
              const SizedBox(height: 2),
              Obx(() => Text(
                    g.iptvGroupName.value.isEmpty
                        ? 'IPTV'
                        : g.iptvGroupName.value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11, color: scheme.onSurfaceVariant),
                  )),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.red,
            borderRadius: BorderRadius.circular(3),
          ),
          child: const Text('已暂停',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold)),
        ),
        const SizedBox(width: 8),
        Icon(Icons.play_circle_outline, color: scheme.primary, size: 26),
      ],
    );
  }
}

// ── 音乐内容 ──────────────────────────────────────────────────────────────

class _MusicMiniContent extends StatelessWidget {
  final GlobalPlayerController g;
  final ColorScheme scheme;
  final VoidCallback onOpenPlayer;
  const _MusicMiniContent({
    required this.g,
    required this.scheme,
    required this.onOpenPlayer,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: InkWell(
            onTap: onOpenPlayer,
            child: Row(
              children: [
                Obx(() {
                  final Uint8List? cover = g.musicCurrentMeta.value?.coverBytes;
                  return Container(
                    width: 40,
                    height: 40,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer.withAlpha(140),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: cover != null
                        ? Image.memory(cover, fit: BoxFit.cover)
                        : Icon(Icons.music_note, size: 20, color: scheme.primary),
                  );
                }),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Obx(() => Text(
                            g.musicCurrentTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600),
                          )),
                      const SizedBox(height: 2),
                      Obx(() {
                        final artist = g.musicCurrentArtist;
                        return Text(
                          artist.isEmpty ? '音乐' : artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 11, color: scheme.onSurfaceVariant),
                        );
                      }),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 4),
        // 播放控制：可直接在底部栏操作，不必进入播放页
        IconButton(
          icon: const Icon(Icons.skip_previous_rounded, size: 20),
          onPressed: g.musicPrevious,
          tooltip: '上一首',
        ),
        Obx(() => IconButton(
              icon: Icon(
                g.musicIsPlaying.value
                    ? Icons.pause_circle_filled_rounded
                    : Icons.play_circle_fill_rounded,
                size: 30,
                color: scheme.primary,
              ),
              onPressed: g.musicTogglePlay,
              tooltip: g.musicIsPlaying.value ? '暂停' : '播放',
            )),
        IconButton(
          icon: const Icon(Icons.skip_next_rounded, size: 20),
          onPressed: g.musicNext,
          tooltip: '下一首',
        ),
      ],
    );
  }
}
