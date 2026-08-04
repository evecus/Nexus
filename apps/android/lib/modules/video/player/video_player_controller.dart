import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:player_shared/player_shared.dart';

import 'package:nexus/app/controller/app_settings_controller.dart';
import 'package:nexus/player/exo_backend.dart';
import 'package:nexus/modules/music/player/music_player_page.dart'
    show MusicPlayerController;

/// 视频播放器控制器,完全照抄 NovaBox 的 `LocalPlayerActivity` 逻辑。
///
/// - 支持单文件 / 文件夹播放列表模式
/// - 自动播放下一首(完成后),不循环
/// - 锁屏控制(隐藏控件)
/// - 全屏切换(横屏 + 沉浸式)
/// - 手势:亮度 / 音量 / 进度(参考 player_shared 的 PlayerStateMixin)
///
/// 重构后通过 [PlayerBackend] 抽象同时支持 MPV 与 ExoPlayer 两种后端，
/// 由设置中的"播放器后端"决定（auto 模式下本地视频默认 ExoPlayer）。
class VideoPlayerController extends GetxController
    with PlayerMixin, PlayerStateMixin {
  static VideoPlayerController get instance =>
      Get.find<VideoPlayerController>();

  late List<Map<String, String>> playlist;
  final RxInt currentIndex = 0.obs;

  final RxBool isPlaying = false.obs;
  final RxBool isBuffering = false.obs;
  final Rx<Duration> position = Duration.zero.obs;
  final Rx<Duration> duration = Duration.zero.obs;
  final RxDouble playSpeed = 1.0.obs;
  final RxBool isLocked = false.obs;
  final RxBool isCompleted = false.obs;

  String get title {
    if (playlist.isEmpty) return '';
    return playlist[currentIndex.value]['name'] ?? '';
  }

  String get currentPath {
    if (playlist.isEmpty) return '';
    return playlist[currentIndex.value]['path'] ?? '';
  }

  @override
  void onInit() {
    super.onInit();
    // 媒体互斥：开始播放视频前，先停止可能正在播放的音乐。
    if (Get.isRegistered<MusicPlayerController>()) {
      MusicPlayerController.instance.stopForOtherMedia();
    }
    // 视频开始播放意味着不再需要展示"上次退出的视频/IPTV"快照
    // （即将被新的播放进度覆盖，若中途又退出会重新写入）。
    PlaybackBarController.instance.clear();

    final args = Get.arguments as Map<String, dynamic>? ?? {};
    playlist = List<Map<String, String>>.from(
        (args['playlist'] as List?)?.map((e) => Map<String, String>.from(e)) ??
            []);
    final idx = args['index'] as int? ?? 0;
    currentIndex.value =
        idx.clamp(0, playlist.isEmpty ? 0 : playlist.length - 1);
    // 从迷你播放栏恢复播放时携带的初始进度（可选）。
    _resumePosition = args['resumePosition'] as Duration?;

    final s = AppSettingsController.instance;
    // 本地视频场景：auto 模式下默认走 ExoPlayer
    final useExo = s.shouldUseExo(isIptv: false);
    final b = buildBackend(
      useExo: useExo,
      hardwareDecode: s.hardwareDecode.value,
      compatMode: s.compatMode.value,
      profile: s.mpvProfile.value,
      exoFactory: () => ExoBackend(),
    );

    // 注意：backend 字段是 late，在 initPlayer 内部才会赋值，
    // 所以这里用局部变量 b 来订阅流，避免 LateInitializationError。
    b.playing.listen((v) => isPlaying.value = v);
    b.buffering.listen((v) => isBuffering.value = v);
    b.position.listen((v) => position.value = v);
    b.duration.listen((v) => duration.value = v);
    b.completed.listen((completed) {
      if (completed) _onCompleted();
    });

    initPlayer(backend: b).then((_) async {
      // 仅 MPV 后端需要应用 profile 选项
      final mpv = mpvBackend;
      if (mpv != null) {
        await applyMpvOptions(mpv.player, s.mpvProfile.value);
      }
      await _playAt(currentIndex.value, seekTo: _resumePosition);
      autoHideControls();
    });
  }

  /// 迷你播放栏恢复播放时携带的初始跳转位置（仅首次打开生效一次）。
  Duration? _resumePosition;

  Future<void> _playAt(int index, {Duration? seekTo}) async {
    if (playlist.isEmpty || index < 0 || index >= playlist.length) return;
    currentIndex.value = index;
    isCompleted.value = false;
    final path = playlist[index]['path'] ?? '';
    if (path.isEmpty) return;
    await backend.open(path);
    if (seekTo != null && seekTo > Duration.zero) {
      await backend.seek(seekTo);
    }
    final s = AppSettingsController.instance;
    s.addRecentFile(path);
  }

  void _onCompleted() {
    isCompleted.value = true;
    final next = currentIndex.value + 1;
    if (next < playlist.length) {
      _playAt(next);
    }
  }

  void playAt(int index) => _playAt(index);

  /// 下一首(若存在)。NovaBox 不支持循环,这里保持一致。
  void next() {
    final n = currentIndex.value + 1;
    if (n < playlist.length) _playAt(n);
  }

  /// 上一首(NovaBox 未实现上一首;此处补充以便 UI 完整)。
  void prev() {
    final n = currentIndex.value - 1;
    if (n >= 0) _playAt(n);
  }

  void togglePlay() => backend.playOrPause();
  void seekTo(Duration d) => backend.seek(d);
  void setSpeed(double s) {
    playSpeed.value = s;
    backend.setRate(s);
  }

  void toggleLock() {
    isLocked.value = !isLocked.value;
    if (isLocked.value) {
      // 锁定后立即隐藏除锁按钮外的所有控件,并保持隐藏
      showControls.value = false;
    } else {
      autoHideControls();
    }
  }

  void enterFullScreen() {
    if (isFullScreen.value) return;
    isFullScreen.value = true;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations(
        _resolveFullScreenOrientations(isIptv: false));
  }

  void exitFullScreen() {
    if (!isFullScreen.value) return;
    isFullScreen.value = false;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  /// 根据全屏播放方向设置计算应锁定的屏幕方向列表。
  /// [isIptv] 为 true 时表示 IPTV 场景（auto 模式默认横屏，因为电视直播基本都是横屏）。
  List<DeviceOrientation> _resolveFullScreenOrientations({required bool isIptv}) {
    final mode = AppSettingsController.instance.fullScreenOrientation.value;
    switch (mode) {
      case FullScreenOrientationMode.portrait:
        // 始终保持竖屏，不旋转
        return [DeviceOrientation.portraitUp];
      case FullScreenOrientationMode.landscape:
        // 始终旋转到横屏（默认行为）
        return [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight];
      case FullScreenOrientationMode.sensor:
        // 跟随传感器，允许四方向自由旋转
        return [
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ];
      case FullScreenOrientationMode.auto:
        if (isIptv) {
          // IPTV 直播几乎全是横屏内容，auto 模式默认横屏
          return [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight];
        }
        // 本地视频：读取视频原始分辨率判断横竖屏
        final size = backend.videoNativeSize;
        final isLandscapeVideo = size == Size.zero || size.width >= size.height;
        if (isLandscapeVideo) {
          return [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight];
        } else {
          return [DeviceOrientation.portraitUp];
        }
    }
  }

  void toggleFullScreen() {
    if (isFullScreen.value) {
      exitFullScreen();
    } else {
      enterFullScreen();
    }
    autoHideControls();
  }

  @override
  void onClose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    // 退出播放页即停止播放，但把"足够恢复"的信息存进全局迷你播放栏，
    // 以便用户在首页点击播放栏时从原进度继续播放。
    if (playlist.isNotEmpty && title.isNotEmpty) {
      PlaybackBarController.instance.saveVideoSnapshot(
        title: title,
        path: currentPath,
        position: position.value,
        duration: duration.value,
        playlist: playlist,
        index: currentIndex.value,
      );
    }
    disposePlayer();
    super.onClose();
  }
}
