import 'package:get/get.dart';
import 'package:player_shared/player_shared.dart';

import 'package:nexus_tv/app/controller/tv_settings_controller.dart';
import 'package:nexus_tv/player/exo_backend.dart';
import 'package:nexus_tv/modules/music/player/tv_music_player_page.dart'
    show TvMusicPlayerController;

/// TV 视频播放控制器,支持播放列表切换。
///
/// 重构后通过 [PlayerBackend] 抽象同时支持 MPV 与 ExoPlayer 两种后端，
/// 由设置中的"播放器后端"决定（auto 模式下本地视频默认 ExoPlayer）。
class TvVideoPlayerController extends GetxController
    with PlayerMixin, TvPlayerStateMixin {
  late List<Map<String, String>> playlist;

  final RxInt currentIdx = 0.obs;
  final isPlaying   = false.obs;
  final isBuffering = false.obs;
  final position    = Duration.zero.obs;
  final duration    = Duration.zero.obs;

  /// 播放列表弹窗是否显示(菜单键唤出)
  final RxBool showPlaylist = false.obs;

  String get title =>
      playlist.isEmpty ? '视频' : playlist[currentIdx.value]['name'] ?? '视频';

  String get currentPath =>
      playlist.isEmpty ? '' : playlist[currentIdx.value]['path'] ?? '';

  /// 顶部播放入口恢复播放时携带的初始跳转位置（仅首次打开生效一次）。
  Duration? _resumePosition;

  @override
  void onInit() {
    super.onInit();
    // 媒体互斥：开始播放视频前，先停止可能正在播放的音乐。
    if (Get.isRegistered<TvMusicPlayerController>()) {
      TvMusicPlayerController.instance.stopForOtherMedia();
    }
    // 视频开始播放意味着不再需要展示"上次退出的视频/IPTV"快照。
    PlaybackBarController.instance.clear();

    final args = Get.arguments as Map<String, dynamic>? ?? {};
    playlist = List<Map<String, String>>.from(
        (args['playlist'] as List?)?.map((e) => Map<String, String>.from(e)) ??
            []);
    currentIdx.value = args['index'] as int? ?? 0;
    _resumePosition = args['resumePosition'] as Duration?;

    final s = TvSettingsController.instance;
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
    b.playing.listen((v)   => isPlaying.value   = v);
    b.buffering.listen((v) => isBuffering.value = v);
    b.position.listen((v)  => position.value    = v);
    b.duration.listen((v)  => duration.value    = v);
    b.completed.listen((c) {
      if (c) _onCompleted();
    });

    initPlayer(backend: b).then((_) async {
      final mpv = mpvBackend;
      if (mpv != null) {
        await applyMpvOptions(mpv.player, s.mpvProfile.value);
      }
      await _playAt(currentIdx.value, seekTo: _resumePosition);
      autoHideControls();
    });
  }

  Future<void> _playAt(int index, {Duration? seekTo}) async {
    if (playlist.isEmpty || index < 0 || index >= playlist.length) return;
    currentIdx.value = index;
    final path = currentPath;
    if (path.isEmpty) return;
    await backend.open(path);
    if (seekTo != null && seekTo > Duration.zero) {
      await backend.seek(seekTo);
    }
    s_addRecent(path);
    autoHideControls();
  }

  void s_addRecent(String path) {
    try {
      TvSettingsController.instance.addRecentFile(path);
    } catch (_) {}
  }

  void _onCompleted() {
    // 顺序播放下一集
    if (playlist.length > 1) {
      _playAt((currentIdx.value + 1) % playlist.length);
    }
  }

  void togglePlay() => backend.playOrPause();

  void seekRelative(int seconds) {
    final target  = backend.currentPosition + Duration(seconds: seconds);
    final dur     = backend.currentDuration;
    final clamped = target.isNegative
        ? Duration.zero
        : (target > dur ? dur : target);
    backend.seek(clamped);
  }

  void playAt(int i) => _playAt(i);

  void next() {
    if (playlist.isEmpty) return;
    _playAt((currentIdx.value + 1) % playlist.length);
  }

  void prev() {
    if (playlist.isEmpty) return;
    _playAt((currentIdx.value - 1 + playlist.length) % playlist.length);
  }

  void togglePlaylist() => showPlaylist.value = !showPlaylist.value;

  @override
  void onClose() {
    // 退出播放页即停止播放，但把"足够恢复"的信息存进全局播放状态，
    // 以便顶部播放入口展示，并在用户点击时从原进度继续播放。
    if (playlist.isNotEmpty && title.isNotEmpty && title != '视频') {
      PlaybackBarController.instance.saveVideoSnapshot(
        title: title,
        path: currentPath,
        position: position.value,
        duration: duration.value,
        playlist: playlist,
        index: currentIdx.value,
      );
    }
    disposePlayer();
    super.onClose();
  }
}
