import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:player_shared/player_shared.dart';

import 'package:nexus/app/controller/app_settings_controller.dart';
import 'package:nexus/player/exo_backend.dart';
import 'package:nexus/modules/music/player/music_player_page.dart'
    show MusicPlayerController;

/// IPTV 直播播放控制器,完全照抄 NovaBox 的 `LivePlayActivity` 逻辑
/// (基于 Windows 端 `IptvPlayerController` 的源加载/M3U 解析逻辑)。
///
/// - 加载 M3U 源 → 按分组组织频道 → 三列浏览(分组|频道|线路)
/// - 同名频道合并为多线路(源1/源2/…)
/// - 切换频道 / 切换线路 / 全屏 / 画面比例 / 解码方式
class IptvPlayerController extends GetxController
    with PlayerMixin, PlayerStateMixin {
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

  // ── 源(播放列表)数据 ─────────────────────────────────
  final sources = <Map<String, String>>[].obs;
  final sourceIndex = 0.obs;

  // ── 播放器状态 ────────────────────────────────────────
  final isBuffering = false.obs;
  final isPlaying = false.obs;
  final isLoading = false.obs;

  // ── 设置 ──────────────────────────────────────────────
  /// 画面比例: 0=默认 1=16:9 2=4:3 3=填充 4=原始 5=裁剪
  final RxInt aspectRatioMode = 0.obs;
  /// 解码方式已迁移到全局设置（播放器后端 + MPV 硬/软解），此处保留 mode 0
  /// 仅用于在 IPTV 设置弹窗里展示当前解码方式（读全局 settings）。
  // (移除了独立的 decodeMode 状态)

  // ── 入参 ──────────────────────────────────────────────
  late final String initialUrl;
  late final String initialChannelName;
  late final String initialGroupName;
  late final int initialSourceIdx;

  final groupScrollCtrl = ScrollController();
  final channelScrollCtrl = ScrollController();
  final streamScrollCtrl = ScrollController();

  List<String> get groups => grouped.keys.toList();

  /// 当前浏览分组下的频道(按名称去重,保留首个)。
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
    if (Get.isRegistered<MusicPlayerController>()) {
      MusicPlayerController.instance.stopForOtherMedia();
    }
    PlaybackBarController.instance.clear();

    final args = Get.arguments as Map<String, dynamic>? ?? {};
    initialUrl = args['url'] as String? ?? '';
    initialChannelName = args['channelName'] as String? ?? '';
    initialGroupName = args['groupName'] as String? ?? '';
    initialSourceIdx = args['sourceIndex'] as int? ?? 0;

    channelName.value = initialChannelName;
    playingGroup.value = initialGroupName;

    final settings = AppSettingsController.instance;
    sources.assignAll(settings.iptvSources);

    // IPTV 直播场景：auto 模式下默认走 MPV（mpv 对 HLS/TS 流兼容性更好）
    final useExo = settings.shouldUseExo(isIptv: true);
    final b = buildBackend(
      useExo: useExo,
      hardwareDecode: settings.hardwareDecode.value,
      compatMode: settings.compatMode.value,
      profile: settings.mpvProfile.value,
      exoFactory: () => ExoBackend(),
    );

    // 注意：backend 字段是 late，在 initPlayer 内部才会赋值，
    // 所以这里用局部变量 b 来订阅流，避免 LateInitializationError。
    b.buffering.listen((v) => isBuffering.value = v);
    b.playing.listen((v) => isPlaying.value = v);

    initPlayer(backend: b).then((_) async {
      final mpv = mpvBackend;
      if (mpv != null) {
        await applyMpvOptions(mpv.player, settings.mpvProfile.value);
      }
      autoHideControls();
      if (sources.isNotEmpty) {
        await loadSource(initialSourceIdx.clamp(0, sources.length - 1));
      }
    });
  }

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

        String targetGroup = grps.first;
        M3uChannel? targetCh;

        if (initialGroupName.isNotEmpty && grps.contains(initialGroupName)) {
          targetGroup = initialGroupName;
        }
        if (initialChannelName.isNotEmpty) {
          for (final c in (grouped[targetGroup] ?? [])) {
            if (c.name == initialChannelName) {
              targetCh = c;
              break;
            }
          }
        }
        if (targetCh == null) {
          targetCh = (grouped[targetGroup] ?? []).isNotEmpty
              ? (grouped[targetGroup] ?? []).first
              : null;
        }

        browseGroup.value = targetGroup;
        playingGroup.value = targetGroup;

        if (targetCh != null) {
          _selectChannelInternal(targetCh, autoPlay: initialUrl.isEmpty);
        } else if (initialUrl.isNotEmpty) {
          streamUrls.value = [initialUrl];
          streamIndex.value = 0;
          backend.open(initialUrl);
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
      _selectChannelInternal(ch, autoPlay: true);

  void _selectChannelInternal(M3uChannel ch, {required bool autoPlay}) {
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
    autoHideControls();
  }

  void togglePlay() => backend.playOrPause();

  // ── 全屏 ──────────────────────────────────────────────

  void enterFullScreen() {
    if (isFullScreen.value) return;
    isFullScreen.value = true;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations(_resolveFullScreenOrientations());
    autoHideControls(seconds: 3);
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
    showControls.value = true;
  }

  /// 根据全屏播放方向设置计算应锁定的屏幕方向列表。
  /// IPTV 直播内容几乎都是横屏，auto 模式默认旋转到横屏。
  List<DeviceOrientation> _resolveFullScreenOrientations() {
    final mode = AppSettingsController.instance.fullScreenOrientation.value;
    switch (mode) {
      case FullScreenOrientationMode.portrait:
        return [DeviceOrientation.portraitUp];
      case FullScreenOrientationMode.landscape:
        return [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight];
      case FullScreenOrientationMode.sensor:
        return [
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ];
      case FullScreenOrientationMode.auto:
      default:
        // IPTV 直播几乎全是横屏内容，auto 模式下默认横屏
        final size = backend.videoNativeSize;
        if (size != Size.zero && size.height > size.width) {
          // 罕见的竖屏 IPTV 源：保持竖屏
          return [DeviceOrientation.portraitUp];
        }
        return [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight];
    }
  }

  void toggleFullScreen() {
    if (isFullScreen.value) {
      exitFullScreen();
    } else {
      enterFullScreen();
    }
  }

  // ── 画面比例 ──────────────────────────────────────────

  static const aspectRatioLabels = ['默认', '16:9', '4:3', '填充', '原始', '裁剪'];

  void setAspectRatio(int mode) {
    aspectRatioMode.value = mode;
    // 通过 backend 抽象统一调用：MPV 后端走 video-aspect-override，
    // ExoPlayer 后端是 no-op（由 buildView 的 fit 决定）。
    backend.setAspectRatio(mode);
  }

  // ── 解码方式（已迁移到全局设置） ──────────────────────

  /// 解码方式选项：根据当前后端返回不同标签。
  /// 仅用于在 IPTV 设置弹窗中展示提示，真正切换请到"设置 → 播放"页。
  static List<String> decodeLabelsFor(bool isMpv) {
    if (isMpv) {
      return ['硬件解码', '软件解码'];
    }
    return ['硬件解码（ExoPlayer 默认）'];
  }

  /// 跳转到全局设置页（提示用户去设置里切换）。
  void setDecodeMode(int mode) {
    SmartDialog.showToast('请到「设置 → 播放」中切换解码方式');
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
    // 退出播放页即停止直播拉流，但把频道信息存进全局迷你播放栏，
    // 以便用户在首页点击播放栏时重新连接回同一频道（直播无法续播进度）。
    if (channelName.value.isNotEmpty) {
      PlaybackBarController.instance.saveIptvSnapshot(
        channelName: channelName.value,
        groupName: playingGroup.value,
        url: streamUrls.isNotEmpty ? streamUrls[streamIndex.value] : '',
        sourceIndex: sourceIndex.value,
      );
    }
    groupScrollCtrl.dispose();
    channelScrollCtrl.dispose();
    streamScrollCtrl.dispose();
    disposePlayer();
    super.onClose();
  }
}

/// IPTV 直播播放页,完全照抄 NovaBox 的 `LivePlayActivity` 布局。
///
/// - 手机端: 垂直布局 — 16:9 播放器在上,信息栏 + 三列(分组|频道|线路)在下
/// - 平板端: 水平分屏 — 播放器在左(flex 72),信息栏 + 三列在右(flex 28)
/// - 全屏: 仅播放器,沉浸式 + 横屏
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
  Widget build(BuildContext context) {
    return Scaffold(
      // 非全屏时，播放器之外的信息栏/三列频道列表应跟随 App 的主题模式
      // 和主题色；全屏时播放器铺满整个 Scaffold，颜色不影响观感。
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: Obx(() {
        if (ctrl.isFullScreen.value) {
          return _buildFullScreen(context);
        }
        final isWide = MediaQuery.sizeOf(context).width >= 600;
        if (isWide) {
          return _buildTabletLayout(context);
        }
        return _buildPhoneLayout(context);
      }),
    );
  }

  // ── 手机布局: 垂直 — 16:9 播放器 + 信息栏 + 三列 ──────

  Widget _buildPhoneLayout(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final playerHeight = width * 9 / 16;
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          SizedBox(
            width: width,
            height: playerHeight,
            child: _buildPlayerArea(context),
          ),
          _buildInfoBar(context),
          Divider(
              height: 1,
              color:
                  Theme.of(context).colorScheme.outlineVariant.withAlpha(120)),
          Expanded(child: _buildChannelArea(context)),
        ],
      ),
    );
  }

  // ── 平板布局: 水平分屏 — 播放器左 + 信息栏+三列右 ────

  Widget _buildTabletLayout(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      bottom: false,
      child: Row(
        children: [
          Expanded(flex: 72, child: _buildPlayerArea(context)),
          Container(width: 1, color: scheme.outlineVariant.withAlpha(120)),
          Expanded(
            flex: 28,
            child: Column(
              children: [
                _buildInfoBar(context),
                Divider(height: 1, color: scheme.outlineVariant.withAlpha(120)),
                Expanded(child: _buildChannelArea(context)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── 全屏 ──────────────────────────────────────────────

  Widget _buildFullScreen(BuildContext context) {
    return Stack(
      children: [
        _buildPlayerArea(context, isFullScreen: true),
        _buildFullScreenTopBar(context),
      ],
    );
  }

  // ── 播放器区域 ────────────────────────────────────────

  Widget _buildPlayerArea(BuildContext context, {bool isFullScreen = false}) {
    return Stack(
      children: [
        // 视频画面 — 通过 backend 统一构建（MPV/ExoPlayer 均适用）
        ctrl.backend.buildView(
          key: ctrl.playerKey,
          fill: Colors.black,
        ),
        // 加载圈
        Obx(() => (ctrl.isBuffering.value || ctrl.isLoading.value)
            ? const Center(
                child: CircularProgressIndicator(color: Colors.white))
            : const SizedBox()),
        // 控制浮层
        _buildPlayerControls(context, isFullScreen: isFullScreen),
        // 右上角频道名(加载时)
        Obx(() => Positioned(
              top: 8,
              right: 12,
              child: (ctrl.isBuffering.value || ctrl.isLoading.value) &&
                      ctrl.channelName.value.isNotEmpty
                  ? Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        ctrl.channelName.value,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 12),
                      ),
                    )
                  : const SizedBox(),
            )),
      ],
    );
  }

  /// [isFullScreen] 为真时，顶部栏改由 [_buildFullScreenTopBar] 提供
  /// （已含 SafeArea 避让），此方法内部不再重复渲染顶部栏，只保留中间
  /// 播放/暂停按钮和底部的上一/下一频道栏。
  Widget _buildPlayerControls(BuildContext context,
      {bool isFullScreen = false}) {
    return Obx(() => ctrl.showControls.value
        ? Positioned.fill(
            child: GestureDetector(
              onTap: ctrl.toggleControls,
              child: Container(
                color: Colors.transparent,
                child: Stack(
                  children: [
                    // 顶部栏: 返回 + 频道名 + 设置 + 全屏
                    // 全屏时顶部栏改由 _buildFullScreenTopBar 提供（自带
                    // SafeArea 避让），这里不重复渲染；非全屏时外层布局
                    // 已用 SafeArea 整体让出状态栏高度，直接贴边即可。
                    if (!isFullScreen)
                      Positioned(
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
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 4),
                            child: Row(
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.arrow_back,
                                      color: Colors.white),
                                  onPressed: () {
                                    if (ctrl.isFullScreen.value) {
                                      ctrl.exitFullScreen();
                                    } else {
                                      Get.back();
                                    }
                                  },
                                ),
                                Expanded(
                                  child: Obx(() => Text(
                                        ctrl.channelName.value.isEmpty
                                            ? '请选择频道'
                                            : ctrl.channelName.value,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 15,
                                            fontWeight: FontWeight.w600),
                                      )),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.tune,
                                      color: Colors.white),
                                  tooltip: '播放设置',
                                  onPressed: () =>
                                      _showSettingsDialog(context),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.fullscreen,
                                      color: Colors.white),
                                  tooltip: '全屏',
                                  onPressed: ctrl.toggleFullScreen,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    // 中心播放/暂停
                    Center(
                      child: Obx(() => IconButton(
                            iconSize: 56,
                            icon: Icon(
                              ctrl.isPlaying.value
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                              color: Colors.white.withAlpha(220),
                            ),
                            onPressed: ctrl.togglePlay,
                          )),
                    ),
                    // 底部栏: 上一个频道 / 下一个频道
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 4),
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [Colors.black87, Colors.transparent],
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            TextButton.icon(
                              icon: const Icon(Icons.skip_previous,
                                  color: Colors.white),
                              label: const Text('上一频道',
                                  style:
                                      TextStyle(color: Colors.white)),
                              onPressed: _prevChannel,
                            ),
                            const SizedBox(width: 24),
                            TextButton.icon(
                              icon: const Text('下一频道',
                                  style:
                                      TextStyle(color: Colors.white)),
                              label: const Icon(Icons.skip_next,
                                  color: Colors.white),
                              onPressed: _nextChannel,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          )
        : Positioned.fill(
            child: GestureDetector(
              onTap: ctrl.toggleControls,
              child: Container(color: Colors.transparent),
            ),
          ));
  }

  Widget _buildFullScreenTopBar(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Obx(() => ctrl.showControls.value
          ? Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black87, Colors.transparent],
                ),
              ),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: ctrl.exitFullScreen,
                  ),
                  Expanded(
                    child: Obx(() => Text(
                          ctrl.channelName.value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600),
                        )),
                  ),
                  IconButton(
                    icon: const Icon(Icons.tune, color: Colors.white),
                    onPressed: () => _showSettingsDialog(context),
                  ),
                  IconButton(
                    icon: const Icon(Icons.fullscreen_exit,
                        color: Colors.white),
                    onPressed: ctrl.exitFullScreen,
                  ),
                ],
                  ),
                ),
              ),
            )
          : const SizedBox()),
    );
  }

  // ── 信息栏 ────────────────────────────────────────────

  Widget _buildInfoBar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 48,
      color: scheme.surface,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Icon(Icons.live_tv, color: scheme.onSurfaceVariant, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Obx(() => Text(
                  ctrl.channelName.value.isEmpty
                      ? '请选择频道'
                      : ctrl.channelName.value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: scheme.onSurface,
                      fontSize: 14,
                      fontWeight: FontWeight.w600),
                )),
          ),
          Obx(() => ctrl.streamUrls.length > 1
              ? Text('源${ctrl.streamIndex.value + 1}/${ctrl.streamUrls.length}',
                  style: TextStyle(
                      color: scheme.onSurfaceVariant, fontSize: 12))
              : const SizedBox()),
          IconButton(
            icon: Icon(Icons.tune, color: scheme.onSurfaceVariant, size: 20),
            tooltip: '播放设置',
            onPressed: () => _showSettingsDialog(context),
          ),
        ],
      ),
    );
  }

  // ── 三列频道区: 分组 | 频道 | 线路 ─────────────────────

  Widget _buildChannelArea(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Obx(() {
      if (ctrl.isLoading.value && ctrl.allChannels.isEmpty) {
        return Center(
            child: CircularProgressIndicator(color: scheme.primary));
      }
      if (ctrl.allChannels.isEmpty) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.live_tv_outlined,
                  size: 64, color: scheme.onSurfaceVariant),
              const SizedBox(height: 12),
              Text('未加载到频道',
                  style: TextStyle(color: scheme.onSurfaceVariant)),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Get.back(),
                child: const Text('返回源管理'),
              ),
            ],
          ),
        );
      }
      return Row(
        children: [
          // 分组列
          Expanded(
            flex: 1,
            child: _buildGroupColumn(context),
          ),
          Container(width: 1, color: scheme.outlineVariant.withAlpha(120)),
          // 频道列
          Expanded(
            flex: 2,
            child: _buildChannelColumn(context),
          ),
          Container(width: 1, color: scheme.outlineVariant.withAlpha(120)),
          // 线路列
          Expanded(
            flex: 1,
            child: _buildStreamColumn(context),
          ),
        ],
      );
    });
  }

  Widget _buildGroupColumn(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          color: scheme.surfaceContainerHighest.withAlpha(120),
          child: Text('分组',
              style: TextStyle(
                  color: scheme.onSurface,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
        ),
        Expanded(
          child: Obx(() => ListView.builder(
                controller: ctrl.groupScrollCtrl,
                itemCount: ctrl.groups.length,
                itemBuilder: (_, i) {
                  final g = ctrl.groups[i];
                  final selected = ctrl.browseGroup.value == g;
                  return Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => ctrl.browseGroup.value = g,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 10),
                        color: selected
                            ? scheme.primary.withAlpha(60)
                            : Colors.transparent,
                        child: Text(g,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: selected
                                  ? scheme.onSurface
                                  : scheme.onSurfaceVariant,
                              fontSize: 13,
                              fontWeight: selected
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            )),
                      ),
                    ),
                  );
                },
              )),
        ),
      ],
    );
  }

  Widget _buildChannelColumn(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          color: scheme.surfaceContainerHighest.withAlpha(120),
          child: Text('频道',
              style: TextStyle(
                  color: scheme.onSurface,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
        ),
        Expanded(
          child: Obx(() {
            final list = ctrl.browsedChannels;
            if (list.isEmpty) {
              return Center(
                child: Text('请选择分组',
                    style:
                        TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
              );
            }
            return ListView.builder(
              controller: ctrl.channelScrollCtrl,
              itemCount: list.length,
              itemBuilder: (_, i) {
                final ch = list[i];
                final selected = ctrl.channelName.value == ch.name;
                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => ctrl.selectChannel(ch),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 10),
                      color: selected
                          ? scheme.primary.withAlpha(80)
                          : Colors.transparent,
                      child: Row(
                        children: [
                          if (ch.logo.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: Image.network(
                                ch.logo,
                                width: 24,
                                height: 24,
                                fit: BoxFit.contain,
                                errorBuilder: (_, __, ___) => Icon(
                                    Icons.live_tv,
                                    color: scheme.onSurfaceVariant,
                                    size: 18),
                              ),
                            )
                          else
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: Icon(Icons.live_tv,
                                  color: scheme.onSurfaceVariant, size: 18),
                            ),
                          Expanded(
                            child: Text(ch.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: selected
                                      ? scheme.onSurface
                                      : scheme.onSurfaceVariant,
                                  fontSize: 13,
                                  fontWeight: selected
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                )),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          }),
        ),
      ],
    );
  }

  Widget _buildStreamColumn(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          color: scheme.surfaceContainerHighest.withAlpha(120),
          child: Text('线路',
              style: TextStyle(
                  color: scheme.onSurface,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
        ),
        Expanded(
          child: Obx(() {
            final urls = ctrl.streamUrls;
            if (urls.isEmpty) {
              return Center(
                child: Text('无线路',
                    style:
                        TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
              );
            }
            return ListView.builder(
              controller: ctrl.streamScrollCtrl,
              itemCount: urls.length,
              itemBuilder: (_, i) {
                final selected = ctrl.streamIndex.value == i;
                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => ctrl.selectStream(i),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 10),
                      color: selected
                          ? scheme.primary.withAlpha(60)
                          : Colors.transparent,
                      child: Text('源${i + 1}',
                          style: TextStyle(
                            color: selected
                                ? scheme.onSurface
                                : scheme.onSurfaceVariant,
                            fontSize: 13,
                            fontWeight: selected
                                ? FontWeight.w600
                                : FontWeight.normal,
                          )),
                    ),
                  ),
                );
              },
            );
          }),
        ),
      ],
    );
  }

  // ── 设置弹窗 ──────────────────────────────────────────

  void _showSettingsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        final scheme = Theme.of(dialogContext).colorScheme;
        return AlertDialog(
          title: const Text('播放设置'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('画面比例',
                  style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
              const SizedBox(height: 8),
              Obx(() => Wrap(
                    spacing: 6,
                    children: List.generate(
                        IptvPlayerController.aspectRatioLabels.length, (i) {
                      final selected = ctrl.aspectRatioMode.value == i;
                      return ChoiceChip(
                        label: Text(IptvPlayerController.aspectRatioLabels[i],
                            style: TextStyle(
                                fontSize: 12,
                                color: selected
                                    ? scheme.onSecondaryContainer
                                    : scheme.onSurfaceVariant)),
                        selected: selected,
                        onSelected: (_) => ctrl.setAspectRatio(i),
                        visualDensity: VisualDensity.compact,
                      );
                    }),
                  )),
              const SizedBox(height: 16),
              Text('解码方式',
                  style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
              const SizedBox(height: 8),
              Obx(() {
                // 解码方式已迁移到全局设置；这里仅展示当前后端类型 + 跳转提示
                final backendName =
                    ctrl.isMpv ? 'MPV (libmpv)' : 'ExoPlayer';
                final hw = AppSettingsController
                    .instance.hardwareDecode.value;
                final decodeText = ctrl.isMpv
                    ? (hw ? '硬件解码' : '软件解码')
                    : '硬件解码（ExoPlayer 默认）';
                return Wrap(
                  spacing: 6,
                  children: [
                    ChoiceChip(
                      label: Text('当前: $backendName · $decodeText',
                          style: TextStyle(
                              fontSize: 12, color: scheme.onSecondaryContainer)),
                      selected: true,
                      onSelected: (_) => ctrl.setDecodeMode(0),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                );
              }),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('关闭'),
            ),
          ],
        );
      },
    );
  }

  // ── 频道导航 ──────────────────────────────────────────

  void _prevChannel() {
    final list = ctrl.browsedChannels;
    if (list.isEmpty) return;
    final idx = list.indexWhere((c) => c.name == ctrl.channelName.value);
    if (idx <= 0) return;
    ctrl.selectChannel(list[idx - 1]);
  }

  void _nextChannel() {
    final list = ctrl.browsedChannels;
    if (list.isEmpty) return;
    final idx = list.indexWhere((c) => c.name == ctrl.channelName.value);
    if (idx < 0 || idx >= list.length - 1) return;
    ctrl.selectChannel(list[idx + 1]);
  }
}
