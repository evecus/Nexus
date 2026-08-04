import 'dart:typed_data';

import 'package:get/get.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;
import 'package:player_shared/player_shared.dart';

import 'app_settings_controller.dart';

/// 底部播放栏当前展示的内容类型。
enum MiniBarKind { none, video, iptv, music }

/// 音乐循环模式（与 MusicPlayerController 保持一致，供全局播放器使用）。
enum GlobalRepeatMode { list, shuffle, one }

/// 单曲元数据缓存（封面/歌词），迁移自原 MusicPlayerController。
class TrackMeta {
  final String? title;
  final String? artist;
  final Uint8List? coverBytes;
  final List<LrcLine> lrcLines;

  const TrackMeta({
    this.title,
    this.artist,
    this.coverBytes,
    this.lrcLines = const [],
  });
}

/// 全局播放状态控制器（Windows 端专用，permanent 单例）。
///
/// 职责：
/// - **音乐**：真正持有底层 mpv Player 实例，音乐播放贯穿全局生命周期——
///   离开音乐播放页不会停止播放，只有切到视频/IPTV 播放或退出程序才会停止。
///   四个主页面 + 音乐播放页共用同一个 Player。
/// - **视频 / IPTV**：不持有播放器（这两类退出播放页即停止播放），只记录
///   "恢复信息"（标题、地址、播放进度、播放列表/频道参数等），供底部播放栏
///   展示 + 点击后带着 resumePosition 重新进入播放页续播。
class GlobalPlayerController extends GetxController with PlayerMixin {
  static GlobalPlayerController get instance =>
      Get.find<GlobalPlayerController>();

  // ── 底部播放栏应该展示哪种内容 ─────────────────────────────────────────
  final miniBarKind = MiniBarKind.none.obs;

  // ══════════════════════════════════════════════════════════════════════
  //  视频 — 仅保存"恢复信息"，不持有播放器
  // ══════════════════════════════════════════════════════════════════════

  final videoTitle = ''.obs;
  final videoPosition = Duration.zero.obs;
  final videoDuration = Duration.zero.obs;

  /// 恢复播放所需的完整参数（url/title/isLocal/playlist/startIndex）。
  Map<String, dynamic>? _videoResumeArgs;

  void updateVideoState({
    required String title,
    required Duration position,
    required Duration duration,
    required Map<String, dynamic> resumeArgs,
  }) {
    videoTitle.value = title;
    videoPosition.value = position;
    videoDuration.value = duration;
    _videoResumeArgs = resumeArgs;
    // 视频是"最后一次进入/更新"的内容，应立即成为底部栏展示的目标，
    // 不应被此前遗留的 iptv/music 状态挡住（之前这里写反了，导致
    // 无论后面播放什么，底部栏永远卡在"最先设置"的那种类型上）。
    miniBarKind.value = MiniBarKind.video;
  }

  /// 视频播放页关闭时调用：只清掉"正在播放"态，恢复信息继续保留在底部栏。
  void onVideoPageClosed() {
    if (miniBarKind.value == MiniBarKind.video) {
      // 保留在 video 态，底部栏继续展示最后进度，只是不再"播放中"。
    }
  }

  void clearVideo() {
    _videoResumeArgs = null;
    videoTitle.value = '';
    if (miniBarKind.value == MiniBarKind.video) {
      miniBarKind.value = MiniBarKind.none;
    }
  }

  Map<String, dynamic>? get videoResumeArgs => _videoResumeArgs;

  // ══════════════════════════════════════════════════════════════════════
  //  IPTV — 同样只保存"恢复信息"
  // ══════════════════════════════════════════════════════════════════════

  final iptvChannelName = ''.obs;
  final iptvGroupName = ''.obs;

  Map<String, dynamic>? _iptvResumeArgs;

  void updateIptvState({
    required String channelName,
    required String groupName,
    required Map<String, dynamic> resumeArgs,
  }) {
    iptvChannelName.value = channelName;
    iptvGroupName.value = groupName;
    _iptvResumeArgs = resumeArgs;
    // 同上：IPTV 是当前正在播放/更新的内容，底部栏应立即切换展示它，
    // 不应被此前遗留的 video/music 状态挡住。
    miniBarKind.value = MiniBarKind.iptv;
  }

  void clearIptv() {
    _iptvResumeArgs = null;
    iptvChannelName.value = '';
    if (miniBarKind.value == MiniBarKind.iptv) {
      miniBarKind.value = MiniBarKind.none;
    }
  }

  Map<String, dynamic>? get iptvResumeArgs => _iptvResumeArgs;

  // ══════════════════════════════════════════════════════════════════════
  //  音乐 — 真正持有播放器，贯穿全局生命周期
  // ══════════════════════════════════════════════════════════════════════

  List<Map<String, String>> musicPlaylist = [];
  final musicCurrentIdx = 0.obs;
  final musicIsPlaying = false.obs;
  final musicIsBuffering = false.obs;
  final musicPosition = Duration.zero.obs;
  final musicDuration = Duration.zero.obs;
  final musicPlaySpeed = 1.0.obs;
  final musicRepeatMode = GlobalRepeatMode.list.obs;
  final musicVolume = 100.0.obs;
  final Rx<TrackMeta?> musicCurrentMeta = Rx<TrackMeta?>(null);
  final musicCurrentLrcIdx = (-1).obs;

  bool _musicInitialized = false;
  final List<int> _shuffleOrder = [];
  int _playGeneration = 0;
  bool _readyForCompleted = false;

  /// 音乐播放器是否已经初始化完成（可安全访问 [musicVideoController]）。
  /// 供 UI 层（如全局隐藏的 Video 挂载点）判断是否已经可以渲染。
  /// 用 .obs 而不是普通 bool，这样 _ensureMusicPlayer() 首次把它置
  /// true 时，Obx 包裹的隐藏 Video 挂载点能立刻感知并渲染出来，
  /// 不需要等待某次无关的其它状态变化才"顺带"重建。
  final musicPlayerReadyRx = false.obs;
  bool get musicPlayerReady => musicPlayerReadyRx.value;

  /// 音乐播放用的 VideoController（media_kit/mpv 在桌面端即使是纯音频
  /// 文件也依赖一个真实的渲染 Surface/纹理才能正常走通解码-播放管线；
  /// 如果从来没有任何 Video widget 使用过这个 controller，mpv 在部分
  /// 情况下会卡在"已加载但不真正推进播放"的状态，表现为：点击播放列表
  /// 里的歌曲后不会立即播放，需要手动点一次播放按钮才能真正出声。
  /// 通过在 HomePage 里挂一个 1x1 的隐藏 Video widget 绑定这个
  /// controller，保证渲染管线从一开始就是"活"的。
  VideoController get musicVideoController => videoController;

  String get musicCurrentTitle {
    final meta = musicCurrentMeta.value;
    if (meta?.title != null && meta!.title!.isNotEmpty) return meta.title!;
    if (musicPlaylist.isEmpty) return '';
    return p.withoutExtension(
        musicPlaylist[musicCurrentIdx.value]['name'] ?? '');
  }

  String get musicCurrentArtist => musicCurrentMeta.value?.artist ?? '';

  /// 提前初始化音乐播放器（不开始播放任何东西），只为了让底层 mpv
  /// Player/VideoController 尽早创建好，从而让全局隐藏的 Video 挂载点
  /// （见 home_page.dart 的 _HiddenMusicVideoSink）尽早绑定上真实的
  /// 渲染纹理。应在 App 启动、进入主页面时调用一次即可，之后
  /// _ensureMusicPlayer() 里的幂等检查会保证不会重复创建。
  ///
  /// 这是修复"点击歌曲不会立即播放，需要手动点一次播放按钮"问题的
  /// 关键一环：如果直到用户点第一首歌才去创建 Player + VideoController，
  /// Video widget 的挂载和 player.open() 之间就会有一次竞态——挂载点的
  /// 重建要等 Obx 下一帧才处理，而 player.open() 几乎是立刻发出的，
  /// mpv 在还没有真正的渲染 Surface 时收到播放指令，容易卡在"已加载
  /// 但未真正播放"的状态。提前预热则完全避免了这个时序问题。
  Future<void> warmupMusicPlayer() => _ensureMusicPlayer();

  /// 由 MusicTabPage / MusicPlayerPage 调用：开始播放一份新的播放列表。
  Future<void> playMusicPlaylist(
    List<Map<String, String>> playlist,
    int index,
  ) async {
    if (playlist.isEmpty) return;

    // 切到音乐：先停掉视频/IPTV 的"正在播放"状态展示（它们本身在各自
    // 页面 dispose 时已经停止播放，这里只是确保底部栏切换到音乐）。
    await _ensureMusicPlayer();

    musicPlaylist = playlist;
    final clamped = index.clamp(0, playlist.length - 1);
    _buildShuffleOrder();
    miniBarKind.value = MiniBarKind.music;
    await _playAt(clamped);
  }

  Future<void> _ensureMusicPlayer() async {
    if (_musicInitialized) return;
    _musicInitialized = true;

    final s = AppSettingsController.instance;
    final config = buildControllerConfig(
      hardwareDecode: s.hardwareDecode.value,
      compatMode: false,
      profile: s.mpvProfile.value,
    );
    await initPlayer(config: config);

    player.stream.playing.listen((v) => musicIsPlaying.value = v);
    player.stream.buffering.listen((v) => musicIsBuffering.value = v);
    player.stream.position.listen((v) {
      musicPosition.value = v;
      _updateLrcIndex(v);
    });
    player.stream.duration.listen((v) => musicDuration.value = v);
    player.stream.volume.listen((v) => musicVolume.value = v);
    player.stream.completed.listen((_) => _onCompleted());

    // 标记为就绪，触发全局隐藏 Video 挂载点渲染出来，保活 mpv 渲染管线
    // （见 musicPlayerReadyRx 的注释）。必须放在上面这些 listen() 之后，
    // 确保挂载点渲染时 backend/videoController 都已经就绪可用。
    musicPlayerReadyRx.value = true;
  }

  Future<void> _playAt(int index) async {
    if (musicPlaylist.isEmpty) return;
    final gen = ++_playGeneration;
    _readyForCompleted = false;
    musicCurrentIdx.value = index;
    musicCurrentMeta.value = null;
    musicCurrentLrcIdx.value = -1;
    await player.open(Media(musicPlaylist[index]['path']!));
    if (gen != _playGeneration) return;
    _loadMeta(musicPlaylist[index]['path']!);
    Future.delayed(const Duration(milliseconds: 500), () {
      if (gen == _playGeneration) _readyForCompleted = true;
    });
  }

  void _onCompleted() {
    if (!_readyForCompleted) return;
    _readyForCompleted = false;
    switch (musicRepeatMode.value) {
      case GlobalRepeatMode.one:
        _playAt(musicCurrentIdx.value);
        break;
      case GlobalRepeatMode.shuffle:
        _playAt(_shuffleNext(1));
        break;
      case GlobalRepeatMode.list:
        _playAt((musicCurrentIdx.value + 1) % musicPlaylist.length);
        break;
    }
  }

  void musicPrevious() {
    if (musicPlaylist.isEmpty) return;
    if (musicRepeatMode.value == GlobalRepeatMode.shuffle) {
      _playAt(_shuffleNext(-1));
    } else {
      _playAt((musicCurrentIdx.value - 1 + musicPlaylist.length) %
          musicPlaylist.length);
    }
  }

  void musicNext() {
    if (musicPlaylist.isEmpty) return;
    if (musicRepeatMode.value == GlobalRepeatMode.shuffle) {
      _playAt(_shuffleNext(1));
    } else {
      _playAt((musicCurrentIdx.value + 1) % musicPlaylist.length);
    }
  }

  void musicPlayAt(int index) => _playAt(index);

  void musicTogglePlay() {
    if (!_musicInitialized) return;
    player.playOrPause();
  }

  void musicSeekTo(Duration d) {
    if (!_musicInitialized) return;
    player.seek(d);
  }

  void musicSetVolume(double v) {
    if (!_musicInitialized) return;
    musicVolume.value = v;
    player.setVolume(v);
  }

  void musicSetSpeed(double s) {
    if (!_musicInitialized) return;
    musicPlaySpeed.value = s;
    player.setRate(s);
  }

  void musicCycleRepeat() {
    musicRepeatMode.value = GlobalRepeatMode
        .values[(musicRepeatMode.value.index + 1) % GlobalRepeatMode.values.length];
    if (musicRepeatMode.value == GlobalRepeatMode.shuffle) _buildShuffleOrder();
  }

  void _buildShuffleOrder() {
    _shuffleOrder
      ..clear()
      ..addAll(List.generate(musicPlaylist.length, (i) => i));
    _shuffleOrder.shuffle();
  }

  int _shuffleNext(int dir) {
    if (_shuffleOrder.isEmpty) _buildShuffleOrder();
    final pos = _shuffleOrder.indexOf(musicCurrentIdx.value);
    if (pos < 0) return _shuffleOrder[0];
    return _shuffleOrder[(pos + dir + _shuffleOrder.length) % _shuffleOrder.length];
  }

  Future<void> _loadMeta(String filePath) async {
    final idx = musicCurrentIdx.value;
    try {
      final meta = await AudioMetadataReader.readFile(filePath);
      if (musicCurrentIdx.value != idx) return;
      musicCurrentMeta.value = TrackMeta(
        title: meta.title,
        artist: meta.artist,
        coverBytes: meta.coverBytes,
        lrcLines: meta.lyrics != null ? parseLrc(meta.lyrics!) : [],
      );
      musicCurrentLrcIdx.value = -1;
    } catch (_) {
      // 忽略读取失败
    }
  }

  void _updateLrcIndex(Duration pos) {
    final lines = musicCurrentMeta.value?.lrcLines ?? [];
    if (lines.isEmpty) return;
    int idx = 0;
    for (int i = 0; i < lines.length; i++) {
      if (lines[i].time <= pos) {
        idx = i;
      } else {
        break;
      }
    }
    if (musicCurrentLrcIdx.value != idx) musicCurrentLrcIdx.value = idx;
  }

  /// 停止音乐播放（仅在开始播放视频/IPTV 时调用）。
  Future<void> stopMusicForOtherPlayback() async {
    if (!_musicInitialized) return;
    try {
      await player.pause();
    } catch (_) {}
  }

  // ══════════════════════════════════════════════════════════════════════
  //  底部播放栏点击 → 进入对应播放页续播
  // ══════════════════════════════════════════════════════════════════════

  /// 点击底部播放栏时，根据当前 miniBarKind 决定跳转逻辑。
  /// 具体跳转由 UI 层（home_page.dart）持有 NavigatorPlayer 引用来完成，
  /// 这里只暴露状态查询接口，保持本 controller 与路由解耦。

  @override
  void onClose() {
    // 全局播放器是 permanent 单例，理论上不会被 onClose，这里仅兜底。
    if (_musicInitialized) {
      disposePlayer();
    }
    super.onClose();
  }
}
