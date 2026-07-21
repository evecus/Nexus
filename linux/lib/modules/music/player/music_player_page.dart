import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as p;

import 'package:nexus_linux/app/controller/global_player_controller.dart';

// ══════════════════════════════════════════════════════════════════════════════
//  播放模式枚举（与 GlobalRepeatMode 一一对应，供本页 UI 使用）
// ══════════════════════════════════════════════════════════════════════════════

enum RepeatMode { list, shuffle, one }

RepeatMode _fromGlobalRepeat(GlobalRepeatMode m) =>
    RepeatMode.values[m.index];

// ══════════════════════════════════════════════════════════════════════════════
//  Controller —— 音乐播放页的"壳"控制器。
//
//  实际播放状态（Player 实例、播放列表、进度等）现在统一由
//  [GlobalPlayerController] 持有并贯穿整个 App 生命周期：离开本播放页
//  不会停止播放，只有切到视频/IPTV 播放或退出程序时才会停止。
//  本类只是把 UI 需要的字段/方法转发到 GlobalPlayerController，
//  尽量保持原有 UI 代码（下面的 Widget 部分）不需要改动。
// ══════════════════════════════════════════════════════════════════════════════

class MusicPlayerController extends GetxController {
  GlobalPlayerController get _g => GlobalPlayerController.instance;

  // ── 只读转发字段 ─────────────────────────────────────────────────────────
  List<Map<String, String>> get playlist => _g.musicPlaylist;

  RxInt get currentIdx => _g.musicCurrentIdx;
  RxBool get isPlaying => _g.musicIsPlaying;
  RxBool get isBuffering => _g.musicIsBuffering;
  Rx<Duration> get position => _g.musicPosition;
  Rx<Duration> get duration => _g.musicDuration;
  RxDouble get playSpeed => _g.musicPlaySpeed;
  RxDouble get volume => _g.musicVolume;
  RxInt get currentLrcIdx => _g.musicCurrentLrcIdx;

  /// 兼容原 UI：以 RepeatMode 类型暴露（内部仍存的是 GlobalRepeatMode）。
  /// 用一个持久的本地 Rx，通过 [ever] 同步一次，而不是每次访问都新建
  /// Rx/绑定新的 stream（那样会不断泄漏订阅且无法被 Obx 正确追踪）。
  late final Rx<RepeatMode> repeatMode =
      _fromGlobalRepeat(_g.musicRepeatMode.value).obs;

  final showQueue = false.obs;

  Rx<TrackMeta?> get currentMeta => _g.musicCurrentMeta;

  String get currentTitle => _g.musicCurrentTitle;
  String get currentArtist => _g.musicCurrentArtist;

  // ── 生命周期 ───────────────────────────────────────────────────────────

  @override
  void onInit() {
    super.onInit();
    // 保持本地 repeatMode 镜像与全局状态同步（用于 UI 高亮/图标展示）。
    ever(_g.musicRepeatMode, (GlobalRepeatMode m) {
      repeatMode.value = _fromGlobalRepeat(m);
    });

    final args = Get.arguments as Map<String, dynamic>? ?? {};
    final rawPlaylist = List<Map<String, String>>.from(
        (args['playlist'] as List?)
                ?.map((e) => Map<String, String>.from(e)) ??
            []);
    final rawIndex = args['index'] as int? ?? 0;

    // 若传入了新的播放列表（例如从音乐库点了新歌），才重新开始播放；
    // 若只是重新打开同一份播放列表且目标下标就是当前正在播放的下标
    // （例如通过底部播放栏回到本页），则不打断当前播放进度。
    // 注意：即使是"同一份播放列表"，只要点击的下标与当前正在播放的
    // 下标不同（例如在音乐库里点了同一列表中的另一首歌），也必须
    // 当作"新的播放请求"重新播放，否则会出现"点了新歌却还在播放
    // 原来那首"的问题。
    final samePlaylist = _isSamePlaylist(rawPlaylist, _g.musicPlaylist);
    final sameIndex = samePlaylist && rawIndex == _g.musicCurrentIdx.value;
    if (rawPlaylist.isNotEmpty && !sameIndex) {
      final idx = rawIndex.clamp(0, rawPlaylist.length - 1);
      _g.playMusicPlaylist(rawPlaylist, idx);
    } else {
      _g.miniBarKind.value = MiniBarKind.music;
    }
  }

  bool _isSamePlaylist(
      List<Map<String, String>> a, List<Map<String, String>> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i]['path'] != b[i]['path']) return false;
    }
    return true;
  }

  // ── 播放控制（转发到全局控制器）───────────────────────────────────────

  void previous() => _g.musicPrevious();
  void next() => _g.musicNext();
  void playAt(int index) => _g.musicPlayAt(index);
  void togglePlay() => _g.musicTogglePlay();
  void seekTo(Duration d) => _g.musicSeekTo(d);
  void setVolume(double v) => _g.musicSetVolume(v);
  void setSpeed(double s) => _g.musicSetSpeed(s);
  void cycleRepeat() => _g.musicCycleRepeat();

  void toggleQueue() => showQueue.value = !showQueue.value;
}

// ══════════════════════════════════════════════════════════════════════════════
//  Page
// ══════════════════════════════════════════════════════════════════════════════

class MusicPlayerPage extends StatefulWidget {
  const MusicPlayerPage({super.key});

  @override
  State<MusicPlayerPage> createState() => _MusicPlayerPageState();
}

class _MusicPlayerPageState extends State<MusicPlayerPage> {
  late final MusicPlayerController ctrl;

  @override
  void initState() {
    super.initState();
    ctrl = Get.put(MusicPlayerController());
  }

  @override
  void dispose() {
    Get.delete<MusicPlayerController>();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('正在播放'),
        foregroundColor: scheme.onSurface,
        actions: [
          // 播放队列图标
          Obx(() => IconButton(
                icon: Icon(
                  Icons.queue_music,
                  color: ctrl.showQueue.value ? scheme.primary : null,
                ),
                tooltip: '播放列表',
                onPressed: ctrl.toggleQueue,
              )),
        ],
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── 左侧封面区（固定宽度）──────────────────────────────────
          _CoverPanel(ctrl: ctrl),

          VerticalDivider(
            width: 1, thickness: 1,
            color: scheme.outlineVariant.withAlpha(60),
          ),

          // ── 中间歌词+控制区（弹性伸展）─────────────────────────────
          Expanded(child: _RightPanel(ctrl: ctrl)),

          // ── 右侧播放队列面板（宽度动画展开/收起）───────────────────
          // 用 AnimatedContainer 直接对宽度做动画，ClipRect 裁剪超出部分；
          // 内部用固定 320 宽度的 SizedBox 渲染 _QueuePanel，且外层 Row
          // 已加上 crossAxisAlignment: stretch，保证这一列拿到完整、非零
          // 的高度（之前默认 CrossAxisAlignment.center 会让子级按内容高
          // 度收缩，导致高度塌缩为 0，内容全部不可见，只剩一片灰色背景）。
          Obx(() {
            final open = ctrl.showQueue.value;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              width: open ? 320 : 0,
              clipBehavior: Clip.hardEdge,
              decoration: const BoxDecoration(),
              child: RepaintBoundary(
                child: SizedBox(
                  width: 320,
                  height: double.infinity,
                  child: _QueuePanel(ctrl: ctrl),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  左侧封面面板
// ══════════════════════════════════════════════════════════════════════════════

class _CoverPanel extends StatelessWidget {
  final MusicPlayerController ctrl;
  const _CoverPanel({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: 300,
      color: scheme.surfaceContainerHighest.withAlpha(40),
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 封面图 / 占位
          Obx(() {
            final bytes = ctrl.currentMeta.value?.coverBytes;
            return Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: scheme.shadow.withAlpha(50),
                    blurRadius: 28,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: bytes != null
                  ? Image.memory(bytes, fit: BoxFit.cover)
                  : Container(
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer.withAlpha(120),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(Icons.music_note,
                          size: 80, color: scheme.primary),
                    ),
            );
          }),
          const SizedBox(height: 24),
          // 歌名
          Obx(() => Text(
                ctrl.currentTitle,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              )),
          const SizedBox(height: 6),
          // 艺术家
          Obx(() {
            final artist = ctrl.currentArtist;
            if (artist.isEmpty) return const SizedBox.shrink();
            return Text(
              artist,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            );
          }),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  右侧面板（歌词 + 控制）
// ══════════════════════════════════════════════════════════════════════════════

class _RightPanel extends StatelessWidget {
  final MusicPlayerController ctrl;
  const _RightPanel({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 歌词滚动区
        Expanded(child: _LyricsView(ctrl: ctrl)),
        // 播放控制区
        _ControlsBar(ctrl: ctrl),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  歌词滚动视图
// ══════════════════════════════════════════════════════════════════════════════

class _LyricsView extends StatefulWidget {
  final MusicPlayerController ctrl;
  const _LyricsView({required this.ctrl});

  @override
  State<_LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends State<_LyricsView> {
  final ScrollController _scrollCtrl = ScrollController();
  static const double _itemHeight = 44.0;
  static const double _topPad     = 120.0;

  @override
  void initState() {
    super.initState();
    ever(widget.ctrl.currentLrcIdx, _onLrcIdxChanged);
  }

  void _onLrcIdxChanged(int idx) {
    if (!mounted) return;
    if (idx < 0) return;
    final offset = _topPad + idx * _itemHeight - 160;
    if (_scrollCtrl.hasClients) {
      _scrollCtrl.animateTo(
        offset.clamp(0.0, _scrollCtrl.position.maxScrollExtent),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Obx(() {
      final meta = widget.ctrl.currentMeta.value;

      // 元数据加载中
      if (meta == null) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: scheme.primary),
              ),
              const SizedBox(height: 12),
              Text('加载中...',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant)),
            ],
          ),
        );
      }

      // 无歌词
      if (meta.lrcLines.isEmpty) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lyrics_outlined,
                  size: 48,
                  color: scheme.onSurfaceVariant.withAlpha(80)),
              const SizedBox(height: 12),
              Text('暂无歌词',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant)),
            ],
          ),
        );
      }

      final lines      = meta.lrcLines;
      final activeIdx  = widget.ctrl.currentLrcIdx.value;

      return ListView.builder(
        controller: _scrollCtrl,
        padding: const EdgeInsets.symmetric(
            horizontal: 32, vertical: _topPad),
        itemCount: lines.length,
        itemExtent: _itemHeight,
        itemBuilder: (_, i) {
          final isActive = i == activeIdx;
          return Center(
            child: Text(
              lines[i].text,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: isActive
                        ? scheme.primary
                        : scheme.onSurface.withAlpha(isActive ? 255 : 140),
                    fontWeight: isActive
                        ? FontWeight.w700
                        : FontWeight.normal,
                    fontSize: isActive ? 17 : 15,
                  ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          );
        },
      );
    });
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  播放控制栏
// ══════════════════════════════════════════════════════════════════════════════

class _ControlsBar extends StatelessWidget {
  final MusicPlayerController ctrl;
  const _ControlsBar({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text   = Theme.of(context).textTheme;

    return Container(
      decoration: BoxDecoration(
        border: Border(
            top: BorderSide(color: scheme.outlineVariant.withAlpha(60))),
        color: scheme.surface,
      ),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 进度条
          Obx(() {
            final pos = ctrl.position.value;
            final dur = ctrl.duration.value;
            final pct = dur.inMilliseconds > 0
                ? pos.inMilliseconds / dur.inMilliseconds
                : 0.0;
            return Column(
              children: [
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 6),
                    overlayShape:
                        const RoundSliderOverlayShape(overlayRadius: 14),
                  ),
                  child: Slider(
                    value: pct.clamp(0.0, 1.0),
                    onChanged: (v) {
                      final t = (v * dur.inMilliseconds).round();
                      ctrl.seekTo(Duration(milliseconds: t));
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      Text(_fmt(pos), style: text.bodySmall),
                      const Spacer(),
                      Text(_fmt(dur), style: text.bodySmall),
                    ],
                  ),
                ),
              ],
            );
          }),

          const SizedBox(height: 8),

          // 主控制按钮行（左侧短音量条 + 居中的播放控制按钮）
          Row(
            children: [
              // 左侧音量条（固定宽度，不再独占一行）
              Obx(() => SizedBox(
                    width: 140,
                    child: Row(
                      children: [
                        Icon(
                          ctrl.volume.value == 0
                              ? Icons.volume_off_rounded
                              : ctrl.volume.value < 50
                                  ? Icons.volume_down_rounded
                                  : Icons.volume_up_rounded,
                          size: 18,
                          color: scheme.onSurfaceVariant,
                        ),
                        Expanded(
                          child: SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              trackHeight: 3,
                              thumbShape: const RoundSliderThumbShape(
                                  enabledThumbRadius: 5),
                              overlayShape: const RoundSliderOverlayShape(
                                  overlayRadius: 12),
                            ),
                            child: Slider(
                              value: ctrl.volume.value.clamp(0, 100),
                              min: 0,
                              max: 100,
                              onChanged: ctrl.setVolume,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )),

              // 中间播放控制按钮（保持原有位置不变，居中于整行）
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // 循环模式
                    Obx(() => Tooltip(
                          message: _repeatLabel(ctrl.repeatMode.value),
                          child: IconButton(
                            icon: Icon(
                              _repeatIcon(ctrl.repeatMode.value),
                              color: ctrl.repeatMode.value == RepeatMode.shuffle
                                  ? scheme.primary
                                  : null,
                            ),
                            onPressed: ctrl.cycleRepeat,
                          ),
                        )),

                    const SizedBox(width: 8),

                    // 上一首
                    IconButton(
                      icon: const Icon(Icons.skip_previous_rounded, size: 30),
                      onPressed: ctrl.previous,
                    ),

                    const SizedBox(width: 4),

                    // 播放 / 暂停
                    Obx(() => FilledButton(
                          onPressed: ctrl.togglePlay,
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.all(14),
                            shape: const CircleBorder(),
                          ),
                          child: Icon(
                            ctrl.isPlaying.value
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            size: 28,
                          ),
                        )),

                    const SizedBox(width: 4),

                    // 下一首
                    IconButton(
                      icon: const Icon(Icons.skip_next_rounded, size: 30),
                      onPressed: ctrl.next,
                    ),

                    const SizedBox(width: 8),

                    // 播放速度
                    PopupMenuButton<double>(
                      tooltip: '播放速度',
                      icon: Obx(() => Text(
                            '${ctrl.playSpeed.value}x',
                            style: text.bodySmall,
                          )),
                      onSelected: ctrl.setSpeed,
                      itemBuilder: (_) => [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
                          .map((s) => PopupMenuItem(
                                value: s,
                                child: Text('${s}x'),
                              ))
                          .toList(),
                    ),
                  ],
                ),
              ),

              // 右侧留白，抵消左侧音量条宽度，让播放控制按钮真正居中
              const SizedBox(width: 140),
            ],
          ),
        ],
      ),
    );
  }

  IconData _repeatIcon(RepeatMode m) {
    switch (m) {
      case RepeatMode.one:     return Icons.repeat_one_rounded;
      case RepeatMode.shuffle: return Icons.shuffle_rounded;
      case RepeatMode.list:    return Icons.repeat_rounded;
    }
  }

  String _repeatLabel(RepeatMode m) {
    switch (m) {
      case RepeatMode.list:    return '列表循环';
      case RepeatMode.shuffle: return '随机播放';
      case RepeatMode.one:     return '单曲循环';
    }
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  播放队列面板（右侧覆盖层，仿 NovaBox 队列面板）
// ══════════════════════════════════════════════════════════════════════════════

class _QueuePanel extends StatelessWidget {
  final MusicPlayerController ctrl;
  const _QueuePanel({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(
            left: BorderSide(color: scheme.outlineVariant.withAlpha(60))),
      ),
      child: Column(
          children: [
            // 面板标题
            Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
              decoration: BoxDecoration(
                border: Border(
                    bottom: BorderSide(
                        color: scheme.outlineVariant.withAlpha(60))),
              ),
              child: Row(
                children: [
                  Text(
                    '播放列表',
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(width: 8),
                  // 注意：playlist 是普通 late 字段（onInit 后不再变化），
                  // 不是 .obs / RxList，这里不需要（也不应该）包 Obx——
                  // 之前误包了 Obx 会导致 GetX 抛出
                  // "improper use of a GetX" 断言错误。
                  Text(
                    '${ctrl.playlist.length} 首',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  const Spacer(),
                  // 当前循环模式
                  Obx(() => Tooltip(
                        message: _repeatLabel(ctrl.repeatMode.value),
                        child: Icon(
                          _repeatIcon(ctrl.repeatMode.value),
                          size: 18,
                          color: ctrl.repeatMode.value == RepeatMode.shuffle
                              ? scheme.primary
                              : scheme.onSurfaceVariant,
                        ),
                      )),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: ctrl.toggleQueue,
                    tooltip: '关闭',
                  ),
                ],
              ),
            ),

            // 列表
            Expanded(
              child: Obx(() {
                final activeIdx = ctrl.currentIdx.value;
                final total     = ctrl.playlist.length;

                if (total == 0) {
                  return const Center(child: Text('播放列表为空'));
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: total,
                  itemBuilder: (_, i) {
                    // 防御：避免 GetX 响应式刷新时序错位（list 已变但
                    // itemCount 还没更新）导致的越界访问，让单个 item
                    // 出错时不至于把整个面板"吞"成一片灰色。
                    try {
                      if (i < 0 || i >= ctrl.playlist.length) {
                        return const SizedBox.shrink();
                      }
                      final track  = ctrl.playlist[i];
                      final name   = p.withoutExtension(track['name'] ?? '');
                      final active = i == activeIdx;
                      return _QueueTile(
                        index:  i + 1,
                        name:   name,
                        active: active,
                        onTap:  () => ctrl.playAt(i),
                      );
                    } catch (e) {
                      // 出错时直接显示错误信息，而不是让整块面板变成
                      // 看不出任何内容的灰色空白，方便定位问题。
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        child: Text('第 ${i + 1} 项加载失败: $e',
                            style: const TextStyle(
                                color: Colors.red, fontSize: 11)),
                      );
                    }
                  },
                );
              }),
            ),
          ],
        ),
    );
  }

  IconData _repeatIcon(RepeatMode m) {
    switch (m) {
      case RepeatMode.one:     return Icons.repeat_one_rounded;
      case RepeatMode.shuffle: return Icons.shuffle_rounded;
      case RepeatMode.list:    return Icons.repeat_rounded;
    }
  }

  String _repeatLabel(RepeatMode m) {
    switch (m) {
      case RepeatMode.list:    return '列表循环';
      case RepeatMode.shuffle: return '随机播放';
      case RepeatMode.one:     return '单曲循环';
    }
  }
}

class _QueueTile extends StatefulWidget {
  final int index;
  final String name;
  final bool active;
  final VoidCallback onTap;

  const _QueueTile({
    required this.index,
    required this.name,
    required this.active,
    required this.onTap,
  });

  @override
  State<_QueueTile> createState() => _QueueTileState();
}

class _QueueTileState extends State<_QueueTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      child: InkWell(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          color: _hovered
              ? scheme.primaryContainer.withAlpha(60)
              : Colors.transparent,
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              // 序号 / 播放中图标
              SizedBox(
                width: 28,
                child: widget.active
                    ? Icon(Icons.equalizer_rounded,
                        size: 16, color: scheme.primary)
                    : Text(
                        '${widget.index}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                        textAlign: TextAlign.center,
                      ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: widget.active ? scheme.primary : null,
                        fontWeight: widget.active
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
