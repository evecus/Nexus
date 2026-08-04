import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:volume_controller/volume_controller.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'player_backend.dart';
import 'mpv_backend.dart';

// ── MPV profiles ────────────────────────────────────────────────────────────

const Map<String, Map<String, String>> mpvProfiles = {
  'performance': {
    'profile': 'fast',
    'hwdec': 'auto-safe',
    'vo': 'gpu',
    'scale': 'bilinear',
    'cscale': 'bilinear',
    'dscale': 'bilinear',
    'correct-downscaling': 'no',
    'sigmoid-upscaling': 'no',
    'deband': 'no',
    'video-sync': 'display-resample',
    'interpolation': 'no',
  },
  // 通用（Android / macOS / Linux）balanced 档，完整覆盖 profile/scale 等参数。
  'balanced': {
    'profile': 'gpu-hq',
    'hwdec': 'auto-safe',
    'vo': 'gpu',
    'scale': 'spline36',
    'cscale': 'spline36',
    'dscale': 'mitchell',
    'deband': 'no',
    'video-sync': 'display-resample',
    'interpolation': 'no',
  },
  // Windows 专用 balanced 档：刻意留空。
  //
  // 原因：Windows 上若同时通过 VideoControllerConfiguration（media_kit 纹理层）
  // 和 mpv setProperty（applyMpvOptions）两条路径下发 hwdec/vo，两层配置会打架，
  // 表现为运动画面出现规律性拖影/残影（本质是硬解路径与纹理渲染不同步导致
  // 丢帧/复制帧）。参考 dart_simple_live 项目的 mpv_options_service.dart 中
  // 同样的处理方式：Windows + balanced 时不下发这些参数，让 VideoController
  // 走 media_kit 默认路径，避免冲突。
  'balancedWindows': <String, String>{},
  'quality': {
    'profile': 'gpu-hq',
    'hwdec': 'auto-safe',
    'vo': 'gpu-next',
    'scale': 'ewa_lanczossharp',
    'cscale': 'ewa_lanczossoft',
    'dscale': 'mitchell',
    'correct-downscaling': 'yes',
    'sigmoid-upscaling': 'yes',
    'deband': 'yes',
    'video-sync': 'display-resample',
    'interpolation': 'no',
  },
};

/// 按平台解析 profile 实际应使用的参数表。
///
/// Windows + 'balanced' 走精简版（'balancedWindows'，空表），
/// 其它平台或其它 profile 名照常查表。
Map<String, String> _profileOptionsForPlatform(String profile) {
  if (profile == 'balanced' && Platform.isWindows) {
    return mpvProfiles['balancedWindows']!;
  }
  return mpvProfiles[profile] ?? mpvProfiles['balanced']!;
}

/// 去交错（deinterlace）设置，独立于 [mpvProfiles]，三档画质预设 + Windows
/// 精简档统一叠加，不受 [_profileOptionsForPlatform] 里"Windows balanced 留空"
/// 逻辑的影响。
///
/// 背景：不少 IPTV/电视直播源（尤其体育赛事）源头是隔行扫描（如 1080i），
/// 画面本身由奇偶两个不同时间点的半场行交织而成。用逐行方式直接播放不做
/// 去交错处理时，运动物体边缘会出现规律的梳齿状条纹（combing artifact）——
/// 具体表现为等间距的平行细纹叠在运动人物/物体上，跟普通的运动模糊或丢帧
/// 拖影观感不同。这与画质预设中的 scale/hwdec 无关，三档画质、软硬解都无法
/// 解决，因为问题出在缩放/解码之前的"这一帧原始数据本身就是交错的"这一步。
///
/// mpv 的 deinterlace 属性只接受 yes/no/auto 三个值（没有 auto-safe）。
/// auto 依赖 mpv 自动检测流的隔行标记，但不少 IPTV 转码流不携带准确的隔行
/// 元数据，会导致检测失败、实际不生效；直接设为 yes 强制开启 yadif 滤镜更
/// 可靠。对本来就是逐行（progressive）的源，yadif 在无交错内容上是安全的
/// 空操作，不会引入额外伪影，代价是极小的额外 CPU/GPU 开销，可接受。
const Map<String, String> _deinterlaceOptions = {
  'deinterlace': 'yes',
};

/// 备用去交错方案：显式插入 yadif 滤镜到 vf 链。
///
/// 背景：'deinterlace' 属性在部分硬解路径（尤其 hwdec=auto-safe 走
/// d3d11va/GPU 纹理直出）下，属性设置可能"成功"但实际不生效——因为
/// 硬解输出直接进纹理管线，没有经过软件滤镜链，deinterlace 属性联动的
/// 内部滤镜插入逻辑被绕开。显式 --vf=yadif 是插入一个具体滤镜，
/// 语义更明确，多数情况下比 deinterlace 属性更可靠。
/// 代价：yadif 是纯 CPU/软件滤镜，会强制画面数据从 GPU 纹理路径拉回
/// 一次做处理，对纯硬解直出场景有一定性能开销，但对本来就有隔行梳齿
/// 问题的直播源，正确显示优先于极致性能。
const Map<String, String> _deinterlaceVfOptions = {
  'vf': 'yadif',
};

/// TS/HLS 流容错选项，独立于去交错设置，用于缓解 IPTV 转发链路常见的
/// 丢包/切片不完整问题。
///
/// 背景（实测确认，见 mpv --msg-level=all=v 命令行日志）：部分 IPTV 转发
/// 源在 HLS 切片刚建立连接、或转发链路本身不稳定丢包时，H.264 解码器会
/// 报 "non-existing PPS 0 referenced" / "no frame!"——即解码器拿到的
/// 码流缺少必要的参数集（SPS/PPS）或参考帧数据不完整。这与去交错完全是
/// 两类问题：去交错处理的是"完整但交错的两场画面"，而这里是"数据本身
/// 就残缺"，会在运动区域表现出块状/线状伪影，肉眼观感与隔行交错的梳齿
/// 条纹相似，容易混淆，但成因和修复方式都不同——去交错滤镜对这类问题
/// 无效。
///
/// 这里做两件事：
/// 1. 增大 demuxer 读取缓冲（cache/readahead），让解码器有更多机会在
///    连接抖动/短暂丢包时等到完整数据，而不是立刻用残缺数据尝试解码。
/// 2. 允许解码器在遇到错误宏块时做错误隐藏（error concealment）并继续
///    渲染后续帧，而不是让错误持续累积到肉眼可见的画面损坏。
///
/// 代价：增大缓冲会略微增加直播的显示延迟（通常几百毫秒级别，直播场景
/// 一般可接受）。
const Map<String, String> _tsResilienceOptions = {
  // 增大 demuxer 缓存队列上限（默认较小，网络抖动时容易触发用残缺数据
  // 硬解的情况）。单位为字节，150MiB 是留有余量但不至于占用过多内存的
  // 折中值。
  'demuxer-max-bytes': '157286400',
  'demuxer-max-back-bytes': '52428800',
  // 直播流优先保证连续性，网络抖动时允许 mpv 主动多缓冲一点再播放。
  'cache': 'yes',
  'cache-secs': '10',
};

/// Build a [VideoControllerConfiguration] for the MPV backend from user settings.
/// 调用方传入相关布尔值，使此函数保持无依赖。
VideoControllerConfiguration buildControllerConfig({
  required bool hardwareDecode,
  required bool compatMode,
  required String profile,
}) {
  final p = _profileOptionsForPlatform(profile);

  if (compatMode && Platform.isAndroid) {
    return const VideoControllerConfiguration(
      vo: 'mediacodec_embed',
      hwdec: 'mediacodec',
    );
  }

  if (Platform.isAndroid) {
    return VideoControllerConfiguration(
      vo: p['vo'],
      hwdec: p['hwdec'],
      enableHardwareAcceleration: hardwareDecode,
      androidAttachSurfaceAfterVideoParameters: true,
    );
  }

  // Windows + balanced（精简档）：p['hwdec'] 本就是 null（空表取不到值），
  // 这里显式不覆盖，让 VideoController 走 media_kit 默认硬解协商路径，
  // 不与 applyMpvOptions 里 mpv 侧的设置产生冲突。
  //
  // 重要修正：之前这里的 hwdec 只取自画质 profile（如 'auto-safe'），跟
  // hardwareDecode 这个"硬件解码"开关完全没有联动——用户关闭硬件解码时，
  // 只是关掉了 media_kit_video 层的 GPU 纹理渲染路径
  // （enableHardwareAcceleration），mpv 内部依然在用 hwdec=auto-safe 尝试
  // 协商硬件解码器（如 Windows 上的 d3d11va），只是解码完的画面改用 CPU
  // 拷贝方式传回。也就是说"关闭硬件解码"这个开关此前并没有真正让 mpv
  // 停止使用硬件解码器，测试"软解"时实际上完全没有测到真正的软解路径。
  //
  // Windows 上 ANGLE（OpenGL→D3D 转换层）+ D3D11VA 硬解组合在部分 GPU/
  // 驱动上有已知的画面异常问题（mpv 官方 issue #3255 等），运动画面出现
  // 多重错位重影就是其中一种典型表现，纯软解通常可以绕开。因此这里让
  // hardwareDecode=false 时，hwdec 强制传 'no'，确保 mpv 内部也真正禁用
  // 硬件解码协商，而不只是关闭渲染层加速。
  return VideoControllerConfiguration(
    hwdec: hardwareDecode ? p['hwdec'] : 'no',
    enableHardwareAcceleration: hardwareDecode,
  );
}

/// 将 mpv profile 中除 vo/hwdec 之外的参数写入播放器，并统一叠加去交错设置。
/// 保留旧签名（接收 [Player]），便于现有调用点继续使用；
/// 调用方需保证传入的 player 来自 [MpvBackend.player]。
///
/// [hardwareDecode] 为 false 时会在运行期再显式 setProperty('hwdec', 'no')
/// 一次，跟 [buildControllerConfig] 里创建 VideoController 时传入的值保持
/// 一致——[VideoControllerConfiguration.hwdec] 只在创建 VideoController 那
/// 一刻生效一次，不是持续生效的运行期属性，这里做双重保险，避免后续任何
/// 逻辑（如切源、重新 open）时硬解协商又被重新触发。
Future<void> applyMpvOptions(
  Player player,
  String profile, {
  bool hardwareDecode = true,
  bool forceDeinterlaceFilter = false,
  bool forceTsResilience = false,
}) async {
  if (Platform.isIOS) return;
  if (player.platform is! NativePlayer) return;
  final opts = Map<String, String>.from(_profileOptionsForPlatform(profile))
    ..remove('vo')
    ..remove('hwdec')
    // 去交错独立于画质预设，三档 + Windows 精简档都要生效，故在这里统一
    // 叠加，即使某档位（如 Windows balanced）本身是空表也不受影响。
    ..addAll(_deinterlaceOptions);
  if (forceTsResilience) {
    opts.addAll(_tsResilienceOptions);
  }
  if (!hardwareDecode) {
    opts['hwdec'] = 'no';
  }
  for (final e in opts.entries) {
    try {
      await (player.platform as dynamic).setProperty(e.key, e.value);
    } catch (_) {
      // 单个 property 设置失败不影响其余 property。
    }
  }

  // ── 强制去交错滤镜（独立于上面的 setProperty 循环） ──────────────────
  //
  // 硬解路径下 'deinterlace' 属性可能不可靠（见 _deinterlaceVfOptions
  // 注释）。这里不再用 setProperty('vf', 'yadif') ——mpv 的 vf 是滤镜
  // 链，运行期用 set_property 直接整体赋值在部分版本/时机下可能被
  // 静默忽略或不生效（这更像是启动参数的写法）；改用 mpv 官方推荐的
  // 运行期滤镜操作命令 vf-add，语义是"插入一个滤镜"，更贴近 mpv 内部
  // 实际处理滤镜链的方式，可靠性更高。同时保留 setProperty 方式作为
  // 兜底（万一 command 调用在某个 media_kit 版本下不可用）。
  //
  // 重要更正（实测踩坑记录，务必保留）：yadif 滤镜的真实参数只有
  // mode / parity / deint 三个（FFmpeg 官方文档 + libavfilter 源码
  // yadif_common.c 确认），deint 的取值只有 all（强制处理所有帧，
  // 不管是否带隔行标记）或 interlaced（仅处理带隔行标记的帧）。
  // 此前版本误加了一个不存在的 interlaced-only 选项，命令行实测
  // （mpv --msg-level=all=v）证实这会导致 FFmpeg 直接报
  // "AVOption 'interlaced-only' not found" 并让整个滤镜创建失败
  // （'Creating filter yadif failed'），进而使视频轨道被完全禁用
  // （'Video: no video'）——而 media_kit 的 command() 调用本身仍会
  // 返回成功、不会抛出异常，导致应用层日志显示 vf-add ... OK，
  // 是一个非常隐蔽的"看似生效、实则整条视频轨道被关闭"的假成功。
  // 正确写法只需 deint=all，本身就是"强制处理所有帧、不依赖流自身
  // 隔行标记是否可信"的语义，不需要也不能再加别的参数名。
  //
  // 默认关闭（forceDeinterlaceFilter=false），避免无隔行问题的源被
  // 强制拉入软件滤镜链造成不必要的性能开销；仅在确认 deinterlace 属性
  // 不生效、或用户主动开启"强制去交错"选项时传 true。
  if (forceDeinterlaceFilter) {
    final native = player.platform as NativePlayer;
    const filterSpec = 'yadif=deint=all';
    try {
      await native.command(['vf-add', filterSpec]);
    } catch (_) {
      // vf-add 失败时回退到 setProperty('vf', ...)
      try {
        await (player.platform as dynamic).setProperty('vf', filterSpec);
      } catch (_) {
        // 两种方式都失败则放弃，不影响播放主流程。
      }
    }
  }
}

// ── Backend factory ─────────────────────────────────────────────────────────

/// 根据 settings 构造一个 [PlayerBackend]。
///
/// - 当 [useExo] 为 true 且当前平台支持 ExoPlayer 时返回 ExoBackend（由调用
///   方注入工厂，避免 player_shared 直接依赖 video_player）；
/// - 当 [useVlc] 为 true 且 [vlcFactory] 不为空时返回 VlcBackend（由调用方
///   注入工厂，避免 player_shared 直接依赖 flutter_vlc_player）；
/// - 否则返回 MpvBackend，并应用 mpv 的硬件解码 / 兼容模式 / profile。
///
/// 调用方（Android / Android TV app）通过注入 [exoFactory] 来提供 ExoBackend
/// 实例，因为 video_player 包并不在 player_shared 的依赖中。
/// Windows app 通过注入 [vlcFactory] 来提供 VlcBackend 实例，因为
/// flutter_vlc_player 包并不在 player_shared 的依赖中。
PlayerBackend buildBackend({
  required bool useExo,
  required bool hardwareDecode,
  required bool compatMode,
  required String profile,
  PlayerBackendFactory? exoFactory,
  bool useVlc = false,
  PlayerBackendFactory? vlcFactory,
}) {
  if (useVlc && vlcFactory != null) {
    return vlcFactory();
  }
  if (useExo && exoFactory != null) {
    return exoFactory();
  }
  final mpv = MpvBackend();
  mpv.attachVideoController(buildControllerConfig(
    hardwareDecode: hardwareDecode,
    compatMode: compatMode,
    profile: profile,
  ));
  return mpv;
}

/// 工厂类型：返回一个 PlayerBackend 实例（ExoBackend / VlcBackend 等）。
/// 由各 app 注入。
typedef PlayerBackendFactory = PlayerBackend Function();

// ── PlayerMixin ──────────────────────────────────────────────────────────────

/// Low-level player backend creation and disposal.
/// Mix into GetxControllers that need a video player.
///
/// 重构后推荐通过 [backend] 访问播放器能力；同时保留 [player] /
/// [videoController] 两个 legacy getter 供尚未迁移到 backend 抽象的旧
/// 代码（如 Windows 端）继续使用——这两个 getter 仅在 MPV 后端下可用。
mixin PlayerMixin {
  final GlobalKey playerKey = GlobalKey();

  late PlayerBackend backend;

  /// 是否 MPV 后端（便于上层做差异化逻辑）。
  bool get isMpv => backend.type == PlayerBackendType.mpv;

  /// 若当前是 MPV 后端，返回 [MpvBackend] 实例，否则返回 null。
  MpvBackend? get mpvBackend =>
      backend is MpvBackend ? backend as MpvBackend : null;

  /// Legacy: 直接访问底层 media_kit [Player]。
  /// 仅在 MPV 后端下可用（Windows 端旧代码继续使用）。
  /// 新代码请通过 [backend] 访问。
  Player get player {
    final mpv = mpvBackend;
    if (mpv == null) {
      throw StateError(
          'player getter 仅在 MPV 后端可用；当前后端为 ${backend.type}，'
          '请改用 backend 抽象接口');
    }
    return mpv.player;
  }

  /// Legacy: 直接访问 media_kit [VideoController]。
  /// 仅在 MPV 后端下可用。新代码请使用 [backend].buildView()。
  VideoController get videoController {
    final mpv = mpvBackend;
    if (mpv == null) {
      throw StateError(
          'videoController getter 仅在 MPV 后端可用；当前后端为 ${backend.type}，'
          '请改用 backend.buildView()');
    }
    return mpv.videoController;
  }

  /// 初始化播放器后端。
  ///
  /// 支持两种调用方式（二选一）：
  /// - **新代码**：传 [backend]，由调用方通过 [buildBackend] 构造好注入。
  /// - **Legacy**：传 [config]（mpv 的 [VideoControllerConfiguration]），
  ///   内部会创建一个 [MpvBackend]。Windows 端旧代码继续使用此方式。
  Future<void> initPlayer({
    PlayerBackend? backend,
    VideoControllerConfiguration? config,
  }) async {
    assert((backend != null) ^ (config != null),
        'initPlayer 必须且只能提供 backend 或 config 之一');
    if (backend != null) {
      this.backend = backend;
    } else if (config != null) {
      final mpv = MpvBackend();
      mpv.attachVideoController(config);
      this.backend = mpv;
    }
    if (isMpv) {
      // 兼容旧行为：Android 上启用 force-seekable
      if (Platform.isAndroid) {
        try {
          await (mpvBackend!.player.platform as NativePlayer)
              .setProperty('force-seekable', 'yes');
        } catch (_) {}
      }
    }
    await WakelockPlus.enable();
  }

  Future<void> disposePlayer() async {
    await backend.dispose();
    await WakelockPlus.disable();
  }
}

// ── PlayerStateMixin (touch gesture controls) ────────────────────────────────

/// UI state + touch-gesture helpers for non-TV players.
mixin PlayerStateMixin on PlayerMixin {
  final RxBool showControls    = true.obs;
  final RxBool isFullScreen    = false.obs;
  final RxBool showGestureTip  = false.obs;
  final RxString gestureTipText = ''.obs;

  Timer? _hideTimer;
  Timer? _tipTimer;

  double? _gestureStartBrightness;
  double? _gestureStartVolume;
  double? _gestureStartPosition;

  void autoHideControls({int seconds = 4}) {
    _hideTimer?.cancel();
    showControls.value = true;
    _hideTimer = Timer(Duration(seconds: seconds), () {
      showControls.value = false;
    });
  }

  void toggleControls() {
    if (showControls.value) {
      _hideTimer?.cancel();
      showControls.value = false;
    } else {
      autoHideControls();
    }
  }

  void showTip(String text) {
    gestureTipText.value = text;
    showGestureTip.value = true;
    _tipTimer?.cancel();
    _tipTimer = Timer(const Duration(milliseconds: 800), () {
      showGestureTip.value = false;
    });
  }

  // Brightness
  Future<void> onBrightnessGestureStart() async {
    _gestureStartBrightness = await ScreenBrightness().application;
  }

  void onBrightnessGestureUpdate(double delta) async {
    final val = ((_gestureStartBrightness ?? 0.5) + delta).clamp(0.0, 1.0);
    await ScreenBrightness().setApplicationScreenBrightness(val);
    showTip('亮度 ${(val * 100).round()}%');
  }

  // Volume
  Future<void> onVolumeGestureStart() async {
    _gestureStartVolume = await VolumeController.instance.getVolume();
  }

  void onVolumeGestureUpdate(double delta) {
    final val = ((_gestureStartVolume ?? 0.5) + delta).clamp(0.0, 1.0);
    VolumeController.instance.setVolume(val);
    showTip('音量 ${(val * 100).round()}%');
  }

  // Seek
  void onSeekGestureStart() {
    _gestureStartPosition = backend.currentPosition.inSeconds.toDouble();
  }

  void onSeekGestureUpdate(double deltaSeconds) {
    final target = ((_gestureStartPosition ?? 0) + deltaSeconds)
        .clamp(0.0, backend.currentDuration.inSeconds.toDouble());
    showTip(_fmtSeconds(target));
  }

  void onSeekGestureEnd(double deltaSeconds) {
    final dur = backend.currentDuration.inSeconds.toDouble();
    final target =
        ((_gestureStartPosition ?? 0) + deltaSeconds).clamp(0.0, dur);
    backend.seek(Duration(seconds: target.round()));
  }

  String _fmtSeconds(double s) {
    final d = Duration(seconds: s.round());
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final sec = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$sec' : '$m:$sec';
  }
}

// ── TV PlayerStateMixin (d-pad, no gesture) ──────────────────────────────────

/// Simpler controls state for TV (no brightness/volume gesture).
mixin TvPlayerStateMixin on PlayerMixin {
  final RxBool showControls = true.obs;
  Timer? _hideTimer;

  void autoHideControls({int seconds = 4}) {
    _hideTimer?.cancel();
    showControls.value = true;
    _hideTimer = Timer(Duration(seconds: seconds), () {
      showControls.value = false;
    });
  }

  void toggleControls() {
    if (showControls.value) {
      _hideTimer?.cancel();
      showControls.value = false;
    } else {
      autoHideControls();
    }
  }

  void cancelHideTimer() {
    _hideTimer?.cancel();
    showControls.value = true;
  }
}
