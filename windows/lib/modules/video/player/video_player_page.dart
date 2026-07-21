import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as p;
import 'package:player_shared/player_shared.dart';
import 'package:window_manager/window_manager.dart';

import 'package:nexus_windows/app/controller/app_settings_controller.dart';
import 'package:nexus_windows/app/controller/global_player_controller.dart';
import 'package:nexus_windows/player/vlc_backend.dart';

// ── Controller ────────────────────────────────────────────────────────────────

class VideoPlayerController extends GetxController
    with PlayerMixin, PlayerStateMixin {
  late String url;
  late String title;
  late bool isLocal;

  // Playlist passed from the library page
  final playlist      = <VideoFile>[].obs;
  final currentIndex  = 0.obs;

  final isPlaying   = false.obs;
  final isBuffering = false.obs;
  final position    = Duration.zero.obs;
  final duration    = Duration.zero.obs;
  final playSpeed   = 1.0.obs;
  final volume      = 100.0.obs;

  /// 进入播放页时若来自"底部播放栏续播"，会带上这个字段，
  /// 用来在打开媒体后 seek 回上次的播放进度。
  Duration? _resumePosition;

  @override
  void onInit() {
    super.onInit();
    final args = Get.arguments as Map<String, dynamic>? ?? {};
    url     = args['url']     as String? ?? '';
    title   = args['title']   as String? ?? '视频';
    isLocal = args['isLocal'] as bool?   ?? false;

    final resumeMs = args['resumePositionMs'] as int?;
    if (resumeMs != null && resumeMs > 0) {
      _resumePosition = Duration(milliseconds: resumeMs);
    }

    // Playlist support
    final rawList = args['playlist'] as List<VideoFile>? ?? [];
    final startIdx = args['startIndex'] as int? ?? 0;
    playlist.assignAll(rawList);
    currentIndex.value = startIdx;

    // 开始播放视频：停止全局音乐播放（视频/IPTV 优先于音乐）。
    GlobalPlayerController.instance.stopMusicForOtherPlayback();

    final s = AppSettingsController.instance;
    // 按用户设置选择后端：vlc / mpv。auto 对本地视频返回 exo，但 Windows
    // 无 ExoBackend，因此 auto 一律回退到 MPV 路径（即 else 分支）。
    final backendType = s.resolveBackendType(isIptv: false);
    final useVlc = backendType == PlayerBackendType.vlc;

    // 注意：新版 player_shared 里 `player` legacy getter 转发自
    // `backend`（一个 late 字段），必须先调用 initPlayer() 完成
    // backend 的赋值，之后才能访问 player / backend.streams 等。
    final Future<void> initFuture;
    if (useVlc) {
      initFuture = initPlayer(
        backend: VlcBackend(hardwareDecode: s.vlcHardwareDecode.value),
      );
    } else {
      final config = buildControllerConfig(
        hardwareDecode: s.hardwareDecode.value,
        compatMode: false,
        profile: s.mpvProfile.value,
      );
      initFuture = initPlayer(config: config);
    }

    initFuture.then((_) async {
      // 统一监听 backend 状态流（mpv / vlc 两个后端都暴露这些流），
      // 不再直接用 player.stream.* —— 这样 vlc 后端也能正常驱动 UI。
      backend.playing.listen((v)   => isPlaying.value   = v);
      backend.buffering.listen((v) => isBuffering.value = v);
      backend.position.listen(_onBackendPosition);
      backend.duration.listen((v) {
        duration.value = v;
        _reportStateToGlobal();
      });
      backend.volume.listen((v)    => volume.value      = v);
      // Auto-advance to next
      backend.completed.listen((completed) {
        if (completed) playNext();
      });

      // MPV 专属调优：画质预设等。VLC 自带网络缓冲 + 去交错，不需要。
      if (isMpv) {
        await applyMpvOptions(player, s.mpvProfile.value);
      }
      await backend.open(url);
      if (_resumePosition != null) {
        // 等待 duration 就绪后再 seek，避免过早 seek 被忽略。
        // 统一走 backend.duration 流，mpv/vlc 均支持。
        await backend.duration
            .firstWhere((d) => d > Duration.zero)
            .timeout(const Duration(seconds: 5), onTimeout: () => Duration.zero);
        await backend.seek(_resumePosition!);
        _resumePosition = null;
      }
      s.addRecentFile(url);
      autoHideControls();
    });
  }

  /// seek 之后，VLC 后端的 position 事件回调可能有明显延迟（甚至在某些
  /// 状态下短暂不触发），如果不做任何处理，backend.position.listen 里
  /// 还会先收到 1~2 个"seek 前的旧进度"事件，把我们刚刚乐观更新的
  /// position.value 覆盖回去，视觉上就是"点了进度条，但指针弹回原位/
  /// 完全不跳转"。
  ///
  /// 这里用一个短暂的时间戳记录"最近一次主动 seek 的目标时间"，在这个
  /// 窗口内，如果收到的后端 position 明显偏离目标（说明是滞后的旧事件），
  /// 就丢弃它，直到后端事件追上目标位置或窗口过期为止。
  DateTime? _lastSeekAt;
  Duration? _seekTarget;
  static const _seekGuardWindow = Duration(milliseconds: 900);

  void _onBackendPosition(Duration v) {
    final seekAt = _lastSeekAt;
    final target = _seekTarget;
    if (seekAt != null && target != null) {
      final withinWindow =
          DateTime.now().difference(seekAt) < _seekGuardWindow;
      // 后端上报的位置仍然明显落后于我们 seek 的目标（>800ms），大概率是
      // seek 触发前排队的旧事件，丢弃它，避免 UI 进度条弹回去。
      final stillStale = (target - v).inMilliseconds.abs() > 800;
      if (withinWindow && stillStale) {
        return;
      }
      // 后端追上了，或者窗口已过期（可能确实是一次真实的新进度，比如
      // seek 目标本身就没生效，此时应该信任后端而不是一直卡在乐观值）：
      // 清掉守卫状态，恢复正常被动更新。
      _lastSeekAt = null;
      _seekTarget = null;
    }
    position.value = v;
    _reportStateToGlobal();
  }

  /// 统一的 seek 入口：立刻乐观更新 UI 进度（不必等待后端确认），
  /// 同时转发给 backend 真正执行 seek。Slider 拖动/点击、±10s 快进快退
  /// 都应该走这里，而不是直接调用 backend.seek。
  void seekTo(Duration target) {
    final clamped = target.isNegative
        ? Duration.zero
        : (target > duration.value ? duration.value : target);
    _lastSeekAt = DateTime.now();
    _seekTarget = clamped;
    position.value = clamped; // 乐观更新：立刻反映到进度条/时间文本
    backend.seek(clamped);
  }

  /// 把当前播放信息同步给全局控制器，供底部播放栏展示 + 退出后续播。
  void _reportStateToGlobal() {
    GlobalPlayerController.instance.updateVideoState(
      title: title,
      position: position.value,
      duration: duration.value,
      resumeArgs: {
        'url': url,
        'title': title,
        'isLocal': isLocal,
        'playlist': playlist.toList(),
        'startIndex': currentIndex.value,
        'resumePositionMs': position.value.inMilliseconds,
      },
    );
  }

  // 控制方法统一走 backend 抽象：mpv 后端底层就是 player.*，
  // vlc 后端则是 VlcPlayerController.*。两个后端都支持，
  // 无需在调用处做 isMpv 判断。
  void togglePlay() => backend.playOrPause();

  void seekRelative(int seconds) {
    seekTo(position.value + Duration(seconds: seconds));
  }

  void setSpeed(double s) {
    playSpeed.value = s;
    backend.setRate(s);
  }

  void setVolume(double v) {
    volume.value = v;
    backend.setVolume(v);
  }

  void playIndex(int index) {
    if (index < 0 || index >= playlist.length) return;
    currentIndex.value = index;
    final f = playlist[index];
    url   = f.path;
    title = p.withoutExtension(f.name);
    backend.open(f.path);
    AppSettingsController.instance.addRecentFile(f.path);
  }

  void playNext() {
    if (currentIndex.value < playlist.length - 1) {
      playIndex(currentIndex.value + 1);
    }
  }

  void playPrev() {
    if (currentIndex.value > 0) {
      playIndex(currentIndex.value - 1);
    }
  }

  Future<void> enterFullScreen() async {
    await windowManager.setFullScreen(true);
    isFullScreen.value = true;
    autoHideControls(seconds: 3);
  }

  Future<void> exitFullScreen() async {
    await windowManager.setFullScreen(false);
    isFullScreen.value = false;
    showControls.value = true;
  }

  void onMouseMove() => autoHideControls(seconds: 3);

  @override
  void onClose() {
    if (isFullScreen.value) windowManager.setFullScreen(false);
    // 退出播放页即停止播放（需求：视频退出播放页后停止播放），
    // 但保留最后的进度/标题信息给底部播放栏用于展示 + 续播。
    _reportStateToGlobal();
    GlobalPlayerController.instance.onVideoPageClosed();
    disposePlayer();
    super.onClose();
  }
}

// ── Route args helper (call from video_tab_page) ─────────────────────────────

abstract class AppNavigatorPlayer {
  static void toVideoPlayerWithPlaylist({
    required String url,
    required String title,
    required bool isLocal,
    List<VideoFile> playlist = const [],
    int startIndex = 0,
    int resumePositionMs = 0,
  }) {
    Get.toNamed('/video/player', arguments: {
      'url':        url,
      'title':      title,
      'isLocal':    isLocal,
      'playlist':   playlist,
      'startIndex': startIndex,
      'resumePositionMs': resumePositionMs,
    });
  }

  /// 由底部播放栏调用：使用上次保存的完整参数（含 resumePositionMs）
  /// 重新进入视频播放页续播。
  static void resumeVideoPlayer(Map<String, dynamic> resumeArgs) {
    Get.toNamed('/video/player', arguments: resumeArgs);
  }
}

// ── Page ──────────────────────────────────────────────────────────────────────

class VideoPlayerPage extends StatefulWidget {
  const VideoPlayerPage({super.key});

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage> {
  late final VideoPlayerController ctrl;

  @override
  void initState() {
    super.initState();
    ctrl = Get.put(VideoPlayerController());
  }

  @override
  void dispose() {
    Get.delete<VideoPlayerController>();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: FocusNode()..requestFocus(),
      autofocus: true,
      onKeyEvent: _handleKey,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Obx(() {
          final fullscreen = ctrl.isFullScreen.value;
          return Row(
            children: [
              // Video area — always present, never rebuilt
              Expanded(
                child: _VideoArea(ctrl: ctrl),
              ),
              // Playlist panel — hidden in fullscreen
              if (!fullscreen) ...[
                Container(
                  width: 1,
                  color: Theme.of(context)
                      .colorScheme
                      .outlineVariant
                      .withAlpha(80),
                ),
                SizedBox(
                  width: 260,
                  child: _PlaylistPanel(ctrl: ctrl),
                ),
              ],
            ],
          );
        }),
      ),
    );
  }

  void _handleKey(KeyEvent e) {
    if (e is! KeyDownEvent) return;
    final key = e.logicalKey;
    if (key == LogicalKeyboardKey.space) {
      ctrl.togglePlay();
    } else if (key == LogicalKeyboardKey.arrowRight) {
      ctrl.seekRelative(5);
      ctrl.autoHideControls();
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      ctrl.seekRelative(-5);
      ctrl.autoHideControls();
    } else if (key == LogicalKeyboardKey.arrowUp) {
      ctrl.setVolume((ctrl.volume.value + 5).clamp(0, 100));
    } else if (key == LogicalKeyboardKey.arrowDown) {
      ctrl.setVolume((ctrl.volume.value - 5).clamp(0, 100));
    } else if (key == LogicalKeyboardKey.escape) {
      if (ctrl.isFullScreen.value) {
        ctrl.exitFullScreen();
      } else {
        Get.back();
      }
    } else if (key == LogicalKeyboardKey.keyF) {
      if (ctrl.isFullScreen.value) {
        ctrl.exitFullScreen();
      } else {
        ctrl.enterFullScreen();
      }
    }
  }
}

// ── Unified video area with hover-reveal overlay ──────────────────────────────

class _VideoArea extends StatelessWidget {
  final VideoPlayerController ctrl;
  const _VideoArea({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onHover:  (_) => ctrl.onMouseMove(),
      onEnter:  (_) => ctrl.onMouseMove(),
      cursor: SystemMouseCursors.basic,
      child: Obx(() {
        final showControls = ctrl.showControls.value;
        final isFullscreen = ctrl.isFullScreen.value;
        return Stack(
          fit: StackFit.expand,
          children: [
            // 统一走 backend.buildView()：mpv 返回 media_kit_video 的 Video，
            // vlc 返回 _VlcView。必须传 ctrl.playerKey（GlobalKey），让
            // VlcPlayer/Video 的 State 在窗口↔全屏切换时被"移动"而非销毁
            // 重建，避免 texture 表面丢失导致黑屏。
            ctrl.backend.buildView(key: ctrl.playerKey, fill: Colors.black),
            // Buffering spinner
            Obx(() => ctrl.isBuffering.value
                ? const Center(
                    child: CircularProgressIndicator(color: Colors.white))
                : const SizedBox()),
            // Gesture tip
            Obx(() => ctrl.showGestureTip.value
                ? Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(ctrl.gestureTipText.value,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 16)),
                    ),
                  )
                : const SizedBox()),
            // Controls overlay — 根据 showControls 挂载/卸载 _TopBar、_BottomBar。
            // 注意：_TopBar 内部的标题不能用 Obx(() => Text(ctrl.title)) 包裹——
            // ctrl.title 是普通 late String，不是 .obs 响应式变量，这样写会产生
            // 一个"空转"的 Obx（内部没有任何 .value 依赖）。这种空转 Obx 在
            // Windows 上会和 media_kit_video 的外部纹理(D3D11，经 ANGLE 从 mpv
            // 的 OpenGL 转译而来)的合成路径冲突，导致鼠标悬停、控制条出现时
            // 整个视频画面被灰色矩形覆盖。凡是不会随状态变化的内容，一律用
            // 普通 Widget，只有真正依赖 .obs 变量的部分才包 Obx。
            if (showControls) ...[
              _TopBar(ctrl: ctrl, isFullscreen: isFullscreen),
              _BottomBar(ctrl: ctrl, isFullscreen: isFullscreen),
            ],
          ],
        );
      }),
    );
  }
}

// ── Top bar — back button + title, always shown (windowed & fullscreen) ────────

class _TopBar extends StatelessWidget {
  final VideoPlayerController ctrl;
  final bool isFullscreen;
  const _TopBar({required this.ctrl, required this.isFullscreen});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0, left: 0, right: 0,
      // 注意：这里不能用 GestureDetector(behavior: HitTestBehavior.opaque)
      // 包裹整个渐变 Container ——在 Windows 上，这会导致 media_kit_video
      // 的外部纹理(D3D11，经 ANGLE 从 mpv 的 OpenGL 转译而来)与 Flutter
      // 引擎的合成路径冲突，使整个视频画面被灰色矩形覆盖。改用 GestureDetector
      // 默认的 HitTestBehavior.deferToChild，并给 Container 一个（哪怕全透明的）
      // color，让它自己响应点击，从而避免触发这条问题路径。
      child: GestureDetector(
        // 点击顶栏空白处隐藏控制条
        onTap: ctrl.toggleControls,
        child: Container(
          // color 必须显式设置（哪怕是 transparent），否则 Container 在没有
          // decoration 命中区域时不会响应点击——这里用 decoration 画渐变，
          // 所以额外套一层保证整个矩形区域都能命中。
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.black87, Colors.transparent],
            ),
          ),
          padding: const EdgeInsets.fromLTRB(4, 8, 16, 32),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back,
                    color: Colors.white, size: 22),
                tooltip: isFullscreen ? '退出全屏 (Esc)' : '返回 (Esc)',
                onPressed: () {
                  if (isFullscreen) {
                    ctrl.exitFullScreen();
                  } else {
                    Get.back();
                  }
                },
              ),
              const SizedBox(width: 4),
              Expanded(
                // 根因修复：ctrl.title 是普通 late String，不是 .obs 响应式变量，
                // 之前用 Obx(() => Text(ctrl.title)) 包裹是一个"空转"的 Obx——
                // 内部没有任何 .value 被访问，不会建立任何响应式依赖。这种空转
                // Obx 在 Windows 上会和 media_kit_video 的外部纹理(D3D11，经
                // ANGLE 从 mpv 的 OpenGL 转译而来)合成路径冲突，导致鼠标悬停、
                // 控制条出现时整个视频画面被灰色矩形覆盖。ctrl.title 从不变化，
                // 直接用普通 Text 即可，不需要任何响应式包裹。
                child: Text(
                  ctrl.title,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Bottom bar ────────────────────────────────────────────────────────────────

class _BottomBar extends StatelessWidget {
  final VideoPlayerController ctrl;
  final bool isFullscreen;
  const _BottomBar(
      {required this.ctrl, required this.isFullscreen});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 0, left: 0, right: 0,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [Colors.black87, Colors.transparent],
          ),
        ),
        padding: const EdgeInsets.fromLTRB(12, 24, 12, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Seek bar + timestamps
            Obx(() {
              final pos = ctrl.position.value;
              final dur = ctrl.duration.value;
              final pct = dur.inMilliseconds > 0
                  ? pos.inMilliseconds / dur.inMilliseconds
                  : 0.0;
              return Column(
                children: [
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 6),
                      overlayShape: const RoundSliderOverlayShape(
                          overlayRadius: 12),
                      activeTrackColor: Colors.white,
                      inactiveTrackColor: Colors.white30,
                      thumbColor: Colors.white,
                    ),
                    child: Slider(
                      value: pct.clamp(0.0, 1.0),
                      onChanged: (v) {
                        final t = (v * dur.inMilliseconds).round();
                        ctrl.seekTo(Duration(milliseconds: t));
                      },
                    ),
                  ),
                  Row(
                    children: [
                      Text(_fmt(pos),
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 11)),
                      const Spacer(),
                      Text(_fmt(dur),
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 11)),
                    ],
                  ),
                ],
              );
            }),
            const SizedBox(height: 2),
            // Buttons row
            Row(
              children: [
                // Play / Pause
                Obx(() => IconButton(
                      icon: Icon(
                        ctrl.isPlaying.value
                            ? Icons.pause
                            : Icons.play_arrow,
                        color: Colors.white,
                        size: 26,
                      ),
                      onPressed: ctrl.togglePlay,
                    )),
                // Seek -10s
                IconButton(
                  icon: const Icon(Icons.replay_10,
                      color: Colors.white, size: 22),
                  onPressed: () => ctrl.seekRelative(-10),
                  tooltip: '-10s',
                ),
                // Seek +10s
                IconButton(
                  icon: const Icon(Icons.forward_10,
                      color: Colors.white, size: 22),
                  onPressed: () => ctrl.seekRelative(10),
                  tooltip: '+10s',
                ),
                // Volume
                Obx(() => Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          ctrl.volume.value == 0
                              ? Icons.volume_off
                              : Icons.volume_up,
                          color: Colors.white70,
                          size: 18,
                        ),
                        SizedBox(
                          width: 72,
                          child: SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              trackHeight: 2,
                              thumbShape:
                                  const RoundSliderThumbShape(
                                      enabledThumbRadius: 5),
                              activeTrackColor: Colors.white,
                              inactiveTrackColor: Colors.white30,
                              thumbColor: Colors.white,
                            ),
                            child: Slider(
                              value:
                                  ctrl.volume.value.clamp(0, 100),
                              min: 0,
                              max: 100,
                              onChanged: ctrl.setVolume,
                            ),
                          ),
                        ),
                      ],
                    )),
                const Spacer(),
                // Speed
                PopupMenuButton<double>(
                  tooltip: '播放速度',
                  icon: Obx(() => Text(
                        '${ctrl.playSpeed.value}x',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 12),
                      )),
                  onSelected: ctrl.setSpeed,
                  itemBuilder: (_) =>
                      [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
                          .map((s) => PopupMenuItem(
                                value: s,
                                child: Text('${s}x'),
                              ))
                          .toList(),
                ),
                // Fullscreen toggle
                IconButton(
                  icon: Icon(
                    isFullscreen
                        ? Icons.fullscreen_exit_rounded
                        : Icons.fullscreen_rounded,
                    color: Colors.white,
                    size: 26,
                  ),
                  tooltip: isFullscreen ? '退出全屏 (F/Esc)' : '全屏 (F)',
                  onPressed: () {
                    if (isFullscreen) {
                      ctrl.exitFullScreen();
                    } else {
                      ctrl.enterFullScreen();
                    }
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m =
        d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s =
        d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }
}

// ── Playlist panel (right pane) ───────────────────────────────────────────────

class _PlaylistPanel extends StatelessWidget {
  final VideoPlayerController ctrl;
  const _PlaylistPanel({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text   = Theme.of(context).textTheme;

    return Container(
      color: scheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: scheme.outlineVariant.withAlpha(80)),
              ),
            ),
            child: Text(
              '播放列表',
              style: text.labelMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          // List
          Expanded(
            child: Obx(() {
              final list = ctrl.playlist;
              if (list.isEmpty) {
                return Center(
                  child: Text(
                    '无播放列表',
                    style: text.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant.withAlpha(120),
                    ),
                  ),
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: list.length,
                itemBuilder: (_, i) {
                  return Obx(() {
                    final isActive = ctrl.currentIndex.value == i;
                    return _PlaylistItem(
                      file: list[i],
                      index: i,
                      isActive: isActive,
                      onTap: () => ctrl.playIndex(i),
                    );
                  });
                },
              );
            }),
          ),
        ],
      ),
    );
  }
}

class _PlaylistItem extends StatefulWidget {
  final VideoFile file;
  final int index;
  final bool isActive;
  final VoidCallback onTap;
  const _PlaylistItem({
    required this.file,
    required this.index,
    required this.isActive,
    required this.onTap,
  });

  @override
  State<_PlaylistItem> createState() => _PlaylistItemState();
}

class _PlaylistItemState extends State<_PlaylistItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ext = p
        .extension(widget.file.name)
        .replaceFirst('.', '')
        .toUpperCase();

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          margin:  const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(7),
            color: widget.isActive
                ? scheme.primaryContainer
                : _hovered
                    ? scheme.surfaceContainerHighest
                    : Colors.transparent,
            border: widget.isActive
                ? Border.all(
                    color: scheme.primary.withAlpha(80), width: 1)
                : null,
          ),
          child: Row(
            children: [
              // Playing indicator or index
              SizedBox(
                width: 20,
                child: widget.isActive
                    ? Icon(Icons.play_arrow,
                        color: scheme.primary, size: 16)
                    : Text(
                        '${widget.index + 1}',
                        style: TextStyle(
                          color: scheme.onSurfaceVariant.withAlpha(150),
                          fontSize: 11,
                        ),
                        textAlign: TextAlign.center,
                      ),
              ),
              const SizedBox(width: 8),
              // Title
              Expanded(
                child: Text(
                  p.withoutExtension(widget.file.name),
                  style: TextStyle(
                    color: widget.isActive
                        ? scheme.onPrimaryContainer
                        : scheme.onSurface,
                    fontSize: 12,
                    fontWeight: widget.isActive
                        ? FontWeight.w600
                        : FontWeight.normal,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              // Format badge
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  ext,
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
