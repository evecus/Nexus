import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;
import 'package:player_shared/player_shared.dart';

import 'package:nexus_ios/app/controller/app_settings_controller.dart';
import 'package:nexus_ios/widgets/lrc_view.dart';

/// 播放模式,对应 NovaBox 的 LIST / SHUFFLE / REPEAT_1。
enum PlayMode { list, shuffle, repeatOne }

/// 音乐播放控制器,完全照抄 NovaBox 的 `LocalAudioPlayerActivity` 逻辑。
///
/// - 播放列表模式,支持上一首/下一首/指定跳转
/// - 三种播放模式: 顺序(列表循环) / 随机 / 单曲循环
/// - 切换曲目时异步加载 ID3 元数据(封面 / 歌词 / 标题 / 歌手 / 专辑)
class MusicPlayerController extends GetxController with PlayerMixin {
  static MusicPlayerController get instance =>
      Get.find<MusicPlayerController>();

  List<Map<String, String>> playlist = const [];

  final RxInt currentIdx = 0.obs;
  final RxBool isPlaying = false.obs;
  final RxBool isBuffering = false.obs;
  final Rx<Duration> position = Duration.zero.obs;
  final Rx<Duration> duration = Duration.zero.obs;
  final Rx<PlayMode> playMode = PlayMode.list.obs;
  final RxBool showQueue = false.obs;
  /// 手机端封面/歌词切换(NovaBox: 左右划切换)。
  final RxBool showLyrics = false.obs;

  // 当前曲目的 ID3 元数据
  final Rx<Uint8List?> coverBytes = Rx<Uint8List?>(null);
  final RxString lyrics = ''.obs;
  final RxString title = ''.obs;
  final RxString artist = ''.obs;
  final RxString album = ''.obs;

  /// 是否已经播放过内容（用于迷你播放栏判断是否有信息可展示）。
  final RxBool hasContent = false.obs;

  bool _playerReady = false;

  String get currentPath =>
      playlist.isEmpty ? '' : playlist[currentIdx.value]['path'] ?? '';

  /// 确保底层播放器后端已初始化（懒加载：常驻单例在 App 启动时就存在，
  /// 但只有真正开始播放音乐时才需要创建播放器后端）。
  Future<void> _ensurePlayerReady() async {
    if (_playerReady) return;
    _playerReady = true;

    final s = AppSettingsController.instance;
    final config = buildControllerConfig(
      hardwareDecode: s.hardwareDecode.value,
      compatMode: s.compatMode.value,
      profile: s.mpvProfile.value,
    );
    // 音乐播放器始终使用 MPV 后端（音频不需要 ExoPlayer）。
    await initPlayer(config: config);

    player.stream.playing.listen((v) => isPlaying.value = v);
    player.stream.buffering.listen((v) => isBuffering.value = v);
    player.stream.position.listen((v) => position.value = v);
    player.stream.duration.listen((v) => duration.value = v);
    player.stream.completed.listen((c) {
      if (c) _onCompleted();
    });
  }

  /// 开始播放一个新的播放列表（从音乐库/分组页进入时调用）。
  /// 常驻单例复用同一个播放器后端，切歌单时直接切换播放内容。
  Future<void> playPlaylist(
    List<Map<String, String>> newPlaylist,
    int index,
  ) async {
    await _ensurePlayerReady();
    playlist = newPlaylist;
    hasContent.value = true;
    if (Get.isRegistered<PlaybackBarController>()) {
      PlaybackBarController.instance.markMusicActive();
    }
    await _playAt(index);
  }

  /// 停止音乐播放（暂停 + 重置状态），但不销毁播放器后端本身 —— 因为本
  /// controller 是 App 级常驻单例。用于播放视频/IPTV 前实现互斥：三种
  /// 媒体同一时刻只能有一个在播放。
  ///
  /// 调用后迷你播放栏不再展示音乐信息，直到用户下次播放音乐。
  Future<void> stopForOtherMedia() async {
    if (!_playerReady) return;
    try {
      await player.pause();
    } catch (_) {}
    hasContent.value = false;
  }

  Future<void> _playAt(int index) async {
    if (playlist.isEmpty) return;
    currentIdx.value = index;
    showLyrics.value = false; // 切歌时回到封面
    final path = currentPath;
    coverBytes.value = null;
    lyrics.value = '';
    title.value = p.withoutExtension(playlist[index]['name'] ?? '');
    artist.value = '';
    album.value = '';
    await player.open(Media(path));
    _loadMetadata(path);
  }

  Future<void> _loadMetadata(String path) async {
    try {
      final meta = await AudioMetadataReader.readFile(path);
      if (currentPath == path) {
        coverBytes.value = meta.coverBytes;
        lyrics.value = meta.lyrics ?? '';
        if (meta.title != null && meta.title!.isNotEmpty) {
          title.value = meta.title!;
        }
        artist.value = meta.artist ?? '';
        album.value = meta.album ?? '';
      }
    } catch (_) {}
  }

  void _onCompleted() {
    switch (playMode.value) {
      case PlayMode.repeatOne:
        _playAt(currentIdx.value);
        break;
      case PlayMode.shuffle:
        _playShuffled();
        break;
      case PlayMode.list:
        _playAt((currentIdx.value + 1) % playlist.length);
        break;
    }
  }

  void _playShuffled() {
    if (playlist.length <= 1) {
      _playAt(0);
      return;
    }
    final rng = DateTime.now().microsecondsSinceEpoch;
    int idx;
    do {
      idx = rng % playlist.length;
    } while (idx == currentIdx.value && playlist.length > 1);
    _playAt(idx);
  }

  void togglePlay() => player.playOrPause();

  void next() {
    if (playlist.isEmpty) return;
    if (playMode.value == PlayMode.shuffle) {
      _playShuffled();
    } else {
      _playAt((currentIdx.value + 1) % playlist.length);
    }
  }

  void prev() {
    if (playlist.isEmpty) return;
    if (playMode.value == PlayMode.shuffle) {
      _playShuffled();
    } else {
      _playAt((currentIdx.value - 1 + playlist.length) % playlist.length);
    }
  }

  void playAt(int i) => _playAt(i);

  void seekTo(Duration d) => player.seek(d);

  void cyclePlayMode() {
    final modes = PlayMode.values;
    playMode.value = modes[(playMode.value.index + 1) % modes.length];
  }

  void toggleQueue() => showQueue.value = !showQueue.value;

  String playModeLabel() {
    switch (playMode.value) {
      case PlayMode.repeatOne:
        return '单曲循环';
      case PlayMode.shuffle:
        return '随机播放';
      default:
        return '列表循环';
    }
  }

  IconData playModeIcon() {
    switch (playMode.value) {
      case PlayMode.repeatOne:
        return Icons.repeat_one;
      case PlayMode.shuffle:
        return Icons.shuffle;
      default:
        return Icons.repeat;
    }
  }

  // 注意：MusicPlayerController 现在是 App 级常驻单例（Get.put(permanent: true)
  // 在 main.dart 启动时创建），不会随音乐播放页面的 dispose 而销毁，所以这里
  // 不再重写 onClose 去 disposePlayer —— 退出音乐播放页应继续播放，
  // 只有开始播放视频/IPTV 或退出 App 时才停止（见 PlaybackCoordinator）。
}

class MusicPlayerPage extends StatefulWidget {
  const MusicPlayerPage({super.key});

  @override
  State<MusicPlayerPage> createState() => _MusicPlayerPageState();
}

class _MusicPlayerPageState extends State<MusicPlayerPage> {
  late final MusicPlayerController ctrl;
  final GlobalKey<LrcViewState> _lrcKey = GlobalKey<LrcViewState>();
  StreamSubscription<Duration>? _posSub;

  @override
  void initState() {
    super.initState();
    // MusicPlayerController 是 App 启动时创建的常驻单例，这里直接复用，
    // 不再 Get.put/Get.delete —— 退出本页面不应销毁播放器。
    ctrl = MusicPlayerController.instance;

    final args = Get.arguments as Map<String, dynamic>?;
    if (args != null && args['playlist'] != null) {
      // 从音乐库/分组页带着新播放列表进入：开始播放新内容。
      final newPlaylist = List<Map<String, String>>.from(
          (args['playlist'] as List).map((e) => Map<String, String>.from(e)));
      final index = args['index'] as int? ?? 0;
      ctrl.playPlaylist(newPlaylist, index).then((_) {
        if (mounted) _attachLrcSub();
      });
    } else {
      // 没有携带新播放列表：说明是从迷你播放栏点进来的，继续展示当前播放中的内容。
      _attachLrcSub();
    }
  }

  void _attachLrcSub() {
    if (!ctrl.hasContent.value) return; // 播放器尚未初始化，没有可订阅的内容
    _posSub?.cancel();
    _posSub = ctrl.player.stream.position.listen((d) {
      _lrcKey.currentState?.updateProgress(d.inMilliseconds);
    });
  }

  @override
  void dispose() {
    _posSub?.cancel();
    // 常驻单例：不删除 controller，也不 disposePlayer —— 退出播放页继续播放。
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 600;
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: SafeArea(
        child: Stack(
          children: [
            isWide ? _buildWide(context) : _buildPhone(context),
            // 队列面板: 手机从底部上滑,平板从顶部下滑(覆盖左侧封面区)
            Obx(() => ctrl.showQueue.value
                ? (isWide
                    ? _buildTabletQueuePanel(context)
                    : _buildPhoneQueuePanel(context))
                : const SizedBox.shrink()),
          ],
        ),
      ),
    );
  }

  // ── 手机端(NovaBox activity_openlist_audio_player) ────
  // 顶部: 返回 + 歌名20sp bold 居中 + 歌手15sp #88000000 + 右占位
  // 中间 flMobileCenter(weight1): 封面260dp / 歌词(默认gone), 左右划切换, 上划开队列
  // 底部: 进度条(时间44dp 12sp #88000000 + SeekBar #1890FF) + 5控制按钮(weight等高)

  Widget _buildPhone(BuildContext context) {
    return Column(
      children: [
        _buildPhoneTopBar(context),
        Expanded(child: _buildPhoneCenter(context)),
        _buildPhoneBottom(context),
      ],
    );
  }

  /// 手机顶部栏: 返回40dp + 歌名20sp bold居中 + 歌手15sp + 右占位40dp。
  Widget _buildPhoneTopBar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 8, right: 16, top: 12, bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 40,
            height: 40,
            child: IconButton(
              padding: EdgeInsets.zero,
              icon: Icon(Icons.arrow_back, color: scheme.onSurface, size: 24),
              onPressed: () => Get.back(),
            ),
          ),
          Expanded(
            child: Obx(() => Column(
                  children: [
                    Text(
                      ctrl.title.value.isEmpty ? '未知' : ctrl.title.value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: scheme.onSurface,
                          fontSize: 20,
                          fontWeight: FontWeight.bold),
                    ),
                    if (ctrl.artist.value.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        ctrl.artist.value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: scheme.onSurfaceVariant, fontSize: 15),
                      ),
                    ],
                  ],
                )),
          ),
          const SizedBox(width: 40),
        ],
      ),
    );
  }

  /// 手机中间区: 封面(260dp)/歌词(alpha切换), 手势左右划切换、上划开队列。
  Widget _buildPhoneCenter(BuildContext context) {
    return GestureDetector(
      onHorizontalDragEnd: (details) {
        final v = details.primaryVelocity ?? 0;
        if (v < -200) {
          // 左划 → 显示歌词
          ctrl.showLyrics.value = true;
        } else if (v > 200) {
          // 右划 → 显示封面
          ctrl.showLyrics.value = false;
        }
      },
      onVerticalDragEnd: (details) {
        if ((details.primaryVelocity ?? 0) < -200) {
          ctrl.showQueue.value = true;
        }
      },
      behavior: HitTestBehavior.translucent,
      child: Stack(
        children: [
          // 封面层
          Obx(() => AnimatedOpacity(
                opacity: ctrl.showLyrics.value ? 0.0 : 1.0,
                duration: const Duration(milliseconds: 250),
                child: Center(child: _buildCover(context, 260)),
              )),
          // 歌词层
          Obx(() => AnimatedOpacity(
                opacity: ctrl.showLyrics.value ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 250),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: LrcView(
                    key: _lrcKey,
                    lrcText: ctrl.lyrics.value,
                    emptyText: '暂无歌词',
                    highlightColor: Theme.of(context).colorScheme.primary,
                    normalColor:
                        Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              )),
        ],
      ),
    );
  }

  /// 手机底部: 进度条 + 5控制按钮。
  Widget _buildPhoneBottom(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 24, right: 24, top: 16, bottom: 24),
      child: Column(
        children: [
          _buildSeekBar(context),
          const SizedBox(height: 16),
          _buildControls(context),
        ],
      ),
    );
  }

  // ── 平板端(NovaBox layout-sw600dp) ───────────────────
  // 返回48dp 左上 margin12 + 水平1:1分屏(左封面区weight1 可被队列覆盖 / 右信息区weight1:
  // 歌名26sp + 歌手17sp + 歌词常驻weight1 + 进度条 + 5控制)

  Widget _buildWide(BuildContext context) {
    return Stack(
      children: [
        // 返回键(NovaBox 平板: 48dp 左上 margin12)
        _buildWideBackButton(context),
        Padding(
          padding:
              const EdgeInsets.only(left: 32, right: 32, top: 64, bottom: 24),
          child: Row(
            children: [
              // 左侧封面区(weight1, 上划开队列下划关)
              Expanded(
                flex: 1,
                child: GestureDetector(
                  onVerticalDragEnd: (details) {
                    final v = details.primaryVelocity ?? 0;
                    if (v < -200) {
                      ctrl.showQueue.value = true;
                    } else if (v > 200) {
                      ctrl.showQueue.value = false;
                    }
                  },
                  behavior: HitTestBehavior.translucent,
                  child: Stack(
                    children: [
                      Center(child: _buildCover(context, 300)),
                      // 队列覆盖层(从顶部下滑)
                      Obx(() => ctrl.showQueue.value
                          ? _buildQueueList(context, isPad: true)
                          : const SizedBox.shrink()),
                    ],
                  ),
                ),
              ),
          // 右侧信息区(weight1)
          Expanded(
            flex: 1,
            child: Padding(
              padding: const EdgeInsets.only(left: 24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // 歌名26sp bold
                  Obx(() => Text(
                        ctrl.title.value.isEmpty ? '未知' : ctrl.title.value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface,
                            fontSize: 26,
                            fontWeight: FontWeight.bold),
                      )),
                  // 歌手17sp
                  Obx(() => ctrl.artist.value.isNotEmpty
                      ? Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            ctrl.artist.value,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                                fontSize: 17),
                          ),
                        )
                      : const SizedBox.shrink()),
                  // 歌词常驻(weight1)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Obx(() => LrcView(
                            key: _lrcKey,
                            lrcText: ctrl.lyrics.value,
                            emptyText: '暂无歌词',
                            highlightColor:
                                Theme.of(context).colorScheme.primary,
                            normalColor: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          )),
                    ),
                  ),
                  _buildSeekBar(context),
                  const SizedBox(height: 8),
                  _buildControls(context),
                ],
              ),
            ),
          ),
        ],
      ),
        ),
      ],
    );
  }

  /// 平板返回键(48dp 左上)。
  Widget _buildWideBackButton(BuildContext context) {
    return Positioned(
      top: 12,
      left: 12,
      child: SizedBox(
        width: 48,
        height: 48,
        child: IconButton(
          padding: EdgeInsets.zero,
          icon: Icon(Icons.arrow_back,
              color: Theme.of(context).colorScheme.onSurface, size: 28),
          onPressed: () => Get.back(),
        ),
      ),
    );
  }

  // ── 封面 ─────────────────────────────────────────────

  Widget _buildCover(BuildContext context, double size) {
    return Obx(() {
      final bytes = ctrl.coverBytes.value;
      if (bytes != null) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.memory(bytes,
              width: size, height: size, fit: BoxFit.cover),
        );
      }
      // 无封面占位(NovaBox: 90-100dp icon_live,跟随主题 + "暂无封面" 13-14sp)
      final scheme = Theme.of(context).colorScheme;
      return SizedBox(
        width: size,
        height: size,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.music_note,
                size: size == 300 ? 100 : 90,
                color: scheme.onSurfaceVariant.withAlpha(150)),
            const SizedBox(height: 12),
            Text('暂无封面',
                style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: size == 300 ? 14 : 13)),
          ],
        ),
      );
    });
  }

  // ── 进度条(NovaBox: 时间44dp宽 12sp #88000000 + SeekBar #1890FF) ──

  Widget _buildSeekBar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Obx(() {
      final posMs = ctrl.position.value.inMilliseconds.toDouble();
      final durMs = ctrl.duration.value.inMilliseconds > 0
          ? ctrl.duration.value.inMilliseconds.toDouble()
          : 1.0;
      return Row(
        children: [
          SizedBox(
            width: 44,
            child: Text(_fmt(ctrl.position.value),
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: scheme.onSurfaceVariant, fontSize: 12)),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 2,
                thumbShape:
                    const RoundSliderThumbShape(enabledThumbRadius: 6),
                activeTrackColor: scheme.primary,
                inactiveTrackColor: scheme.primary.withAlpha(50),
                thumbColor: scheme.primary,
              ),
              child: Slider(
                value: posMs.clamp(0, durMs),
                max: durMs,
                onChanged: (v) =>
                    ctrl.seekTo(Duration(milliseconds: v.round())),
              ),
            ),
          ),
          SizedBox(
            width: 44,
            child: Text(_fmt(ctrl.duration.value),
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: scheme.onSurfaceVariant, fontSize: 12)),
          ),
        ],
      );
    });
  }

  // ── 5控制按钮(NovaBox: 等高weight, 模式44 / 上一首52 / 播放64 weight1.4 / 下一首52 / 队列44) ──

  Widget _buildControls(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Obx(() => Row(
          children: [
            // 播放模式 44dp weight1
            Expanded(
              flex: 1,
              child: SizedBox(
                height: 44,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  icon: Icon(ctrl.playModeIcon(),
                      color: ctrl.playMode.value != PlayMode.list
                          ? scheme.primary
                          : scheme.onSurfaceVariant),
                  onPressed: ctrl.cyclePlayMode,
                ),
              ),
            ),
            // 上一首 52dp weight1
            Expanded(
              flex: 1,
              child: SizedBox(
                height: 52,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  icon: Icon(Icons.skip_previous,
                      color: scheme.onSurfaceVariant, size: 32),
                  onPressed: ctrl.prev,
                ),
              ),
            ),
            // 播放/暂停 64dp weight1.4
            Expanded(
              flex: 14,
              child: SizedBox(
                height: 64,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  iconSize: 56,
                  icon: Icon(
                    ctrl.isPlaying.value
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    color: scheme.onSurface,
                  ),
                  onPressed: ctrl.togglePlay,
                ),
              ),
            ),
            // 下一首 52dp weight1
            Expanded(
              flex: 1,
              child: SizedBox(
                height: 52,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  icon: Icon(Icons.skip_next,
                      color: scheme.onSurfaceVariant, size: 32),
                  onPressed: ctrl.next,
                ),
              ),
            ),
            // 队列 44dp weight1
            Expanded(
              flex: 1,
              child: SizedBox(
                height: 44,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  icon: Icon(Icons.queue_music, color: scheme.onSurfaceVariant),
                  onPressed: () => ctrl.showQueue.value = true,
                ),
              ),
            ),
          ],
        ));
  }

  // ── 队列面板 ──────────────────────────────────────────

  /// 手机队列: 全屏跟随主题背景,从底部上滑。
  Widget _buildPhoneQueuePanel(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Positioned.fill(
      child: Material(
        color: scheme.surface,
        child: Column(
          children: [
            // "此处向下轻扫以返回播放界面"
            GestureDetector(
              onVerticalDragEnd: (d) {
                if ((d.primaryVelocity ?? 0) > 200) ctrl.showQueue.value = false;
              },
              child: Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 4),
                child: Text('此处向下轻扫以返回播放界面',
                    style: TextStyle(
                        color: scheme.onSurfaceVariant, fontSize: 13)),
              ),
            ),
            _buildQueueHeader(context),
            Container(height: 1, color: scheme.outlineVariant.withAlpha(120)),
            Expanded(child: _buildQueueListBody(context)),
            _buildQueueFooter(context),
          ],
        ),
      ),
    );
  }

  /// 平板队列: 覆盖左侧封面区,白底,从顶部下滑(由父 Stack 定位在左侧 Expanded 内)。
  Widget _buildTabletQueuePanel(BuildContext context) {
    // 平板队列已在 _buildWide 的左 Stack 内渲染,这里返回空避免重复
    return const SizedBox.shrink();
  }

  /// 队列头部: 当前歌曲信息 + 数量行 + "播放队列"标题。
  Widget _buildQueueHeader(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Obx(() => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ctrl.title.value.isEmpty
                              ? '未知'
                              : ctrl.title.value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: scheme.onSurface,
                              fontSize: 16,
                              fontWeight: FontWeight.bold),
                        ),
                        if (ctrl.artist.value.isNotEmpty)
                          Text(ctrl.artist.value,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: scheme.onSurfaceVariant,
                                  fontSize: 13)),
                      ],
                    )),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Obx(() => Expanded(
                    child: Text('${ctrl.playlist.length} 首',
                        style: TextStyle(
                            color: scheme.onSurfaceVariant, fontSize: 13)),
                  )),
              Text('播放队列',
                  style: TextStyle(
                      color: scheme.onSurface,
                      fontSize: 15,
                      fontWeight: FontWeight.bold)),
              const Expanded(child: SizedBox()),
            ],
          ),
        ),
      ],
    );
  }

  /// 队列底部: 播放模式按钮。
  Widget _buildQueueFooter(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: GestureDetector(
        onTap: ctrl.cyclePlayMode,
        child: Obx(() => Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withAlpha(150),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(ctrl.playModeLabel(),
                  style: TextStyle(color: scheme.onSurface, fontSize: 14)),
            )),
      ),
    );
  }

  /// 队列列表(NovaBox item_audio_queue: padding16/12, 15sp黑(当前#1890FF) +
  /// 12sp #88000000 副标题 + 20dp #1890FF 指示器(当前可见))。
  Widget _buildQueueList(BuildContext context, {required bool isPad}) {
    return _buildQueueListBody(context);
  }

  Widget _buildQueueListBody(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Obx(() => ListView.builder(
          padding: const EdgeInsets.only(bottom: 16),
          itemCount: ctrl.playlist.length,
          itemBuilder: (_, i) {
            final name = p.withoutExtension(ctrl.playlist[i]['name'] ?? '');
            final isActive = ctrl.currentIdx.value == i;
            return InkWell(
              onTap: () {
                ctrl.playAt(i);
                ctrl.showQueue.value = false;
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: isActive
                                    ? scheme.primary
                                    : scheme.onSurface,
                                fontSize: 15,
                              )),
                        ],
                      ),
                    ),
                    Icon(Icons.play_arrow,
                        size: 20,
                        color: isActive ? scheme.primary : Colors.transparent),
                  ],
                ),
              ),
            );
          },
        ));
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}
