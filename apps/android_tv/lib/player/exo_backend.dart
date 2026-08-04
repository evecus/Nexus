import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:player_shared/player_shared.dart';
import 'package:video_player/video_player.dart';

/// 基于 ExoPlayer（通过 Flutter 官方 [video_player] 包）的后端实现。
///
/// 与 [MpvBackend] 不同，ExoPlayer 的 controller 是 per-media 的——每次
/// [open] 都需要销毁旧 controller 并创建新的，因此本类内部维护一个当前
/// 的 [VideoPlayerController]，并通过 [StreamController] 把它的状态变化
/// 转换成统一的 [PlayerBackend] 状态流。
///
/// 同时本类 mixin [ChangeNotifier]，在 controller 被替换（即 [open] 调用）
/// 时通过 [notifyListeners] 通知视图层（_ExoView）重建，使其能拿到新的
/// controller 实例。
///
/// ExoPlayer 默认就是硬件解码，无需额外的硬/软解开关；本类不响应
/// [setAspectRatio]（保留接口签名一致性，实际由 [buildView] 通过
/// [FittedBox] 的 fit 参数控制画面填充方式）。
class ExoBackend with ChangeNotifier implements PlayerBackend {
  @override
  PlayerBackendType get type => PlayerBackendType.exo;

  VideoPlayerController? _controller;
  bool _disposed = false;

  // 用 StreamController 暴露统一的状态流
  final _playingCtrl = StreamController<bool>.broadcast();
  final _bufferingCtrl = StreamController<bool>.broadcast();
  final _positionCtrl = StreamController<Duration>.broadcast();
  final _durationCtrl = StreamController<Duration>.broadcast();
  final _completedCtrl = StreamController<bool>.broadcast();
  final _volumeCtrl = StreamController<double>.broadcast();

  // 缓存上一次的 position/duration，用于过滤重复事件
  Duration _lastPosition = Duration.zero;
  Duration _lastDuration = Duration.zero;
  bool _lastPlaying = false;
  bool _lastBuffering = false;
  bool _lastCompleted = false;
  double _lastVolume = 100.0;

  @override
  Stream<bool> get playing => _playingCtrl.stream;
  @override
  Stream<bool> get buffering => _bufferingCtrl.stream;
  @override
  Stream<Duration> get position => _positionCtrl.stream;
  @override
  Stream<Duration> get duration => _durationCtrl.stream;
  @override
  Stream<bool> get completed => _completedCtrl.stream;
  @override
  Stream<double> get volume => _volumeCtrl.stream;

  @override
  Duration get currentPosition => _controller?.value.position ?? Duration.zero;
  @override
  Duration get currentDuration => _controller?.value.duration ?? Duration.zero;
  @override
  bool get isPlaying => _controller?.value.isPlaying ?? false;
  @override
  bool get isBuffering => _controller?.value.isBuffering ?? false;
  @override
  double get currentVolume =>
      (_controller?.value.volume ?? 1.0) * 100.0;

  void _onChanged() {
    final c = _controller;
    if (c == null) return;
    final v = c.value;

    // position 变化
    if (v.position != _lastPosition) {
      _lastPosition = v.position;
      _positionCtrl.add(v.position);
    }
    // duration 变化
    if (v.duration != _lastDuration) {
      _lastDuration = v.duration;
      _durationCtrl.add(v.duration);
    }
    // playing 状态变化
    if (v.isPlaying != _lastPlaying) {
      _lastPlaying = v.isPlaying;
      _playingCtrl.add(v.isPlaying);
    }
    // buffering 状态变化
    if (v.isBuffering != _lastBuffering) {
      _lastBuffering = v.isBuffering;
      _bufferingCtrl.add(v.isBuffering);
    }
    // 完成检测：position 到达 duration 且非播放中
    final finished = v.duration.inMilliseconds > 0 &&
        v.position.inMilliseconds >= v.duration.inMilliseconds - 250 &&
        !v.isPlaying;
    if (finished != _lastCompleted) {
      _lastCompleted = finished;
      if (finished) _completedCtrl.add(true);
    }
  }

  @override
  Future<void> open(String pathOrUrl) async {
    if (_disposed) return;
    // 销毁旧 controller
    if (_controller != null) {
      _controller!.removeListener(_onChanged);
      await _controller!.dispose();
      _controller = null;
      _resetCache();
    }

    final Uri uri;
    try {
      uri = Uri.parse(pathOrUrl);
    } catch (_) {
      return;
    }

    final VideoPlayerController next;
    if (uri.scheme == 'http' || uri.scheme == 'https') {
      next = VideoPlayerController.networkUrl(uri);
    } else if (uri.scheme == 'file') {
      next = VideoPlayerController.file(File.fromUri(uri));
    } else {
      // 当作本地文件路径
      next = VideoPlayerController.file(File(pathOrUrl));
    }

    _controller = next;
    next.addListener(_onChanged);
    // 通知视图层 controller 已切换，触发重建
    notifyListeners();

    try {
      await next.initialize();
      if (_disposed) return;
      // 初始化完成后立刻发出 duration / position 事件，便于 UI 同步
      _durationCtrl.add(next.value.duration);
      _positionCtrl.add(next.value.position);
      await next.play();
      _playingCtrl.add(true);
      // isInitialized 变化，再次通知视图层
      notifyListeners();
    } catch (_) {
      // 初始化失败
      _bufferingCtrl.add(false);
    }
  }

  void _resetCache() {
    _lastPosition = Duration.zero;
    _lastDuration = Duration.zero;
    _lastPlaying = false;
    _lastBuffering = false;
    _lastCompleted = false;
  }

  @override
  Future<void> playOrPause() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    if (c.value.isPlaying) {
      await c.pause();
    } else {
      await c.play();
    }
  }

  @override
  Future<void> seek(Duration position) async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    await c.seekTo(position);
  }

  @override
  Future<void> setRate(double rate) async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    await c.setPlaybackSpeed(rate);
  }

  @override
  Future<void> setVolume(double v) async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    final clamped = v.clamp(0.0, 100.0) / 100.0;
    await c.setVolume(clamped);
    if (clamped * 100 != _lastVolume) {
      _lastVolume = clamped * 100;
      _volumeCtrl.add(_lastVolume);
    }
  }

  @override
  Future<void> setAspectRatio(int mode) async {
    // ExoPlayer 后端不通过 property 控制画面比例，
    // 而是由 buildView 的 fit 参数决定。
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    final c = _controller;
    if (c != null) {
      c.removeListener(_onChanged);
      await c.dispose();
      _controller = null;
    }
    await _playingCtrl.close();
    await _bufferingCtrl.close();
    await _positionCtrl.close();
    await _durationCtrl.close();
    await _completedCtrl.close();
    await _volumeCtrl.close();
    // ChangeNotifier.dispose 标注了 @mustCallSuper，必须调用 super.dispose()
    super.dispose();
  }

  @override
  Widget buildView({
    Key? key,
    Color fill = Colors.black,
    BoxFit fit = BoxFit.contain,
  }) {
    return _ExoView(backend: this, fill: fill, fit: fit);
  }
}

/// ExoBackend 的视频渲染组件。通过 [AnimatedBuilder] 监听 backend 的
/// ChangeNotifier，在 controller 被替换或 isInitialized 变化时重建。
class _ExoView extends StatelessWidget {
  final ExoBackend backend;
  final Color fill;
  final BoxFit fit;
  const _ExoView({
    required this.backend,
    required this.fill,
    required this.fit,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: backend,
      builder: (context, _) {
        final c = backend._controller;
        if (c == null || !c.value.isInitialized) {
          return ColoredBox(
              color: fill, child: const SizedBox.expand());
        }
        // 重要：这里必须先用 SizedBox.expand 把 ColoredBox 撑满父级
        // (Stack/SizedBox 给出的整个播放器区域)，再用 Center + FittedBox
        // 让视频画面在这个已撑满的区域内居中缩放。
        //
        // 之前的写法是 ColoredBox(child: FittedBox(child: SizedBox(...
        // VideoPlayer)))，没有任何东西撑满父级：FittedBox 在父级约束
        // 是"loose"（Stack 的非 Positioned 子节点默认就是 loose 约束）
        // 时，会收缩到刚好包住缩放后的视频画面本身的大小，而不是撑满
        // 整个播放器区域。对于竖屏(9:16)视频，缩放后宽度远小于播放器
        // 区域宽度，于是这个"刚好包住视频"的 ColoredBox 本身就很窄，
        // 又因为 Stack 默认按左上角(topStart)对齐非 Positioned 子节点，
        // 视频画面就会贴着屏幕左侧显示，右边留出一大片空白——横屏
        // (16:9)视频因为缩放后宽度接近甚至等于播放器区域宽度，这个问题
        // 不明显，所以只有竖屏视频才会看出来偏左。
        //
        // 改为：外层 SizedBox.expand 先撑满父级约束给的全部空间，
        // ColoredBox 的黑色背景铺满整个播放器区域，Center 再把 FittedBox
        // (及其内部按视频原始像素宽高构造的 SizedBox)放在这个已撑满
        // 区域的正中央。与手机/平板端(android)的修复保持一致。
        return ColoredBox(
          color: fill,
          child: SizedBox.expand(
            child: Center(
              child: FittedBox(
                fit: fit,
                child: SizedBox(
                  width: c.value.size.width,
                  height: c.value.size.height,
                  child: VideoPlayer(c),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
