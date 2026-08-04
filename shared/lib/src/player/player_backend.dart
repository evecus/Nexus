import 'dart:async';

import 'package:flutter/material.dart';

/// 播放器后端类型。
enum PlayerBackendType { mpv, exo, vlc }

/// 统一的播放器后端抽象。
///
/// 之所以引入这一层，是为了让上层（VideoPlayerController / IptvPlayerController
/// 等业务控制器与对应的播放页 UI）无需关心底层到底是 media_kit (libmpv) 还是
/// ExoPlayer（video_player）。新增后端只需实现本抽象类即可。
///
/// 统一暴露以下能力：
/// - 5 个状态流：playing / buffering / position / duration / completed
/// - 同步状态读取：currentPosition / currentDuration / isPlaying / isBuffering
/// - 基本控制：open / playOrPause / seek / setRate / dispose
/// - 视图构建：buildView（不同后端返回各自的渲染 Widget）
abstract class PlayerBackend {
  /// 后端类型，便于上层做差异化逻辑（如 MPV 才有的画质预设）。
  PlayerBackendType get type;

  // ── 状态流 ──────────────────────────────────────────────
  Stream<bool> get playing;
  Stream<bool> get buffering;
  Stream<Duration> get position;
  Stream<Duration> get duration;
  Stream<bool> get completed;

  /// 音量变化流（0-100）。MPV/VLC 后端支持；ExoBackend 暂为空流。
  Stream<double> get volume;

  // ── 同步状态读取 ────────────────────────────────────────
  Duration get currentPosition;
  Duration get currentDuration;
  bool get isPlaying;
  bool get isBuffering;

  /// 当前音量（0-100）。不支持音量的后端返回 100。
  double get currentVolume;

  /// 视频原始分辨率。已知时返回实际值，未知或未初始化时返回 [Size.zero]。
  /// 用于\"全屏播放方向 → 自动\"模式：宽 > 高即视为横屏视频，旋转到横屏；
  /// 高 >= 宽即视为竖屏视频，保持竖屏全屏。
  Size get videoNativeSize => Size.zero;

  // ── 控制 ───────────────────────────────────────────────
  Future<void> open(String pathOrUrl);
  Future<void> playOrPause();
  Future<void> seek(Duration position);
  Future<void> setRate(double rate);

  /// 设置音量（0-100）。
  Future<void> setVolume(double v);

  /// 设置画面比例（仅 MPV 后端真正生效；ExoPlayer 后端通过包裹 AspectRatio
  /// 实现等价效果）。值含义：
  /// 0=auto 1=16:9 2=4:3 3=填充 4=原始 5=裁剪
  Future<void> setAspectRatio(int mode);

  /// 释放底层资源。调用后不可再用。
  Future<void> dispose();

  /// 构建视频画面 Widget。各后端返回各自的渲染组件（media_kit 的 Video /
  /// video_player 的 VideoPlayer），上层通过此方法统一获取。
  Widget buildView({
    Key? key,
    Color fill = Colors.black,
    BoxFit fit = BoxFit.contain,
  });
}
