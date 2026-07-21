import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;
import 'package:player_shared/player_shared.dart';

import 'package:nexus_tv/app/controller/tv_settings_controller.dart';
import 'package:nexus_tv/app/theme/tv_theme.dart';
import 'package:nexus_tv/app/tv_focus_node.dart';
import 'package:nexus_tv/app/tv_style.dart';
import 'package:nexus_tv/widgets/lrc_view.dart';
import 'package:nexus_tv/widgets/tv_highlight.dart';

/// 播放模式,对应 NovaBox 的 LIST / SHUFFLE / REPEAT_1。
enum PlayMode { list, shuffle, repeatOne }

/// TV 音乐播放控制器,照抄 NovaBox `LocalAudioPlayerActivity` 逻辑。
///
/// - 播放列表模式,支持上一首/下一首/指定跳转
/// - 三种播放模式: 顺序(列表循环) / 随机 / 单曲循环
/// - 切换曲目时异步加载 ID3 元数据(封面 / 歌词 / 标题 / 歌手 / 专辑)
class TvMusicPlayerController extends GetxController with PlayerMixin {
  static TvMusicPlayerController get instance =>
      Get.find<TvMusicPlayerController>();

  List<Map<String, String>> playlist = const [];

  final RxInt currentIdx = 0.obs;
  final RxBool isPlaying = false.obs;
  final RxBool isBuffering = false.obs;
  final Rx<Duration> position = Duration.zero.obs;
  final Rx<Duration> duration = Duration.zero.obs;
  final Rx<PlayMode> playMode = PlayMode.list.obs;

  /// 播放列表弹窗是否显示
  final RxBool showQueue = false.obs;

  // 当前曲目的 ID3 元数据
  final Rx<Uint8List?> coverBytes = Rx<Uint8List?>(null);
  final RxString lyrics = ''.obs;
  final RxString title = ''.obs;
  final RxString artist = ''.obs;
  final RxString album = ''.obs;

  /// 是否已经播放过内容（用于顶部播放入口/迷你播放栏判断是否有信息可展示）。
  final RxBool hasContent = false.obs;

  bool _playerReady = false;

  String get currentPath =>
      playlist.isEmpty ? '' : playlist[currentIdx.value]['path'] ?? '';

  /// 确保底层播放器后端已初始化（懒加载：常驻单例在 App 启动时就存在，
  /// 但只有真正开始播放音乐时才需要创建播放器后端）。
  Future<void> _ensurePlayerReady() async {
    if (_playerReady) return;
    _playerReady = true;

    final s = TvSettingsController.instance;
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

  /// 开始播放一个新的播放列表（从音乐库进入时调用）。
  /// 常驻单例复用同一个播放器后端，切歌单时直接切换播放内容。
  Future<void> playPlaylist(
    List<Map<String, String>> newPlaylist,
    int index,
  ) async {
    await _ensurePlayerReady();
    playlist = newPlaylist;
    hasContent.value = true;
    await _playAt(index);
  }

  /// 停止音乐播放（暂停），但不销毁播放器后端本身 —— 因为本 controller 是
  /// App 级常驻单例。用于播放视频/IPTV 前实现互斥：三种媒体同一时刻只能
  /// 有一个在播放。调用后顶部播放入口不再展示音乐信息，直到下次播放音乐。
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

  // 注意：TvMusicPlayerController 现在是 App 级常驻单例（main.dart 启动时
  // Get.put(permanent: true) 创建），不会随播放页面的 dispose 而销毁，所以
  // 这里不再重写 onClose 去 disposePlayer —— 退出音乐播放页应继续播放，
  // 只有开始播放视频/IPTV 或退出 App 时才停止。
}

class TvMusicPlayerPage extends StatefulWidget {
  const TvMusicPlayerPage({super.key});
  @override
  State<TvMusicPlayerPage> createState() => _TvMusicPlayerPageState();
}

class _TvMusicPlayerPageState extends State<TvMusicPlayerPage> {
  late final TvMusicPlayerController ctrl;
  final GlobalKey<LrcViewState> _lrcKey = GlobalKey<LrcViewState>();
  StreamSubscription<Duration>? _posSub;

  // 控制按钮焦点节点(有序遍历)
  final _modeFocus = TvFocusNode();
  final _prevFocus = TvFocusNode();
  final _playFocus = TvFocusNode(autofocus: true);
  final _nextFocus = TvFocusNode();
  final _queueFocus = TvFocusNode();
  final _backFocus = TvFocusNode();

  // 根级焦点(处理返回键)
  late final FocusNode _rootFocus;

  @override
  void initState() {
    super.initState();
    // TvMusicPlayerController 是 App 启动时创建的常驻单例，直接复用，
    // 不再 Get.put/Get.delete —— 退出本页面不应销毁播放器。
    ctrl = TvMusicPlayerController.instance;
    _rootFocus = FocusNode();

    final args = Get.arguments as Map<String, dynamic>?;
    if (args != null && args['playlist'] != null) {
      // 从音乐库带着新播放列表进入：开始播放新内容。
      final newPlaylist = List<Map<String, String>>.from(
          (args['playlist'] as List).map((e) => Map<String, String>.from(e)));
      final index = args['index'] as int? ?? 0;
      ctrl.playPlaylist(newPlaylist, index).then((_) {
        if (mounted) _attachLrcSub();
      });
    } else {
      // 没有携带新播放列表：从顶部播放入口点进来，继续展示当前播放中的内容。
      _attachLrcSub();
    }
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
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
    _rootFocus.dispose();
    _modeFocus.dispose();
    _prevFocus.dispose();
    _playFocus.dispose();
    _nextFocus.dispose();
    _queueFocus.dispose();
    _backFocus.dispose();
    // 常驻单例：不删除 controller，也不 disposePlayer —— 退出播放页继续播放。
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  /// 根级按键:弹窗显示时返回键关闭弹窗,否则退出页面。
  KeyEventResult _onRootKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final isBack = key == LogicalKeyboardKey.goBack ||
        key == LogicalKeyboardKey.escape;
    if (!isBack) return KeyEventResult.ignored;
    if (ctrl.showQueue.value) {
      ctrl.showQueue.value = false;
      return KeyEventResult.handled;
    }
    Get.back();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TvColors.background,
      body: Focus(
        focusNode: _rootFocus,
        autofocus: true,
        onKeyEvent: _onRootKey,
        child: Stack(
          children: [
            // 主体:1:1 分屏(左封面 / 右信息+歌词+控制)
            _buildBody(context),
            // 播放列表弹窗(确定键唤出)
            Obx(() => ctrl.showQueue.value
                ? _buildQueuePanel(context)
                : const SizedBox()),
          ],
        ),
      ),
    );
  }

  // ── 主体布局(照抄 NovaBox 平板端 activity_openlist_audio_player) ──
  // 左封面区(可被队列覆盖)+ 右信息区(歌名+歌手+歌词常驻+进度条+5控制)

  Widget _buildBody(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(48.w, 48.w, 48.w, 48.w),
      child: Stack(
        children: [
          Row(
            children: [
              // 左侧封面区(weight1)
              Expanded(
                flex: 1,
                child: _buildCoverArea(context),
              ),
              SizedBox(width: 48.w),
              // 右侧信息区(weight1)
              Expanded(
                flex: 1,
                child: _buildInfoArea(context),
              ),
            ],
          ),
          // 返回键(左上角)
          Positioned(
            top: 0,
            left: 0,
            child: _BackButton(focusNode: _backFocus),
          ),
        ],
      ),
    );
  }

  /// 左侧封面区:大封面居中,无封面时显示音符占位。
  Widget _buildCoverArea(BuildContext context) {
    return Center(
      child: Obx(() {
        final bytes = ctrl.coverBytes.value;
        if (bytes != null) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(24.w),
            child: Image.memory(
              bytes,
              width: 480.w,
              height: 480.w,
              fit: BoxFit.cover,
            ),
          );
        }
        // 无封面占位
        return SizedBox(
          width: 480.w,
          height: 480.w,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.music_note,
                  size: 160.w, color: TvColors.accent.withAlpha(120)),
              SizedBox(height: 16.w),
              Text('暂无封面', style: TvStyle.labelSmall),
            ],
          ),
        );
      }),
    );
  }

  /// 右侧信息区:歌名 + 歌手 + 歌词(常驻) + 进度条 + 5控制按钮。
  Widget _buildInfoArea(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // 歌名 40sp bold
        Obx(() => Text(
              ctrl.title.value.isEmpty ? '未知' : ctrl.title.value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TvStyle.titleLarge,
            )),
        SizedBox(height: 12.w),
        // 歌手 28sp
        Obx(() => ctrl.artist.value.isNotEmpty
            ? Text(
                ctrl.artist.value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TvStyle.bodyLarge
                    .copyWith(color: TvColors.textSecondary),
              )
            : const SizedBox.shrink()),
        SizedBox(height: 32.w),
        // 歌词常驻(weight1)
        Expanded(
          child: Obx(() => LrcView(
                key: _lrcKey,
                lrcText: ctrl.lyrics.value,
                emptyText: '暂无歌词',
                highlightColor: TvColors.accent,
                normalColor: TvColors.textSecondary,
                lineSpacing: 80.w,
                normalFontSize: 24.sp,
                currentFontSize: 32.sp,
              )),
        ),
        SizedBox(height: 32.w),
        // 进度条
        _buildSeekBar(context),
        SizedBox(height: 24.w),
        // 5控制按钮
        _buildControls(context),
        SizedBox(height: 16.w),
        // 底部提示
        Text(
          'OK 播放/暂停  ← → 切换曲目  返回键退出',
          style: TvStyle.labelSmall,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  /// 进度条(时间 + SeekBar)。
  Widget _buildSeekBar(BuildContext context) {
    return Obx(() {
      final posMs = ctrl.position.value.inMilliseconds.toDouble();
      final durMs = ctrl.duration.value.inMilliseconds > 0
          ? ctrl.duration.value.inMilliseconds.toDouble()
          : 1.0;
      return Row(
        children: [
          SizedBox(
            width: 100.w,
            child: Text(_fmt(ctrl.position.value),
                textAlign: TextAlign.center, style: TvStyle.labelSmall),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 4,
                thumbShape:
                    const RoundSliderThumbShape(enabledThumbRadius: 8),
                activeTrackColor: TvColors.accent,
                inactiveTrackColor: TvColors.divider,
                thumbColor: TvColors.accent,
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
            width: 100.w,
            child: Text(_fmt(ctrl.duration.value),
                textAlign: TextAlign.center, style: TvStyle.labelSmall),
          ),
        ],
      );
    });
  }

  /// 5控制按钮(有序焦点遍历: 模式/上一首/播放/下一首/队列)。
  Widget _buildControls(BuildContext context) {
    return FocusTraversalGroup(
      policy: OrderedTraversalPolicy(),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 播放模式
          _ControlBtn(
            focusNode: _modeFocus,
            onTap: ctrl.cyclePlayMode,
            order: 1,
            child: Obx(() => Icon(
                  ctrl.playModeIcon(),
                  color: ctrl.playMode.value != PlayMode.list
                      ? TvColors.accent
                      : TvColors.textSecondary,
                  size: 44.w,
                )),
          ),
          SizedBox(width: 32.w),
          // 上一首
          _ControlBtn(
            focusNode: _prevFocus,
            onTap: ctrl.prev,
            order: 2,
            child: Icon(Icons.skip_previous_rounded,
                color: TvColors.textPrimary, size: 56.w),
          ),
          SizedBox(width: 32.w),
          // 播放/暂停(更大)
          _ControlBtn(
            focusNode: _playFocus,
            onTap: ctrl.togglePlay,
            autofocus: true,
            order: 3,
            size: 96.w,
            child: Obx(() => Icon(
                  ctrl.isPlaying.value
                      ? Icons.pause_circle_filled
                      : Icons.play_circle_filled,
                  color: TvColors.accent,
                  size: 80.w,
                )),
          ),
          SizedBox(width: 32.w),
          // 下一首
          _ControlBtn(
            focusNode: _nextFocus,
            onTap: ctrl.next,
            order: 4,
            child: Icon(Icons.skip_next_rounded,
                color: TvColors.textPrimary, size: 56.w),
          ),
          SizedBox(width: 32.w),
          // 播放列表
          _ControlBtn(
            focusNode: _queueFocus,
            onTap: ctrl.toggleQueue,
            order: 5,
            child: Icon(Icons.queue_music,
                color: TvColors.textSecondary, size: 44.w),
          ),
        ],
      ),
    );
  }

  // ── 播放列表弹窗 ──────────────────────────────────────────

  /// 播放列表弹窗:半透明黑底 + 居中面板,列表项用 TvHighlight 包裹。
  Widget _buildQueuePanel(BuildContext context) {
    return Positioned.fill(
      child: Container(
        color: Colors.black54,
        alignment: Alignment.center,
        child: Container(
          width: 800.w,
          height: 720.w,
          decoration: BoxDecoration(
            color: TvColors.surface,
            borderRadius: TvStyle.radius12,
            border: Border.all(color: TvColors.accent, width: 2.w),
          ),
          child: Column(
            children: [
              // 头部
              Container(
                height: 80.w,
                padding: EdgeInsets.symmetric(horizontal: 32.w),
                alignment: Alignment.centerLeft,
                decoration: BoxDecoration(
                  border: Border(
                      bottom: BorderSide(
                          color: TvColors.divider, width: 1)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.queue_music,
                        color: TvColors.accent, size: 36.w),
                    SizedBox(width: 12.w),
                    Text('播放队列', style: TvStyle.titleMedium),
                    const Spacer(),
                    Obx(() => Text('${ctrl.playlist.length} 首',
                        style: TvStyle.labelSmall)),
                  ],
                ),
              ),
              // 列表
              Expanded(
                child: Obx(() => ListView.builder(
                      padding: EdgeInsets.symmetric(vertical: 8.w),
                      itemCount: ctrl.playlist.length,
                      itemBuilder: (_, i) {
                        final name = p.withoutExtension(
                            ctrl.playlist[i]['name'] ?? '');
                        final isActive = ctrl.currentIdx.value == i;
                        return _QueueItem(
                          text: name,
                          highlighted: isActive,
                          autofocus: i == 0,
                          onTap: () {
                            ctrl.playAt(i);
                            ctrl.showQueue.value = false;
                          },
                        );
                      },
                    )),
              ),
              // 底部:播放模式
              Container(
                height: 80.w,
                padding: EdgeInsets.symmetric(horizontal: 32.w),
                alignment: Alignment.centerLeft,
                decoration: BoxDecoration(
                  border: Border(
                      top: BorderSide(
                          color: TvColors.divider, width: 1)),
                ),
                child: Row(
                  children: [
                    Icon(ctrl.playModeIcon(),
                        color: TvColors.accent, size: 32.w),
                    SizedBox(width: 12.w),
                    Text(ctrl.playModeLabel(), style: TvStyle.bodyMedium),
                    const Spacer(),
                    Text('返回键关闭', style: TvStyle.labelSmall),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

/// 返回按钮(TvHighlight 包裹,遥控器可聚焦)。
class _BackButton extends StatelessWidget {
  final TvFocusNode focusNode;
  const _BackButton({required this.focusNode});

  @override
  Widget build(BuildContext context) {
    return TvHighlight(
      focusNode: focusNode,
      onTap: () {
        final ctrl = Get.find<TvMusicPlayerController>();
        if (ctrl.showQueue.value) {
          ctrl.showQueue.value = false;
        } else {
          Get.back();
        }
      },
      borderRadius: BorderRadius.circular(50),
      child: Padding(
        padding: EdgeInsets.all(12.w),
        child: Icon(Icons.arrow_back,
            color: TvColors.textPrimary, size: 40.w),
      ),
    );
  }
}

/// 控制按钮(TvHighlight + 有序焦点遍历)。
class _ControlBtn extends StatelessWidget {
  final TvFocusNode focusNode;
  final Widget child;
  final VoidCallback? onTap;
  final bool autofocus;
  final double? size;
  final int order;

  const _ControlBtn({
    required this.focusNode,
    required this.child,
    this.onTap,
    this.autofocus = false,
    this.size,
    required this.order,
  });

  @override
  Widget build(BuildContext context) {
    return FocusTraversalOrder(
      order: NumericFocusOrder(order.toDouble()),
      child: TvHighlight(
        focusNode: focusNode,
        autofocus: autofocus,
        onTap: onTap,
        borderRadius: BorderRadius.circular(50),
        child: SizedBox(
          width: size ?? 72.w,
          height: size ?? 72.w,
          child: Center(child: child),
        ),
      ),
    );
  }
}

/// 播放列表项(TvHighlight 包裹,遥控器可聚焦)。
class _QueueItem extends StatefulWidget {
  final String text;
  final bool highlighted;
  final bool autofocus;
  final VoidCallback onTap;

  const _QueueItem({
    required this.text,
    required this.onTap,
    this.highlighted = false,
    this.autofocus = false,
  });

  @override
  State<_QueueItem> createState() => _QueueItemState();
}

class _QueueItemState extends State<_QueueItem> {
  late final TvFocusNode _focus;

  @override
  void initState() {
    super.initState();
    _focus = TvFocusNode();
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TvHighlight(
      focusNode: _focus,
      autofocus: widget.autofocus,
      onTap: widget.onTap,
      borderRadius: TvStyle.radius8,
      color: widget.highlighted
          ? TvColors.accent.withAlpha(40)
          : Colors.transparent,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 32.w, vertical: 16.w),
        child: Row(
          children: [
            if (widget.highlighted) ...[
              Icon(Icons.equalizer,
                  color: TvColors.accent, size: 28.w),
              SizedBox(width: 12.w),
            ],
            Expanded(
              child: Text(
                widget.text,
                style: TvStyle.bodyMedium.copyWith(
                  color: widget.highlighted
                      ? TvColors.accent
                      : TvColors.textPrimary,
                  fontWeight: widget.highlighted
                      ? FontWeight.bold
                      : FontWeight.normal,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
