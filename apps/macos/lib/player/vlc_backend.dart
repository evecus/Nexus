import 'dart:async';

import 'package:flutter/material.dart';
import 'package:player_shared/player_shared.dart';
import 'package:vlc_player/vlc_player.dart';

/// 基于 libVLC（通过 [vlc_player] 包）的后端实现。
///
/// 与 [MpvBackend] 不同，VLC 的 controller 是 per-media 的——每次 [open]
/// 都通过 [VlcPlayerController.setMedia] 加载新的 [VlcMediaSource]，
/// 因此本类内部维护一个当前的 [VlcPlayerController]，并通过
/// [StreamController] 把它的状态变化转换成统一的 [PlayerBackend] 状态流。
///
/// 选用 VLC 作为 IPTV 直播流备用后端的原因：
/// - libVLC 对 HLS（.m3u8）/ MPEG-TS / RTMP / RTSP 的容错和兼容性
///   是业界事实标准，明显好于 mpv（尤其是 IPTV 转发链路丢包、SPS/PPS
///   残缺、隔行扫描等场景）；
/// - 自带去交错（yadif/ivtc），不需要像 mpv 那样手动 vf-add 滤镜链；
/// - 自带 network-caching / live-caching 缓冲协商，不需要像 mpv 那样
///   手动调 demuxer-max-bytes；
/// - Windows 构建时 vlc_player 会自动下载 VLC runtime（libvlc.dll /
///   libvlccore.dll / plugins/）并打包到 Release 目录；macOS 下则依赖
///   CocoaPods 拉取的 VLCKit（见下方【macOS 移植说明】）。
///
/// 本类 mixin [ChangeNotifier]，在 controller 被替换（即 [open] 调用）
/// 时通过 [notifyListeners] 通知视图层（_VlcView）重建。
///
/// 注意：本实现使用 [vlc_player] 包，而非 flutter_vlc_player（后者只支持
/// Android/iOS）。
///
/// 【macOS 移植说明 / 风险点】
/// 本文件从 Windows 端原样迁移，接口调用（VlcPlayerController /
/// VlcMediaSource / VlcVideoFit 等）与 Windows 端完全一致，vlc_player
/// 包本身按 Windows/Linux/macOS 桌面平台设计。但本次移植环境没有
/// Flutter/macOS 编译工具链（需要 Xcode），无法实际跑一遍验证。请在本地
/// 按以下步骤确认：
/// 1. macOS 下 vlc_player 通过 CocoaPods 拉取预编译的 VLCKit framework，
///    `flutter pub get` + 在 Xcode 里 `pod install`（或 `flutter build
///    macos` 自动触发）即可，不需要像 Linux 那样让用户自行安装系统
///    libvlc；但要留意 CocoaPods 拉取的 VLCKit 体积较大，首次构建时间
///    会明显变长。
/// 2. macOS 应用若要分发（尤其是走 App Store 或做了 Hardened Runtime /
///    公证），需要确认 VLCKit.framework 被正确签名并随 `.app` 一起打包
///    （`flutter build macos` 默认会处理，但自定义签名流程时需要额外
///    核对）。
/// 3. 若 `flutter pub get` / 编译阶段发现 vlc_player 在 macOS 目标下
///    缺少必要的 native 绑定或直接报错不支持：IPTV/视频播放不会受影响，
///    因为 mpv 后端是默认且完全独立的实现；只需要把
///    app_settings_controller.dart 里 IPTV 默认后端从 vlc 改回 mpv、
///    并在 settings_page.dart 的下拉选项里去掉 VLC 选项即可安全降级，
///    不影响其余任何功能。
class VlcBackend with ChangeNotifier implements PlayerBackend {
  @override
  PlayerBackendType get type => PlayerBackendType.vlc;

  /// 是否启用硬件解码。true 时走 VLC 默认硬解协商（Windows 上是
  /// D3D11VA/DXVA2，macOS 上则是 VideoToolbox，由 libVLC 自动选择，
  /// Dart 侧调用方式不变），false 时通过 `:avcodec-hw=none` 强制软解。
  /// 与设置页"解码方式"联动。
  final bool hardwareDecode;

  VlcBackend({this.hardwareDecode = true});

  VlcPlayerController? _controller;
  bool _disposed = false;

  // 用 StreamController 暴露统一的状态流
  final _playingCtrl = StreamController<bool>.broadcast();
  final _bufferingCtrl = StreamController<bool>.broadcast();
  final _positionCtrl = StreamController<Duration>.broadcast();
  final _durationCtrl = StreamController<Duration>.broadcast();
  final _completedCtrl = StreamController<bool>.broadcast();
  final _volumeCtrl = StreamController<double>.broadcast();

  // 缓存上一次的值，用于过滤重复事件
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
  Duration get currentPosition =>
      _controller?.value.position ?? Duration.zero;
  @override
  Duration get currentDuration =>
      _controller?.value.duration ?? Duration.zero;
  @override
  bool get isPlaying =>
      _controller?.value.state == VlcPlaybackState.playing;
  @override
  bool get isBuffering =>
      _controller?.value.state == VlcPlaybackState.buffering;
  @override
  double get currentVolume {
    // VlcPlayerValue.volume 是 0-200 int（VLC 原生范围），归一化到 0-100
    final raw = _controller?.value;
    if (raw == null) return _lastVolume;
    return (raw.volume / 2).clamp(0.0, 100.0);
  }

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

    // 通过 VlcPlaybackState 枚举派生 playing / buffering / completed
    final playing = v.state == VlcPlaybackState.playing;
    if (playing != _lastPlaying) {
      _lastPlaying = playing;
      _playingCtrl.add(playing);
    }
    final buffering = v.state == VlcPlaybackState.buffering ||
        v.state == VlcPlaybackState.opening;
    if (buffering != _lastBuffering) {
      _lastBuffering = buffering;
      _bufferingCtrl.add(buffering);
    }
    final completed = v.state == VlcPlaybackState.ended;
    if (completed != _lastCompleted) {
      _lastCompleted = completed;
      if (completed) _completedCtrl.add(true);
    }

    // volume 变化（int 0-200 → double 0-100）
    final vol = (v.volume / 2).clamp(0.0, 100.0);
    if (vol != _lastVolume) {
      _lastVolume = vol;
      _volumeCtrl.add(vol);
    }
  }

  @override
  Future<void> open(String pathOrUrl) async {
    if (_disposed) return;
    // 销毁旧 controller
    if (_controller != null) {
      _controller!.removeListener(_onChanged);
      // VlcPlayerController 继承自 ValueNotifier，dispose() 返回 void（非 Future）
      _controller!.dispose();
      _controller = null;
      _resetCache();
    }

    final Uri uri;
    try {
      uri = Uri.parse(pathOrUrl);
    } catch (_) {
      return;
    }

    // IPTV 直播流优化参数：
    // :network-caching=1500 —— 默认 1000ms 太短，抖动时容易卡顿；
    //   太长会增加直播延迟，1500ms 是平衡值。
    // :deinterlace-filter=yadif —— VLC 自带的去交错，对 1080i 体育源有效。
    //   （vlc_player 通过 VlcMediaSource.mediaOptions 传 VLC 原生参数）
    //
    // 解码方式：与设置页"解码方式"联动。VLC 走 FFmpeg libavcodec，
    // :avcodec-hw=any 让 VLC 自动选择最佳硬解后端（Windows 上是
    // D3D11VA / DXVA2，macOS 上是 VideoToolbox）；:avcodec-hw=none
    // 强制软解，兼容性更好但 CPU 占用高。
    final isNetwork = uri.scheme == 'http' ||
        uri.scheme == 'https' ||
        uri.scheme == 'rtsp' ||
        uri.scheme == 'rtmp' ||
        uri.scheme == 'udp';

    final sourceUri = isNetwork
        ? uri
        : (uri.scheme == 'file' ? uri : Uri.file(pathOrUrl));

    final mediaOptions = <String>[
      ':network-caching=1500',
      if (hardwareDecode) ':avcodec-hw=any' else ':avcodec-hw=none',
    ];

    final source = VlcMediaSource(
      uri: sourceUri,
      mediaOptions: mediaOptions,
    );

    final next = VlcPlayerController(
      mediaSource: source,
      autoPlay: true,
    );

    _controller = next;
    next.addListener(_onChanged);
    // 通知视图层 controller 已切换，触发重建
    notifyListeners();

    try {
      // setMedia 会把 source 加载到 native player 并（因 autoPlay=true）开始播放。
      // controller 已在构造时收到 mediaSource，这里再次显式调用是为了
      // 确保在 controller 被 VlcPlayer attach 后媒体确实加载——vlc_player 的
      // 实现里构造期传的 mediaSource 会在 attach 时应用，setMedia 用于
      // 后续切换源；此处为保险起见也调用一次。
      await next.setMedia(source, autoPlay: true);
      if (_disposed) return;
      // 初始化完成后发出初始事件，便于 UI 同步
      _durationCtrl.add(next.value.duration);
      _positionCtrl.add(next.value.position);
      _volumeCtrl.add((next.value.volume / 2).clamp(0.0, 100.0));
      notifyListeners();
    } catch (_) {
      _bufferingCtrl.add(false);
    }
  }

  void _resetCache() {
    _lastPosition = Duration.zero;
    _lastDuration = Duration.zero;
    _lastPlaying = false;
    _lastBuffering = false;
    _lastCompleted = false;
    _lastVolume = 100.0;
  }

  @override
  Future<void> playOrPause() async {
    final c = _controller;
    if (c == null) return;
    if (c.value.state == VlcPlaybackState.playing) {
      await c.pause();
    } else {
      await c.play();
    }
  }

  @override
  Future<void> seek(Duration position) async {
    final c = _controller;
    if (c == null) return;
    await c.seekTo(position);
  }

  @override
  Future<void> setRate(double rate) async {
    final c = _controller;
    if (c == null) return;
    await c.setPlaybackSpeed(rate);
  }

  @override
  Future<void> setVolume(double v) async {
    final c = _controller;
    if (c == null) return;
    // VLC 原生音量范围 0-200，PlayerBackend 接口约定 0-100，做 ×2 转换
    final vlcVol = (v.clamp(0.0, 100.0) * 2).round();
    await c.setVolume(vlcVol);
    _lastVolume = v.clamp(0.0, 100.0);
    _volumeCtrl.add(_lastVolume);
  }

  @override
  Future<void> setAspectRatio(int mode) async {
    // VLC 后端通过 buildView 的 fit 参数控制，这里不通过 property 设置。
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    final c = _controller;
    if (c != null) {
      c.removeListener(_onChanged);
      // VlcPlayerController 继承自 ValueNotifier，dispose() 返回 void（非 Future）
      c.dispose();
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
    return _VlcView(backend: this, fill: fill, fit: fit, playerKey: key);
  }
}

/// VlcBackend 的视频渲染组件。通过 [AnimatedBuilder] 监听 backend 的
/// ChangeNotifier，在 controller 被替换或 isReady 变化时重建。
class _VlcView extends StatelessWidget {
  final VlcBackend backend;
  final Color fill;
  final BoxFit fit;
  /// 透传给内部 VlcPlayer 的 key。上层（IPTV 播放页）传入 GlobalKey
  /// 可让 VlcPlayer 的 State 在分屏↔全屏切换时被"移动"而非销毁重建。
  /// 在 Windows/Linux 上这能避免 texture-backed 渲染表面丢失导致的全屏
  /// 黑屏；在 macOS 上 vlc_player 走的是原生 platform view（而非纹理），
  /// 同样受益于"移动而非销毁重建"，可以避免原生视图短暂消失/重新附加的
  /// 闪烁，三端统一用同一套 GlobalKey 透传逻辑。
  final Key? playerKey;
  const _VlcView({
    required this.backend,
    required this.fill,
    required this.fit,
    this.playerKey,
  });

  /// 将 PlayerBackend 的 BoxFit 映射到 vlc_player 的 VlcVideoFit。
  VlcVideoFit _mapFit(BoxFit f) {
    switch (f) {
      case BoxFit.fill:
        return VlcVideoFit.fill;
      case BoxFit.cover:
        return VlcVideoFit.cover;
      case BoxFit.contain:
        return VlcVideoFit.contain;
      default:
        return VlcVideoFit.contain;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: backend,
      builder: (context, _) {
        final c = backend._controller;
        if (c == null) {
          return ColoredBox(color: fill, child: const SizedBox.expand());
        }
        // VlcPlayer 自身就是 texture-backed（Windows/Linux）或 platform view
        // （Android/iOS/macOS）的渲染组件，内部已处理 videoSize / aspectRatio。
        // 我们只需用 SizedBox.expand 撑满父级，让 VlcPlayer 的 fit 参数
        // 控制画面缩放方式，并用 ColoredBox 提供黑色背景。
        //
        // playerKey 透传到 VlcPlayer：当上层用 GlobalKey 时，分屏→全屏
        // 切换会让 Flutter 把 VlcPlayer 的 State 移动到新子树位置，而不是
        // 销毁旧 State 再创建新 State，从而保留 texture 表面不中断。
        return ColoredBox(
          color: fill,
          child: SizedBox.expand(
            child: VlcPlayer(
              key: playerKey,
              controller: c,
              backgroundColor: fill,
              fit: _mapFit(fit),
            ),
          ),
        );
      },
    );
  }
}
