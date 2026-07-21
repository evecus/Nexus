import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:player_shared/player_shared.dart';
import 'package:window_manager/window_manager.dart';

import 'package:nexus_windows/app/controller/app_settings_controller.dart';
import 'package:nexus_windows/app/controller/global_player_controller.dart';
import 'package:nexus_windows/player/vlc_backend.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Controller
// ─────────────────────────────────────────────────────────────────────────────

class IptvPlayerController extends GetxController
    with PlayerMixin, PlayerStateMixin {

  // ── Channel data ─────────────────────────────────────────────────────────
  final allChannels     = <M3uChannel>[].obs;
  final grouped         = <String, List<M3uChannel>>{}.obs;

  /// The group currently shown in the channel column (browsing cursor)
  final browseGroup     = ''.obs;

  /// The group the currently-playing channel belongs to (for persistent highlight)
  final playingGroup    = ''.obs;

  /// Name of the channel currently playing
  final channelName     = ''.obs;

  /// All URLs for current channel (源1/源2/…)
  final streamUrls      = <String>[].obs;

  /// Which stream URL index is currently active
  final streamIndex     = 0.obs;

  // ── Source (playlist) data ────────────────────────────────────────────────
  final sources         = <Map<String, String>>[].obs;
  final sourceIndex     = 0.obs;

  // ── Player state ──────────────────────────────────────────────────────────
  final isBuffering     = false.obs;
  final isPlaying       = false.obs;
  final volume          = 100.0.obs;
  final isLoading       = false.obs;

  // ── Args ──────────────────────────────────────────────────────────────────
  late final String initialUrl;
  late final String initialChannelName;
  late final String initialGroupName;
  late final int    initialSourceIdx;

  // ── ScrollControllers so we can auto-scroll to playing items ─────────────
  final groupScrollCtrl   = ScrollController();
  final channelScrollCtrl = ScrollController();
  final streamScrollCtrl  = ScrollController();

  @override
  void onInit() {
    super.onInit();
    final args         = Get.arguments as Map<String, dynamic>? ?? {};
    initialUrl         = args['url']         as String? ?? '';
    initialChannelName = args['channelName'] as String? ?? '';
    initialGroupName   = args['groupName']   as String? ?? '';
    initialSourceIdx   = args['sourceIndex'] as int?    ?? 0;

    channelName.value  = initialChannelName;
    playingGroup.value = initialGroupName;

    final settings = AppSettingsController.instance;
    sources.assignAll(settings.iptvSources);

    // 开始播放 IPTV：停止全局音乐播放（视频/IPTV 优先于音乐）。
    GlobalPlayerController.instance.stopMusicForOtherPlayback();

    final s = AppSettingsController.instance;
    // 按用户设置选择后端：vlc / mpv（IPTV 场景下 auto 也走 mpv）
    final backendType = s.resolveBackendType(isIptv: true);

    if (backendType == PlayerBackendType.vlc) {
      // VLC 后端：对 IPTV 直播流兼容性最好，自带去交错 + 网络缓冲协商。
      // vlcHardwareDecode 与设置页"VLC解码方式"联动。
      initPlayer(
              backend: VlcBackend(hardwareDecode: s.vlcHardwareDecode.value))
          .then((_) async {
        backend.buffering.listen((v) => isBuffering.value = v);
        backend.playing.listen((v)   => isPlaying.value   = v);
        backend.volume.listen((v)    => volume.value      = v);
        autoHideControls();
        if (sources.isNotEmpty) {
          await loadSource(initialSourceIdx.clamp(0, sources.length - 1));
        }
      });
    } else {
      // MPV 后端（默认）：保留原有的 mpv options 调优
      final config = buildControllerConfig(
        hardwareDecode: s.hardwareDecode.value,
        compatMode: false,
        profile: s.mpvProfile.value,
      );
      initPlayer(config: config).then((_) async {
        player.stream.buffering.listen((v) => isBuffering.value = v);
        player.stream.playing.listen((v)   => isPlaying.value   = v);
        player.stream.volume.listen((v)    => volume.value      = v);

        await applyMpvOptions(
          player,
          s.mpvProfile.value,
          hardwareDecode: s.hardwareDecode.value,
          // TODO(test-only): 临时强制开启去交错滤镜 + TS 流容错缓冲，
          // 用于验证运动画面梳齿状条纹的真正根因。
          // 验证完成后请根据结果移除此行或改为走设置项控制。
          forceDeinterlaceFilter: true,
          forceTsResilience: true,
        );
        autoHideControls();
        if (sources.isNotEmpty) {
          await loadSource(initialSourceIdx.clamp(0, sources.length - 1));
        }
      });
    }
  }

  // ── Groups (no "全部") ────────────────────────────────────────────────────

  List<String> get groups => grouped.keys.toList();

  List<M3uChannel> get browsedChannels {
    if (browseGroup.value.isEmpty) return [];
    // Deduplicate by name
    final seen = <String>{};
    return (grouped[browseGroup.value] ?? [])
        .where((c) => seen.add(c.name))
        .toList();
  }

  // ── Load a playlist source ────────────────────────────────────────────────

  Future<void> loadSource(int idx) async {
    if (idx < 0 || idx >= sources.length) return;
    final src = sources[idx];
    sourceIndex.value = idx;
    isLoading.value   = true;
    try {
      String content = '';
      if (src['type'] == 'file') {
        final path = src['filePath'] ?? '';
        if (path.isNotEmpty) content = await File(path).readAsString();
      } else {
        final url = src['url'] ?? '';
        if (url.isNotEmpty) {
          final r = await Dio().get<String>(url,
              options: Options(responseType: ResponseType.plain));
          content = r.data ?? '';
        }
      }
      if (content.isNotEmpty) {
        final parsed = M3uParser.parse(content);
        allChannels.value = parsed;
        grouped.value     = M3uParser.groupBy(parsed);

        final grps = groups;
        if (grps.isEmpty) return;

        // Determine which group/channel to auto-play:
        // If we already know a playing group from args, use that.
        // Otherwise default to first group's first channel.
        String targetGroup   = grps.first;
        M3uChannel? targetCh;

        if (initialGroupName.isNotEmpty && grps.contains(initialGroupName)) {
          targetGroup = initialGroupName;
        }
        if (initialChannelName.isNotEmpty) {
          targetCh = (grouped[targetGroup] ?? [])
              .firstWhereOrNull((c) => c.name == initialChannelName);
        }
        targetCh ??= (grouped[targetGroup] ?? []).firstOrNull;

        browseGroup.value  = targetGroup;
        playingGroup.value = targetGroup;

        if (targetCh != null) {
          // autoPlay 逻辑：只要能匹配到目标频道（无论是否同时带了 url），
          // 都应该自动播放——url 只在"匹配不到频道名"时才作为兜底直接播放。
          // 之前仅用 initialUrl.isEmpty 判断，会导致底部播放栏续播时
          // （resumeArgs 里 url/channelName 都有值）反而不自动播放。
          _selectChannelInternal(targetCh, autoPlay: true);
        } else if (initialUrl.isNotEmpty) {
          // fallback: play the passed URL directly
          streamUrls.value  = [initialUrl];
          streamIndex.value = 0;
          _playStream(
            initialUrl,
            channelName:
                initialChannelName.isNotEmpty ? initialChannelName : '(未知频道-fallback)',
            sourceLabel: '源1',
            callSite: 'fallback-initialUrl',
          );
        }
      }
    } catch (_) {
      // silent
    } finally {
      isLoading.value = false;
    }
  }

  // ── Channel selection ─────────────────────────────────────────────────────

  void selectChannel(M3uChannel ch) => _selectChannelInternal(ch, autoPlay: true);

  void _selectChannelInternal(M3uChannel ch, {required bool autoPlay}) {
    channelName.value  = ch.name;
    playingGroup.value = ch.group;

    // Collect all distinct URLs for channels with this name (= the 源 list)
    final urls = allChannels
        .where((c) => c.name == ch.name)
        .map((c) => c.url)
        .toSet()
        .toList();
    streamUrls.value  = urls.isNotEmpty ? urls : [ch.url];
    streamIndex.value = 0;

    if (autoPlay) {
      _playStream(
        streamUrls.first,
        channelName: ch.name,
        sourceLabel: '源${streamIndex.value + 1}',
        callSite: 'selectChannel(autoPlay)',
      );
    }
    _reportStateToGlobal();
  }

  void selectStream(int idx) {
    if (idx < 0 || idx >= streamUrls.length) return;
    streamIndex.value = idx;
    _playStream(
      streamUrls[idx],
      channelName: channelName.value,
      sourceLabel: '源${idx + 1}',
      callSite: 'selectStream',
    );
    _reportStateToGlobal();
  }

  void _playStream(
    String url, {
    required String channelName,
    required String sourceLabel,
    required String callSite,
  }) {
    // 统一走 backend.open()：mpv 后端底层就是 player.open(Media(url))，
    // vlc 后端则是销毁旧 controller 并新建一个 network controller。
    backend.open(url);
    autoHideControls();

    // MPV 后端专属：player.open() 会重新初始化 mpv 的内部播放状态，
    // 之前通过 applyMpvOptions（含 vf-add yadif）应用的滤镜链会被清空，
    // 因此每次切流后需要重新应用。VLC 后端自带去交错 + 缓冲，不需要。
    if (isMpv) {
      final s = AppSettingsController.instance;
      applyMpvOptions(
        player,
        s.mpvProfile.value,
        hardwareDecode: s.hardwareDecode.value,
        forceDeinterlaceFilter: true,
        forceTsResilience: true,
      );
    }
  }

  /// 把当前频道信息同步给全局控制器，供底部播放栏展示 + 退出后续播（记录频道）。
  void _reportStateToGlobal() {
    GlobalPlayerController.instance.updateIptvState(
      channelName: channelName.value,
      groupName: playingGroup.value,
      resumeArgs: {
        'url': streamUrls.isNotEmpty ? streamUrls[streamIndex.value] : initialUrl,
        'channelName': channelName.value,
        'groupName': playingGroup.value,
        'sourceIndex': sourceIndex.value,
      },
    );
  }

  // ── Controls ──────────────────────────────────────────────────────────────

  /// 统一走 backend：mpv 后端底层就是 player.playOrPause()，
  /// vlc 后端则是 VlcPlayerController.play()/pause()。两个后端都支持，
  /// 无需在调用处做 isMpv 判断。
  void togglePlay() => backend.playOrPause();

  void setVolume(double v) {
    volume.value = v;
    // 统一走 backend：mpv 后端会通过 player.stream.volume 反推回来；
    // vlc 后端则在 VlcPlayerValue.volume 变化时通过 _volumeCtrl 推送。
    backend.setVolume(v);
  }

  // ── Fullscreen ────────────────────────────────────────────────────────────

  Future<void> enterFullScreen() async {
    await windowManager.setFullScreen(true);
    isFullScreen.value = true;
    autoHideControls(seconds: 3);
  }

  Future<void> exitFullScreen() async {
    await windowManager.setFullScreen(false);
    isFullScreen.value = false;
    showControls.value = true;
  }

  void onMouseMove() => autoHideControls(seconds: 3);

  @override
  void onClose() {
    if (isFullScreen.value) windowManager.setFullScreen(false);
    // 退出播放页即停止播放（需求：IPTV 退出播放页后停止播放，但记录频道），
    // 保留频道信息给底部播放栏用于展示 + 再次点击续播。
    if (channelName.value.isNotEmpty) _reportStateToGlobal();
    groupScrollCtrl.dispose();
    channelScrollCtrl.dispose();
    streamScrollCtrl.dispose();
    disposePlayer();
    super.onClose();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Page
// ─────────────────────────────────────────────────────────────────────────────

class IptvPlayerPage extends StatefulWidget {
  const IptvPlayerPage({super.key});
  @override
  State<IptvPlayerPage> createState() => _IptvPlayerPageState();
}

class _IptvPlayerPageState extends State<IptvPlayerPage> {
  late final IptvPlayerController ctrl;

  @override
  void initState() {
    super.initState();
    ctrl = Get.put(IptvPlayerController());
  }

  @override
  void dispose() {
    Get.delete<IptvPlayerController>();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Obx(() => ctrl.isFullScreen.value
      ? _FullScreenPlayer(ctrl: ctrl)
      : _SplitPlayer(ctrl: ctrl));
}

// ─────────────────────────────────────────────────────────────────────────────
// Split layout
// ─────────────────────────────────────────────────────────────────────────────

class _SplitPlayer extends StatelessWidget {
  final IptvPlayerController ctrl;
  const _SplitPlayer({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: FocusNode()..requestFocus(),
      autofocus: true,
      onKeyEvent: (e) {
        if (e is! KeyDownEvent) return;
        if (e.logicalKey == LogicalKeyboardKey.space) ctrl.togglePlay();
        if (e.logicalKey == LogicalKeyboardKey.escape) Get.back();
        if (e.logicalKey == LogicalKeyboardKey.keyF) ctrl.enterFullScreen();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Row(
          children: [
            Expanded(flex: 7, child: _VideoArea(ctrl: ctrl, isFullScreen: false)),
            SizedBox(width: 360, child: _ChannelPanel(ctrl: ctrl)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Fullscreen
// ─────────────────────────────────────────────────────────────────────────────

class _FullScreenPlayer extends StatelessWidget {
  final IptvPlayerController ctrl;
  const _FullScreenPlayer({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: FocusNode()..requestFocus(),
      autofocus: true,
      onKeyEvent: (e) {
        if (e is! KeyDownEvent) return;
        if (e.logicalKey == LogicalKeyboardKey.space) ctrl.togglePlay();
        if (e.logicalKey == LogicalKeyboardKey.escape) ctrl.exitFullScreen();
        if (e.logicalKey == LogicalKeyboardKey.keyF) ctrl.exitFullScreen();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: _VideoArea(ctrl: ctrl, isFullScreen: true),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Video area with hover-reveal controls
// ─────────────────────────────────────────────────────────────────────────────

class _VideoArea extends StatelessWidget {
  final IptvPlayerController ctrl;
  final bool isFullScreen;
  const _VideoArea({required this.ctrl, required this.isFullScreen});

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onHover: (_) => ctrl.onMouseMove(),
      onEnter: (_) => ctrl.onMouseMove(),
      cursor: SystemMouseCursors.basic,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 统一走 backend.buildView()：
          // - mpv 后端返回 media_kit_video 的 Video（内部用 ctrl.videoController）
          // - vlc 后端返回 _VlcView（监听 VlcBackend 的 ChangeNotifier）
          // 这样切后端时无需改 UI 代码，videoController getter 也只在 mpv
          // 路径内部被调用，vlc 路径不会触发它的 StateError。
          //
          // 必须传 ctrl.playerKey（GlobalKey）：分屏↔全屏切换时整个 widget
          // 子树从 _SplitPlayer 换成 _FullScreenPlayer，没有 GlobalKey 的话
          // VlcPlayer/Video 的 State 会被销毁后重建——Windows 上 VLC 是
          // texture-backed，旧 State 销毁会释放纹理，新 State 无法重建纹理
          // 表面，表现为全屏黑屏。用 GlobalKey 让 Flutter 把同一份 State
          // 从旧子树位置"移动"到新位置，纹理不中断。
          ctrl.backend.buildView(key: ctrl.playerKey, fill: Colors.black),
          Obx(() => ctrl.isBuffering.value
              ? const Center(child: CircularProgressIndicator(color: Colors.white))
              : const SizedBox()),
          Obx(() => AnimatedOpacity(
                opacity: ctrl.showControls.value ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 220),
                child: Stack(children: [
                  // ── Top bar ──────────────────────────────────────────────
                  Positioned(
                    top: 0, left: 0, right: 0,
                    child: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.black87, Colors.transparent],
                        ),
                      ),
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 32),
                      child: Row(children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back,
                              color: Colors.white, size: 22),
                          tooltip: '返回',
                          onPressed: isFullScreen
                              ? () => ctrl.exitFullScreen()
                              : () => Get.back(),
                        ),
                        const SizedBox(width: 6),
                        Obx(() => Expanded(
                          child: Text(ctrl.channelName.value,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600),
                              overflow: TextOverflow.ellipsis),
                        )),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: const Text('LIVE',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11)),
                        ),
                      ]),
                    ),
                  ),
                  // ── Bottom bar ────────────────────────────────────────────
                  Positioned(
                    bottom: 0, left: 0, right: 0,
                    child: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [Colors.black87, Colors.transparent],
                        ),
                      ),
                      padding: const EdgeInsets.fromLTRB(16, 32, 16, 12),
                      child: Row(children: [
                        Obx(() => IconButton(
                          icon: Icon(
                            ctrl.isPlaying.value
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            color: Colors.white, size: 28),
                          onPressed: ctrl.togglePlay,
                        )),
                        const SizedBox(width: 4),
                        const Icon(Icons.volume_up,
                            color: Colors.white70, size: 18),
                        Obx(() => SizedBox(
                          width: 90,
                          child: SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              trackHeight: 2,
                              thumbShape: const RoundSliderThumbShape(
                                  enabledThumbRadius: 5),
                              activeTrackColor: Colors.white,
                              inactiveTrackColor: Colors.white30,
                              thumbColor: Colors.white,
                              overlayShape: SliderComponentShape.noOverlay,
                            ),
                            child: Slider(
                              value: ctrl.volume.value.clamp(0, 100),
                              min: 0, max: 100,
                              onChanged: ctrl.setVolume,
                            ),
                          ),
                        )),
                        const Spacer(),
                        IconButton(
                          icon: Icon(
                            isFullScreen
                                ? Icons.fullscreen_exit_rounded
                                : Icons.fullscreen_rounded,
                            color: Colors.white, size: 26),
                          tooltip: isFullScreen ? '退出全屏' : '全屏',
                          onPressed: isFullScreen
                              ? () => ctrl.exitFullScreen()
                              : () => ctrl.enterFullScreen(),
                        ),
                      ]),
                    ),
                  ),
                ]),
              )),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Right-side channel panel — strict 3-column layout matching NovaBox
// ─────────────────────────────────────────────────────────────────────────────

class _ChannelPanel extends StatelessWidget {
  final IptvPlayerController ctrl;
  const _ChannelPanel({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Column(
        children: [
          // ── Header: channel name ────────────────────────────────────────
          Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(
              border: Border(
                  bottom: BorderSide(color: scheme.outlineVariant.withAlpha(60))),
            ),
            child: Obx(() => Text(
              ctrl.channelName.value.isEmpty ? 'IPTV' : ctrl.channelName.value,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            )),
          ),

          // ── Three-column body ───────────────────────────────────────────
          Expanded(
            child: Obx(() {
              if (ctrl.isLoading.value) {
                return const Center(child: CircularProgressIndicator());
              }
              if (ctrl.grouped.isEmpty) {
                return Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.live_tv_outlined,
                        size: 48, color: scheme.onSurfaceVariant.withAlpha(80)),
                    const SizedBox(height: 12),
                    Text('暂无频道',
                        style: TextStyle(fontSize: 13,
                            color: scheme.onSurfaceVariant)),
                  ]),
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Column 1: Groups (80px fixed)
                  SizedBox(
                    width: 80,
                    child: _GroupColumn(ctrl: ctrl),
                  ),
                  VerticalDivider(
                      width: 1,
                      color: scheme.outlineVariant.withAlpha(80)),
                  // Column 2: Channels (flexible)
                  Expanded(child: _ChannelColumn(ctrl: ctrl)),
                  VerticalDivider(
                      width: 1,
                      color: scheme.outlineVariant.withAlpha(80)),
                  // Column 3: Streams (72px fixed)
                  SizedBox(
                    width: 72,
                    child: _StreamColumn(ctrl: ctrl),
                  ),
                ],
              );
            }),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Column 1 — Groups
// ─────────────────────────────────────────────────────────────────────────────

class _GroupColumn extends StatelessWidget {
  final IptvPlayerController ctrl;
  const _GroupColumn({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Obx(() {
      final grps = ctrl.groups;
      return ListView.builder(
        controller: ctrl.groupScrollCtrl,
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: grps.length,
        itemBuilder: (_, i) {
          final g = grps[i];
          // 用 Obx 包裹每一项，让高亮状态能响应 browseGroup / playingGroup
          // 的变化——这两个值是在 itemBuilder 回调里读取的，而 itemBuilder
          // 是 Flutter 渲染时才异步调用的，不在外层 Obx().builder 的同步
          // 执行栈内，外层 Obx 建立不了对它们的依赖，只有 grps（分组键集合
          // 本身）变化时才会重建。切换浏览分组/切换播放频道都不会改变
          // grps，所以外层 Obx 永远不会因为这两个状态的变化而重建，高亮
          // 就一直停留在首次渲染时的状态。
          return Obx(() {
            final isBrowsing = ctrl.browseGroup.value == g;
            final isPlaying  = ctrl.playingGroup.value == g;
            return InkWell(
              onTap: () => ctrl.browseGroup.value = g,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 130),
                margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
                decoration: BoxDecoration(
                  color: isBrowsing
                      ? scheme.primary
                      : isPlaying
                          ? scheme.primaryContainer.withAlpha(120)
                          : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  g,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: isBrowsing
                        ? scheme.onPrimary
                        : isPlaying
                            ? scheme.primary
                            : scheme.onSurface,
                    fontWeight: (isBrowsing || isPlaying)
                        ? FontWeight.w600
                        : FontWeight.normal,
                  ),
                ),
              ),
            );
          });
        },
      );
    });
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Column 2 — Channels (for the browsed group)
// ─────────────────────────────────────────────────────────────────────────────

class _ChannelColumn extends StatelessWidget {
  final IptvPlayerController ctrl;
  const _ChannelColumn({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final list = ctrl.browsedChannels;
      if (list.isEmpty) {
        return Center(
          child: Text('请选择分组',
              style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
        );
      }
      return ListView.builder(
        controller: ctrl.channelScrollCtrl,
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: list.length,
        itemBuilder: (_, i) {
          final ch = list[i];
          // 用 Obx 包裹每一项，让"是否正在播放"的高亮能响应 channelName
          // 的变化——原因同分组列表：channelName.value 是在 itemBuilder
          // 回调里读取的，外层 Obx 只在 browsedChannels（分组切换）变化时
          // 重建，同一分组内切换播放频道不会触发外层重建，高亮就不会更新。
          return Obx(() {
            final isPlaying = ctrl.channelName.value == ch.name;
            return _ChannelTile(
              ch: ch,
              selected: isPlaying,
              onTap: () => ctrl.selectChannel(ch),
            );
          });
        },
      );
    });
  }
}

class _ChannelTile extends StatefulWidget {
  final M3uChannel ch;
  final bool selected;
  final VoidCallback onTap;
  const _ChannelTile(
      {required this.ch, required this.selected, required this.onTap});
  @override
  State<_ChannelTile> createState() => _ChannelTileState();
}

class _ChannelTileState extends State<_ChannelTile> {
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
          color: widget.selected
              ? scheme.primaryContainer.withAlpha(180)
              : _hovered
                  ? scheme.surfaceContainerHighest
                  : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          child: Row(children: [
            // Logo / fallback
            if (widget.ch.logo.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: Image.network(
                  widget.ch.logo,
                  width: 24, height: 24,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => _icon(scheme),
                ),
              )
            else
              _icon(scheme),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                widget.ch.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: widget.selected ? FontWeight.w700 : FontWeight.normal,
                  color: widget.selected
                      ? scheme.onPrimaryContainer
                      : scheme.onSurface,
                ),
              ),
            ),
            if (widget.selected)
              Icon(Icons.play_arrow_rounded,
                  size: 13, color: scheme.primary),
          ]),
        ),
      ),
    );
  }

  Widget _icon(ColorScheme s) => Container(
        width: 24, height: 24,
        decoration: BoxDecoration(
          color: s.primaryContainer.withAlpha(60),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Icon(Icons.live_tv, size: 13, color: s.primary),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Column 3 — Streams (源1/源2/…) — always visible, always 3+ items tall
// ─────────────────────────────────────────────────────────────────────────────

class _StreamColumn extends StatelessWidget {
  final IptvPlayerController ctrl;
  const _StreamColumn({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Obx(() {
      final urls   = ctrl.streamUrls;
      final selIdx = ctrl.streamIndex.value;
      // Always show at least some placeholder rows when no streams yet
      final count  = urls.isEmpty ? 0 : urls.length;
      return ListView.builder(
        controller: ctrl.streamScrollCtrl,
        padding: const EdgeInsets.symmetric(vertical: 6),
        itemCount: count,
        itemBuilder: (_, i) {
          final isSelected = selIdx == i;
          return InkWell(
            onTap: () => ctrl.selectStream(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 110),
              margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected ? scheme.primary : scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                '源${i + 1}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.normal,
                  color: isSelected ? scheme.onPrimary : scheme.onSurfaceVariant,
                ),
              ),
            ),
          );
        },
      );
    });
  }
}
