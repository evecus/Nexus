import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'player_backend.dart';

/// 基于 media_kit (libmpv) 的后端实现。
///
/// 包装 [Player] + [VideoController]，对外暴露统一的 [PlayerBackend] 接口。
/// 保留对 MPV profile / 硬解 / 兼容模式 / 画质预设等特性的支持。
class MpvBackend implements PlayerBackend {
  @override
  PlayerBackendType get type => PlayerBackendType.mpv;

  final Player player;
  late final VideoController videoController;

  MpvBackend({PlayerConfiguration? configuration})
      : player = Player(
          configuration: configuration ??
              const PlayerConfiguration(title: 'Nexus'),
        );

  /// 用指定的 mpv 配置初始化 VideoController。
  /// 必须在 [open] 之前调用一次。
  void attachVideoController(VideoControllerConfiguration config) {
    videoController = VideoController(player, configuration: config);
  }

  // ── 状态流（直接转接 media_kit 的 Stream） ────────────────
  @override
  Stream<bool> get playing => player.stream.playing;
  @override
  Stream<bool> get buffering => player.stream.buffering;
  @override
  Stream<Duration> get position => player.stream.position;
  @override
  Stream<Duration> get duration => player.stream.duration;
  @override
  Stream<bool> get completed => player.stream.completed;
  @override
  Stream<double> get volume => player.stream.volume;

  // ── 同步状态读取 ────────────────────────────────────────
  @override
  Duration get currentPosition => player.state.position;
  @override
  Duration get currentDuration => player.state.duration;
  @override
  bool get isPlaying => player.state.playing;
  @override
  bool get isBuffering => player.state.buffering;
  @override
  double get currentVolume => player.state.volume;

  // ── 控制 ───────────────────────────────────────────────
  @override
  Future<void> open(String pathOrUrl) async {
    await player.open(Media(pathOrUrl));
  }

  @override
  Future<void> playOrPause() => player.playOrPause();

  @override
  Future<void> seek(Duration position) => player.seek(position);

  @override
  Future<void> setRate(double rate) => player.setRate(rate);

  @override
  Future<void> setVolume(double v) => player.setVolume(v);

  @override
  Future<void> setAspectRatio(int mode) async {
    const map = <int, String>{
      0: 'auto',
      1: '16:9',
      2: '4:3',
      3: 'keep',
      4: 'keep',
      5: 'crop',
    };
    try {
      await (player.platform as dynamic)
          .setProperty('video-aspect-override', map[mode] ?? 'auto');
    } catch (_) {}
  }

  /// 暴露原生 Player，供需要直接调用 mpv property 的场景使用
  /// （如 applyMpvOptions）。
  NativePlayer? get nativePlayer =>
      player.platform is NativePlayer ? player.platform as NativePlayer : null;

  @override
  Future<void> dispose() async {
    await player.dispose();
  }

  @override
  Widget buildView({
    Key? key,
    Color fill = Colors.black,
    BoxFit fit = BoxFit.contain,
  }) {
    return Video(
      controller: videoController,
      key: key,
      controls: NoVideoControls,
      fill: fill,
      fit: fit,
    );
  }
}
