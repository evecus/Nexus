import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:player_shared/player_shared.dart';

import 'package:nexus/app/controller/tv_settings_controller.dart';
import 'package:nexus/app/theme/tv_theme.dart';
import 'package:nexus/app/tv_focus_node.dart';
import 'package:nexus/app/tv_style.dart';
import 'package:nexus/player/exo_backend.dart';
import 'package:nexus/widgets/tv_highlight.dart';
import 'package:nexus/modules/music/player/tv_music_player_page.dart'
    show TvMusicPlayerController;

/// IPTV 全屏播放控制器。
///
/// - 进入页面后加载指定 M3U 源,解析全部频道,默认播放第一个频道的第一个线路。
/// - 遥控器按确定键唤出左侧三列弹窗(分组 | 频道 | 线路)。
///   * 切换分组:只刷新频道列表和线路列表,不切换播放。
///   * 切换频道:切到该频道的第一个线路播放。
///   * 切换线路:切到该线路播放。
/// - 弹窗 5 秒无操作或按返回键自动关闭;弹窗关闭后按返回键退出播放页。
class TvIptvPlayerController extends GetxController
    with PlayerMixin, TvPlayerStateMixin {
  // ── 频道数据 ──────────────────────────────────────────
  final allChannels = <M3uChannel>[].obs;
  final grouped = <String, List<M3uChannel>>{}.obs;

  /// 当前浏览的分组(频道列高亮)
  final browseGroup = ''.obs;

  /// 当前播放频道所在分组(持久高亮)
  final playingGroup = ''.obs;

  /// 当前播放的频道名
  final channelName = ''.obs;

  /// 当前频道的所有线路 URL(源1/源2/…)
  final streamUrls = <String>[].obs;
  final streamIndex = 0.obs;

  // ── 源数据 ────────────────────────────────────────────
  final sources = <Map<String, String>>[].obs;
  final sourceIndex = 0.obs;

  // ── 播放器状态 ────────────────────────────────────────
  final isBuffering = false.obs;
  final isPlaying = false.obs;
  final isLoading = false.obs;

  // ── 弹窗 ──────────────────────────────────────────────
  /// 左侧三列弹窗是否显示
  final showPanel = false.obs;
  Timer? _hideTimer;

  List<String> get groups => grouped.keys.toList();

  /// 当前浏览分组下的频道(按名称去重,保留首个)
  List<M3uChannel> get browsedChannels {
    if (browseGroup.value.isEmpty) return [];
    final seen = <String>{};
    return (grouped[browseGroup.value] ?? [])
        .where((c) => seen.add(c.name))
        .toList();
  }

  @override
  void onInit() {
    super.onInit();
    // 媒体互斥：开始播放 IPTV 前，先停止可能正在播放的音乐。
    if (Get.isRegistered<TvMusicPlayerController>()) {
      TvMusicPlayerController.instance.stopForOtherMedia();
    }
    PlaybackBarController.instance.clear();

    final args = Get.arguments as Map<String, dynamic>? ?? {};
    final initialSourceIdx = args['sourceIndex'] as int? ?? 0;
    // 从顶部播放入口恢复播放时携带的目标频道信息（可选）：若提供则加载源后
    // 直接定位到该频道，而不是默认播放源里的第一个频道。
    _resumeChannelName = args['channelName'] as String?;
    _resumeGroupName = args['groupName'] as String?;

    final s = TvSettingsController.instance;
    sources.assignAll(s.iptvSources);

    // IPTV 直播场景：auto 模式下默认走 MPV（mpv 对 HLS/TS 流兼容性更好）
    final useExo = s.shouldUseExo(isIptv: true);
    final b = buildBackend(
      useExo: useExo,
      hardwareDecode: s.hardwareDecode.value,
      compatMode: s.compatMode.value,
      profile: s.mpvProfile.value,
      exoFactory: () => ExoBackend(),
    );

    // 注意：backend 字段是 late，在 initPlayer 内部才会赋值，
    // 所以这里用局部变量 b 来订阅流，避免 LateInitializationError。
    b.buffering.listen((v) => isBuffering.value = v);
    b.playing.listen((v) => isPlaying.value = v);

    initPlayer(backend: b).then((_) async {
      final mpv = mpvBackend;
      if (mpv != null) {
        await applyMpvOptions(mpv.player, s.mpvProfile.value);
      }
      autoHideControls(seconds: 5);
      if (sources.isNotEmpty) {
        await loadSource(initialSourceIdx.clamp(0, sources.length - 1));
      }
    });
  }

  /// 顶部播放入口恢复播放时携带的目标频道信息（可选，仅首次加载源时生效一次）。
  String? _resumeChannelName;
  String? _resumeGroupName;

  // ── 加载 M3U 源 ───────────────────────────────────────

  Future<void> loadSource(int idx) async {
    if (idx < 0 || idx >= sources.length) return;
    final src = sources[idx];
    sourceIndex.value = idx;
    isLoading.value = true;
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
        grouped.value = M3uParser.groupBy(parsed);

        final grps = groups;
        if (grps.isEmpty) return;

        // 若携带了恢复目标频道，优先尝试定位并播放该频道。
        final resumeName = _resumeChannelName;
        if (resumeName != null && resumeName.isNotEmpty) {
          final resumeGroup = _resumeGroupName ?? '';
          M3uChannel? match;
          for (final c in allChannels) {
            if (c.name == resumeName &&
                (resumeGroup.isEmpty || c.group == resumeGroup)) {
              match = c;
              break;
            }
          }
          if (match != null) {
            browseGroup.value = match.group;
            playingGroup.value = match.group;
            _selectChannel(match, autoPlay: true);
            // 仅首次加载生效一次，避免用户后续手动切台时被覆盖。
            _resumeChannelName = null;
            return;
          }
        }

        browseGroup.value = grps.first;
        playingGroup.value = grps.first;

        final chs = browsedChannels;
        if (chs.isNotEmpty) {
          _selectChannel(chs.first, autoPlay: true);
        }
      }
    } catch (_) {
      // silent
    } finally {
      isLoading.value = false;
    }
  }

  // ── 频道选择 ──────────────────────────────────────────

  void selectChannel(M3uChannel ch) =>
      _selectChannel(ch, autoPlay: true);

  void _selectChannel(M3uChannel ch, {required bool autoPlay}) {
    channelName.value = ch.name;
    playingGroup.value = ch.group;

    // 收集所有同名频道的 URL 作为多线路(源1/源2/…)
    final urls = allChannels
        .where((c) => c.name == ch.name)
        .map((c) => c.url)
        .toSet()
        .toList();
    streamUrls.value = urls.isNotEmpty ? urls : [ch.url];
    streamIndex.value = 0;

    if (autoPlay) _playStream(streamUrls.first);
  }

  void selectStream(int idx) {
    if (idx < 0 || idx >= streamUrls.length) return;
    streamIndex.value = idx;
    _playStream(streamUrls[idx]);
  }

  void _playStream(String url) {
    backend.open(url);
    autoHideControls(seconds: 5);
  }

  void togglePlay() => backend.playOrPause();

  // ── 弹窗控制 ──────────────────────────────────────────

  /// 唤出左侧弹窗,并启动 5 秒自动隐藏计时器。
  void showChannelPanel() {
    showPanel.value = true;
    _resetHideTimer();
  }

  /// 关闭弹窗(不退出页面)。
  void hideChannelPanel() {
    showPanel.value = false;
    _hideTimer?.cancel();
    _hideTimer = null;
  }

  /// 用户在弹窗内有任何操作时重置 5 秒计时器。
  void onPanelActivity() {
    if (showPanel.value) _resetHideTimer();
  }

  /// 切换浏览分组(只刷新频道列表,不切换播放)。
  void browseToGroup(String g) {
    browseGroup.value = g;
    onPanelActivity();
  }

  /// 切换浏览分组下的频道(高亮,不立即播放,等用户确认)。
  /// 这里直接播放,符合 NovaBox 行为。
  void browseAndPlayChannel(M3uChannel ch) {
    selectChannel(ch);
    onPanelActivity();
  }

  /// 切换线路(源)。
  void browseAndPlayStream(int idx) {
    selectStream(idx);
    onPanelActivity();
  }

  void _resetHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 5), () {
      showPanel.value = false;
    });
  }

  @override
  void onClose() {
    _hideTimer?.cancel();
    // 退出播放页即停止直播拉流，但把频道信息存进全局播放状态，供顶部播放
    // 入口展示，并在用户点击时重新连接回同一频道（直播无法续播进度）。
    if (channelName.value.isNotEmpty) {
      PlaybackBarController.instance.saveIptvSnapshot(
        channelName: channelName.value,
        groupName: playingGroup.value,
        url: streamUrls.isNotEmpty ? streamUrls[streamIndex.value] : '',
        sourceIndex: sourceIndex.value,
      );
    }
    disposePlayer();
    super.onClose();
  }
}

class TvIptvPlayerPage extends StatefulWidget {
  const TvIptvPlayerPage({super.key});
  @override
  State<TvIptvPlayerPage> createState() => _TvIptvPlayerPageState();
}

class _TvIptvPlayerPageState extends State<TvIptvPlayerPage> {
  late final TvIptvPlayerController ctrl;
  late final FocusNode _rootFocus;

  @override
  void initState() {
    super.initState();
    ctrl = Get.put(TvIptvPlayerController());
    _rootFocus = FocusNode();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    _rootFocus.dispose();
    Get.delete<TvIptvPlayerController>();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        focusNode: _rootFocus,
        autofocus: true,
        onKeyEvent: _onRootKey,
        child: Stack(
          children: [
            // 视频画面 — 通过 backend 统一构建（MPV/ExoPlayer 均适用）
            ctrl.backend.buildView(
              key: ctrl.playerKey,
              fill: Colors.black,
            ),
            // 加载中
            Obx(() => ctrl.isLoading.value
                ? const Center(
                    child: CircularProgressIndicator(color: Colors.white))
                : const SizedBox()),
            // 缓冲中
            Obx(() => ctrl.isBuffering.value && !ctrl.isLoading.value
                ? const Center(
                    child: CircularProgressIndicator(color: Colors.white))
                : const SizedBox()),
            // 顶部信息栏(频道名 + LIVE)
            _buildTopBar(),
            // 底部提示
            _buildBottomHint(),
            // 左侧三列弹窗(确定键唤出)
            Obx(() => ctrl.showPanel.value
                ? _buildChannelPanel(context)
                : const SizedBox()),
          ],
        ),
      ),
    );
  }

  /// 根级按键处理:
  /// - 弹窗显示时:返回键关闭弹窗(不退出页面),任意键重置 5 秒计时器。
  /// - 弹窗隐藏时:确定键唤出弹窗,返回键退出页面。
  KeyEventResult _onRootKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final isBack = key == LogicalKeyboardKey.goBack ||
        key == LogicalKeyboardKey.escape;
    final isOk = key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.space;

    if (ctrl.showPanel.value) {
      // 弹窗显示中
      if (isBack) {
        ctrl.hideChannelPanel();
        return KeyEventResult.handled;
      }
      // 其它任意键(方向键等)交给弹窗内的 Focus 处理,但重置计时器
      ctrl.onPanelActivity();
      return KeyEventResult.ignored;
    }

    // 弹窗未显示
    if (isOk) {
      ctrl.showChannelPanel();
      return KeyEventResult.handled;
    }
    if (isBack) {
      Get.back();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _buildTopBar() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black87, Colors.transparent],
          ),
        ),
        padding: EdgeInsets.fromLTRB(48.w, 32.w, 48.w, 32.w),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 6.w),
              decoration: BoxDecoration(
                color: TvColors.liveRed,
                borderRadius: TvStyle.radius8,
              ),
              child: Text('LIVE',
                  style: TvStyle.bodyMedium
                      .copyWith(fontWeight: FontWeight.bold)),
            ),
            SizedBox(width: 16.w),
            Expanded(
              child: Obx(() => Text(
                    ctrl.channelName.value.isEmpty
                        ? '正在加载...'
                        : ctrl.channelName.value,
                    style: TvStyle.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  )),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomHint() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [Colors.black87, Colors.transparent],
          ),
        ),
        padding: EdgeInsets.fromLTRB(48.w, 24.w, 48.w, 32.w),
        child: Obx(() => Text(
              ctrl.showPanel.value
                  ? '方向键切换  OK 确认  返回键关闭面板  (5秒无操作自动关闭)'
                  : 'OK 唤出频道列表  返回键退出',
              style: TvStyle.labelSmall,
              textAlign: TextAlign.center,
            )),
      ),
    );
  }

  /// 左侧三列弹窗:分组 | 频道 | 线路。
  /// 半透明黑底,占屏幕左侧约 60% 宽度,垂直居中。
  Widget _buildChannelPanel(BuildContext context) {
    return Positioned.fill(
      child: GestureDetector(
        // 点击空白处不关闭(只能用返回键或 5 秒超时),避免误触
        behavior: HitTestBehavior.translucent,
        onTap: () {},
        child: Align(
          alignment: Alignment.centerLeft,
          child: Container(
            margin: EdgeInsets.only(left: 48.w),
            width: 1000.w,
            height: 760.w,
            decoration: BoxDecoration(
              color: TvColors.surface.withAlpha(230),
              borderRadius: TvStyle.radius12,
              border: Border.all(color: TvColors.primary, width: 2.w),
            ),
            child: Row(
              children: [
                // 第一列:分组
                _buildGroupColumn(),
                VerticalDivider(width: 1, color: TvColors.divider),
                // 第二列:频道
                _buildChannelColumn(),
                VerticalDivider(width: 1, color: TvColors.divider),
                // 第三列:线路
                _buildStreamColumn(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGroupColumn() {
    return SizedBox(
      width: 280.w,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _panelHeader('分组'),
          Expanded(
            child: Obx(() {
              final grps = ctrl.groups;
              if (grps.isEmpty) {
                return Center(
                    child: Text('无分组', style: TvStyle.labelSmall));
              }
              return ListView.builder(
                padding: EdgeInsets.symmetric(vertical: 4.w),
                itemCount: grps.length,
                itemBuilder: (_, i) {
                  final g = grps[i];
                  final fn = TvFocusNode();
                  return _PanelItem(
                    focusNode: fn,
                    autofocus: i == 0,
                    text: g,
                    highlighted: ctrl.browseGroup.value == g,
                    onTap: () => ctrl.browseToGroup(g),
                  );
                },
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildChannelColumn() {
    return SizedBox(
      width: 380.w,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _panelHeader('频道'),
          Expanded(
            child: Obx(() {
              final chs = ctrl.browsedChannels;
              if (chs.isEmpty) {
                return Center(
                    child: Text('无频道', style: TvStyle.labelSmall));
              }
              final firstCh = ctrl.channelName.value;
              return ListView.builder(
                padding: EdgeInsets.symmetric(vertical: 4.w),
                itemCount: chs.length,
                itemBuilder: (_, i) {
                  final ch = chs[i];
                  final fn = TvFocusNode();
                  return _PanelItem(
                    focusNode: fn,
                    autofocus: i == 0,
                    text: ch.name,
                    highlighted: ch.name == firstCh,
                    onTap: () => ctrl.browseAndPlayChannel(ch),
                  );
                },
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildStreamColumn() {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _panelHeader('线路'),
          Expanded(
            child: Obx(() {
              final urls = ctrl.streamUrls;
              if (urls.isEmpty) {
                return Center(
                    child: Text('无线路', style: TvStyle.labelSmall));
              }
              return ListView.builder(
                padding: EdgeInsets.symmetric(vertical: 4.w),
                itemCount: urls.length,
                itemBuilder: (_, i) {
                  final fn = TvFocusNode();
                  return _PanelItem(
                    focusNode: fn,
                    autofocus: i == 0,
                    text: '线路 ${i + 1}',
                    highlighted: ctrl.streamIndex.value == i,
                    onTap: () => ctrl.browseAndPlayStream(i),
                  );
                },
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _panelHeader(String title) {
    return Container(
      height: 72.w,
      padding: EdgeInsets.symmetric(horizontal: 24.w),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        border: Border(
            bottom: BorderSide(color: TvColors.divider, width: 1)),
      ),
      child: Text(title, style: TvStyle.titleMedium),
    );
  }
}

/// 弹窗内列表项 — 用 TvHighlight 包裹,确保遥控器可聚焦。
class _PanelItem extends StatefulWidget {
  final TvFocusNode focusNode;
  final String text;
  final bool highlighted;
  final bool autofocus;
  final VoidCallback onTap;

  const _PanelItem({
    required this.focusNode,
    required this.text,
    required this.onTap,
    this.highlighted = false,
    this.autofocus = false,
  });

  @override
  State<_PanelItem> createState() => _PanelItemState();
}

class _PanelItemState extends State<_PanelItem> {
  @override
  void dispose() {
    widget.focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TvHighlight(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      onTap: widget.onTap,
      borderRadius: TvStyle.radius8,
      color: widget.highlighted
          ? TvColors.primary.withAlpha(40)
          : Colors.transparent,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 14.w),
        child: Row(
          children: [
            if (widget.highlighted) ...[
              Icon(Icons.play_arrow,
                  color: TvColors.primary, size: 24.w),
              SizedBox(width: 8.w),
            ],
            Expanded(
              child: Text(
                widget.text,
                style: TvStyle.bodyMedium.copyWith(
                  color: widget.highlighted
                      ? TvColors.primary
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
