import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as p;

import 'video_player_controller.dart';

/// 视频播放页,完全照抄 NovaBox 的 `LocalPlayerActivity` + `activity_local_player.xml`。
///
/// - 手机:垂直布局,16:9 播放器(黑)在上,标题(15sp bold 黑)+ 1dp 线 + 播放列表在下
/// - 平板:水平 74:26 分屏,左播放器(黑),右栏(56dp 标题栏含返回+标题 + 1dp 线 + 播放列表)
/// - 控制层: #44000000 半透明,back/lock/center play(手机56dp 平板64dp)/
///   bottom seekbar + fullscreen(手机36dp 平板40dp)/loading(手机40dp 平板48dp)
/// - 播放列表项: 卡片 padding10dp mb6dp,左 18dp 青绿色 #FF1ABC9C 指示器 + 13sp 黑字
class VideoPlayerPage extends StatefulWidget {
  const VideoPlayerPage({super.key});

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage> {
  late final VideoPlayerController controller;

  @override
  void initState() {
    super.initState();
    controller = Get.put(VideoPlayerController());
  }

  @override
  void dispose() {
    Get.delete<VideoPlayerController>();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: Obx(() {
        if (controller.isFullScreen.value) {
          return _buildPlayerArea(context);
        }
        final isWide = MediaQuery.sizeOf(context).width >= 600;
        if (isWide) {
          return _buildTabletLayout(context);
        }
        return _buildPhoneLayout(context);
      }),
    );
  }

  /// 手机布局:垂直 — 16:9 播放器 + 标题(12dp padding) + 1dp 线 + 播放列表。
  /// 非全屏时不做沉浸式：播放器区域整体让出顶部状态栏高度，画面本身不会
  /// 被状态栏文字/图标遮挡（进入全屏横屏播放时才铺满，见 _buildPlayerArea
  /// 在 build() 中 isFullScreen 分支的直接调用）。
  Widget _buildPhoneLayout(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final width = MediaQuery.sizeOf(context).width;
    final playerHeight = width * 9 / 16;
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          SizedBox(
              width: width,
              height: playerHeight,
              child: _buildPlayerArea(context)),
          // 标题(NovaBox tvVideoTitle: padding12dp, 15sp bold,跟随主题文字色)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            color: scheme.surface,
            child: Obx(() => Text(
                  controller.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: scheme.onSurface,
                      fontSize: 15,
                      fontWeight: FontWeight.bold),
                )),
          ),
          Container(
              height: 1,
              color: scheme.outlineVariant.withAlpha(120),
              margin: const EdgeInsets.symmetric(horizontal: 12)),
          Expanded(child: _buildPlaylist(context)),
        ],
      ),
    );
  }

  /// 平板布局:水平 74:26 分屏。非全屏时不做沉浸式，整体让出状态栏高度。
  Widget _buildTabletLayout(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      bottom: false,
      child: LayoutBuilder(
        builder: (context, c) {
          final left = c.maxWidth * 0.74;
          final right = c.maxWidth - left;
          return Row(
            children: [
              SizedBox(
                width: left,
                height: double.infinity,
                child: _buildPlayerArea(context),
              ),
              SizedBox(
                width: right,
                child: Column(
                  children: [
                    // 标题栏(NovaBox: 56dp, 含返回40dp + 标题15sp bold,跟随主题)
                    Container(
                      height: 56,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      color: scheme.surface,
                      child: Row(
                        children: [
                          IconButton(
                            icon: Icon(Icons.arrow_back,
                                color: scheme.onSurface),
                            onPressed: () => Get.back(),
                          ),
                          Expanded(
                            child: Obx(() => Text(
                                  controller.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      color: scheme.onSurface,
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold),
                                )),
                          ),
                        ],
                      ),
                    ),
                    Container(
                        height: 1,
                        color: scheme.outlineVariant.withAlpha(120)),
                    Expanded(child: _buildPlaylist(context)),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildPlayerArea(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 600;
    return Stack(
      children: [
        // 视频画面(黑底) — 通过 backend 统一构建（MPV/ExoPlayer 均适用）
        controller.backend.buildView(
          key: controller.playerKey,
          fill: Colors.black,
        ),
        // 控件层(NovaBox: #44000000 半透明)
        _VideoPlayerOverlay(
          controller: controller,
          isWide: isWide,
          isFullScreen: controller.isFullScreen.value,
        ),
      ],
    );
  }

  /// 播放列表(NovaBox item_local_playlist: 卡片 padding10dp mb6dp,
  /// 左 18dp 青绿色 #FF1ABC9C 指示器(默认不可见)+ 13sp 文字,跟随主题)
  Widget _buildPlaylist(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      color: scheme.surface,
      child: Obx(() {
        final list = controller.playlist;
        final cur = controller.currentIndex.value;
        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          itemCount: list.length,
          itemBuilder: (_, i) {
            final name = list[i]['name'] ?? '';
            final isActive = i == cur;
            return Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withAlpha(120),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: scheme.outlineVariant.withAlpha(120), width: 0.5),
              ),
              child: InkWell(
                onTap: () => controller.playAt(i),
                child: Row(
                  children: [
                    // 青绿色正在播放指示器(非当前项不可见)
                    Icon(
                      Icons.play_arrow,
                      size: 18,
                      color: isActive
                          ? const Color(0xFF1ABC9C)
                          : Colors.transparent,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        p.withoutExtension(name),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isActive
                              ? const Color(0xFF1ABC9C)
                              : scheme.onSurface,
                          fontSize: 13,
                          fontWeight: isActive
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      }),
    );
  }
}

/// 视频播放器控件层 — 照抄 NovaBox flControlOverlay。
/// 仅: back / lock / center play / bottom seekbar + fullscreen / loading。
class _VideoPlayerOverlay extends StatefulWidget {
  final VideoPlayerController controller;
  final bool isWide;
  final bool isFullScreen;
  const _VideoPlayerOverlay({
    required this.controller,
    required this.isWide,
    required this.isFullScreen,
  });

  @override
  State<_VideoPlayerOverlay> createState() => _VideoPlayerOverlayState();
}

class _VideoPlayerOverlayState extends State<_VideoPlayerOverlay> {
  VideoPlayerController get c => widget.controller;
  bool get isWide => widget.isWide;
  bool get isFullScreen => widget.isFullScreen;
  Offset? _gestureStart;
  String _gestureType = '';
  double _lastSeekDelta = 0;

  void _onTap() {
    if (c.isLocked.value) {
      c.showControls.value = !c.showControls.value;
      return;
    }
    c.toggleControls();
  }

  void _onPanStart(DragStartDetails d) {
    if (c.isLocked.value) return;
    _gestureStart = d.localPosition;
    _gestureType = '';
    _lastSeekDelta = 0;
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (c.isLocked.value || _gestureStart == null) return;
    final dx = d.localPosition.dx - _gestureStart!.dx;
    final dy = d.localPosition.dy - _gestureStart!.dy;
    final w = context.size?.width ?? 400;
    final h = context.size?.height ?? 600;

    if (_gestureType.isEmpty && (dx.abs() + dy.abs()) > 10) {
      if (dx.abs() > dy.abs()) {
        _gestureType = 'seek';
        c.onSeekGestureStart();
      } else {
        _gestureType = _gestureStart!.dx < w / 2 ? 'brightness' : 'volume';
        if (_gestureType == 'brightness') {
          c.onBrightnessGestureStart();
        } else {
          c.onVolumeGestureStart();
        }
      }
    }

    if (_gestureType == 'seek') {
      _lastSeekDelta = dx / w * 120;
      c.onSeekGestureUpdate(_lastSeekDelta);
    } else if (_gestureType == 'brightness') {
      c.onBrightnessGestureUpdate(-dy / h);
    } else if (_gestureType == 'volume') {
      c.onVolumeGestureUpdate(-dy / h);
    }
  }

  void _onPanEnd(DragEndDetails d) {
    if (_gestureType == 'seek') {
      c.onSeekGestureEnd(_lastSeekDelta);
    }
    _gestureType = '';
    _gestureStart = null;
    _lastSeekDelta = 0;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _onTap,
      onPanStart: _onPanStart,
      onPanUpdate: _onPanUpdate,
      onPanEnd: _onPanEnd,
      behavior: HitTestBehavior.translucent,
      child: Obx(() {
        final showLock = c.isLocked.value;
        final showAll = c.showControls.value && !c.isLocked.value;
        return Stack(
          children: [
            // 手势提示
            if (c.showGestureTip.value)
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    c.gestureTipText.value,
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ),
              ),
            // 锁按钮(锁定时仍可见,右上角)
            if (showLock)
              Positioned(
                top: 0,
                right: 0,
                child: isFullScreen
                    ? SafeArea(
                        bottom: false,
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: IconButton(
                            icon: const Icon(Icons.lock,
                                color: Colors.white, size: 24),
                            onPressed: c.toggleLock,
                          ),
                        ),
                      )
                    : Padding(
                        padding: const EdgeInsets.all(8),
                        child: IconButton(
                          icon: const Icon(Icons.lock,
                              color: Colors.white, size: 24),
                          onPressed: c.toggleLock,
                        ),
                      ),
              ),
            // 全部控件(NovaBox: 控制层背景 #44000000)
            if (showAll) ...[
              _buildTopBar(context),
              _buildCenterPlayPause(context),
              _buildBottomBar(context),
            ],
            // 加载指示器(NovaBox pbLoading: 手机40dp 平板48dp)
            if (c.isBuffering.value)
              Center(
                child: SizedBox(
                  width: isWide ? 48 : 40,
                  height: isWide ? 48 : 40,
                  child: const CircularProgressIndicator(color: Colors.white),
                ),
              ),
          ],
        );
      }),
    );
  }

  /// 顶部栏: back(左上) + lock(右上)。
  /// 非全屏时外层布局已整体让出状态栏高度，此处直接贴边即可；仅全屏
  /// (横屏)时才需要额外用 SafeArea 避让刘海/挖孔等安全区。
  Widget _buildTopBar(BuildContext context) {
    final row = Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // 返回(NovaBox ivBack: 44dp)
        SizedBox(
          width: 44,
          height: 44,
          child: IconButton(
            padding: EdgeInsets.zero,
            icon: const Icon(Icons.arrow_back, color: Colors.white, size: 26),
            onPressed: () {
              if (c.isFullScreen.value) {
                c.exitFullScreen();
              } else {
                Get.back();
              }
            },
          ),
        ),
        // 锁(NovaBox ivLock: 40dp, 右上)
        SizedBox(
          width: 40,
          height: 40,
          child: IconButton(
            padding: EdgeInsets.zero,
            icon: Icon(
              c.isLocked.value ? Icons.lock : Icons.lock_open,
              color: Colors.white,
              size: 24,
            ),
            onPressed: c.toggleLock,
          ),
        ),
      ],
    );
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: isFullScreen
          ? SafeArea(
              bottom: false,
              child: Padding(padding: const EdgeInsets.all(8), child: row),
            )
          : Padding(padding: const EdgeInsets.all(8), child: row),
    );
  }

  /// 中央播放/暂停(NovaBox ivPlayPause: 手机56dp 平板64dp)。
  Widget _buildCenterPlayPause(BuildContext context) {
    return Positioned.fill(
      child: Center(
        child: SizedBox(
          width: isWide ? 64 : 56,
          height: isWide ? 64 : 56,
          child: IconButton(
            padding: EdgeInsets.zero,
            iconSize: isWide ? 64 : 56,
            icon: Icon(
              c.isPlaying.value
                  ? Icons.pause_circle_filled
                  : Icons.play_circle_filled,
              color: Colors.white,
            ),
            onPressed: c.togglePlay,
          ),
        ),
      ),
    );
  }

  /// 底部栏: 当前时间 + SeekBar + 总时间 + 全屏按钮。
  /// NovaBox: 手机 padding8 / 平板 padding12;SeekBar margin 手机8 平板10;
  /// 时间文字 手机12sp 平板13sp;全屏按钮 手机36dp 平板40dp。
  Widget _buildBottomBar(BuildContext context) {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Obx(() {
        final pos = c.position.value;
        final dur = c.duration.value;
        final totalMs =
            dur.inMilliseconds > 0 ? dur.inMilliseconds.toDouble() : 1.0;
        return Container(
          padding: EdgeInsets.all(isWide ? 12.0 : 8.0),
          child: Row(
            children: [
              Text(_fmt(pos),
                  style: TextStyle(
                      color: Colors.white, fontSize: isWide ? 13.0 : 12.0)),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(
                      horizontal: isWide ? 10.0 : 8.0),
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 2,
                      thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 6),
                      overlayShape: const RoundSliderOverlayShape(
                          overlayRadius: 12),
                      activeTrackColor: Colors.white,
                      inactiveTrackColor: Colors.white30,
                      thumbColor: Colors.white,
                    ),
                    child: Slider(
                      value: pos.inMilliseconds
                          .toDouble()
                          .clamp(0.0, totalMs),
                      max: totalMs,
                      onChanged: (v) =>
                          c.seekTo(Duration(milliseconds: v.round())),
                    ),
                  ),
                ),
              ),
              Text(_fmt(dur),
                  style: TextStyle(
                      color: Colors.white, fontSize: isWide ? 13.0 : 12.0)),
              // 全屏(NovaBox ivFullscreen: 手机36dp 平板40dp)
              SizedBox(
                width: isWide ? 40 : 36,
                height: isWide ? 40 : 36,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  icon: Icon(
                    c.isFullScreen.value
                        ? Icons.fullscreen_exit
                        : Icons.fullscreen,
                    color: Colors.white,
                    size: isWide ? 26 : 22,
                  ),
                  onPressed: c.toggleFullScreen,
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }
}
