import 'dart:io';

import 'package:fc_native_video_thumbnail/fc_native_video_thumbnail.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;
import 'package:player_shared/player_shared.dart' hide AppDataDir;

import 'package:nexus/app/controller/app_settings_controller.dart';
import 'package:nexus/app/data_dir.dart';
import 'package:nexus/app/routes.dart';

// ── Controller ───────────────────────────────────────────────────────────────

enum SortMode { name, size, ext }

class VideoLibraryController extends GetxController {
  // All files per path
  final _filesByPath = <String, List<VideoFile>>{}.obs;

  // 视频文件绝对路径 → 缩略图文件绝对路径。为空字符串表示"已尝试生成但失败"，
  // 不存在这个 key 表示"还没处理过"。用一个独立的 RxMap 管理，这样某张缩略图
  // 生成完成时只需要刷新引用了它的那一张卡片，不需要重建整个网格。
  final thumbnails = <String, String>{}.obs;

  final isScanning   = false.obs;
  final search       = ''.obs;
  final sortMode     = SortMode.name.obs;
  final selectedPath = ''.obs; // '' = 全部

  // 缩略图生成队列：限制同时最多 2 个视频在后台截图，避免一次性打开大量
  // 解码器实例占用过多 CPU/GPU/内存。
  final List<VideoFile> _thumbQueue = [];
  int _thumbRunning = 0;
  static const int _thumbMaxConcurrent = 2;

  List<VideoFile> get _allFiles =>
      _filesByPath.values.expand((l) => l).toList();

  List<VideoFile> get _sourceFiles {
    if (selectedPath.value.isEmpty) return _allFiles;
    return _filesByPath[selectedPath.value] ?? [];
  }

  List<VideoFile> get filtered {
    var list = _sourceFiles;
    final q = search.value.toLowerCase();
    if (q.isNotEmpty) {
      list = list.where((f) => f.name.toLowerCase().contains(q)).toList();
    }
    list = List.of(list);
    switch (sortMode.value) {
      case SortMode.name:
        list.sort((a, b) => a.name.compareTo(b.name));
        break;
      case SortMode.size:
        list.sort((a, b) => b.size.compareTo(a.size));
        break;
      case SortMode.ext:
        list.sort((a, b) =>
            p.extension(a.name).compareTo(p.extension(b.name)));
        break;
    }
    return list;
  }

  int get totalCount => _allFiles.length;

  @override
  void onInit() {
    super.onInit();
    _loadSortMode();
    _loadThumbCache();
    _scanAll();
  }

  // ── 排序持久化 ─────────────────────────────────────────────────────────────

  void _loadSortMode() {
    final saved = StorageService.getValue<String>(
        StorageService.kVideoSortMode, SortMode.name.name);
    sortMode.value = SortMode.values.firstWhere(
      (m) => m.name == saved,
      orElse: () => SortMode.name,
    );
  }

  Future<void> setSortMode(SortMode mode) async {
    sortMode.value = mode;
    await StorageService.setValue(StorageService.kVideoSortMode, mode.name);
  }

  // ── 缩略图缓存持久化 ─────────────────────────────────────────────────────────

  void _loadThumbCache() {
    final raw = StorageService.getValue<Map>(
        StorageService.kVideoThumbCache, <String, dynamic>{});
    thumbnails.value = raw.map(
      (k, v) => MapEntry(k as String, (v as String?) ?? ''),
    );
  }

  Future<void> _saveThumbCache() async {
    await StorageService.setValue(
        StorageService.kVideoThumbCache, Map<String, dynamic>.from(thumbnails));
  }

  /// 把还没有缩略图记录、或记录已失效（如旧版本存的绝对路径在程序目录迁移
  /// 后指向不存在的文件）的视频加入后台生成队列。由扫描完成后调用，不阻塞
  /// 列表本身的展示。
  void _enqueueMissingThumbnails(List<VideoFile> files) {
    for (final f in files) {
      final cached = thumbnails[f.path];
      if (cached != null) {
        // 空字符串代表"已尝试生成但失败"，不重试，避免反复对坏文件截图；
        // 非空则需要确认对应缩略图文件当下确实存在，否则视为记录失效。
        if (cached.isEmpty) continue;
        final absPath = AppDataDir.toAbsolute(cached);
        if (File(absPath).existsSync()) continue;
        // 记录失效：从缓存里摘掉，走下面的正常入队重新生成流程。
        thumbnails.remove(f.path);
      }
      if (_thumbQueue.any((q) => q.path == f.path)) continue; // 已在队列里
      _thumbQueue.add(f);
    }
    _pumpThumbQueue();
  }

  void _pumpThumbQueue() {
    while (_thumbRunning < _thumbMaxConcurrent && _thumbQueue.isNotEmpty) {
      final next = _thumbQueue.removeAt(0);
      _thumbRunning++;
      _generateThumbnail(next).whenComplete(() {
        _thumbRunning--;
        _pumpThumbQueue();
      });
    }
  }

  /// 生成单个视频的缩略图。
  ///
  /// 优先走 `fc_native_video_thumbnail`（Windows 下底层是 Media Foundation
  /// 原生取帧），不需要真正打开一个播放器实例，比 media_kit 截图方案快得多、
  /// 资源占用也更低；仅在原生方案调用失败（如极少数损坏文件/罕见编码）时，
  /// 才回退到原来的 media_kit 打开视频 + seek 到 10% 位置 + screenshot()
  /// 方案兜底，保证兼容性不下降。
  ///
  /// 目录管理和"相对于 appdata 根目录"的路径存储逻辑保持不变，不受取帧方式
  /// 影响。
  Future<void> _generateThumbnail(VideoFile f) async {
    await AppDataDir.ensureCreated();
    final hash = _stableHash(f.path);
    final outFile = File(p.join(AppDataDir.thumbsDir.path, '$hash.jpg'));

    String result = await _generateWithFcNative(f.path, outFile);
    if (result.isEmpty) {
      result = await _generateWithMediaKit(f.path, outFile);
    }

    thumbnails[f.path] = result; // 空字符串代表"生成失败"，避免反复重试
    await _saveThumbCache();
  }

  /// 原生方案：Media Foundation 直接取帧，写入 [outFile]。
  ///
  /// 该插件在 Windows 下不支持非正方形缩略图，[height] 参数会被忽略，
  /// 实际固定按 [width] x [width] 输出（例如 width=160 就是 160x160）。
  /// 这里干脆把 width/height 都显式设成同一个值，避免代码看起来像是在
  /// 控制一个 16:9 尺寸、实际却被平台悄悄改成正方形，容易误导后来的人。
  ///
  /// 网格卡片用 BoxFit.cover 铺满显示（见 _VideoCard 的 Image.file），
  /// 正方形素材裁剪显示不受影响。
  ///
  /// 竖屏视频封面文件明显比横屏大: 原始视频分辨率的宽高比越极端(尤其是
  /// 竖屏 9:16 这种)，缩放到同样的正方形目标尺寸时,编码前保留的细节/
  /// 高频信息更多,JPEG 压缩后的文件体积也随之更大——这不是取帧方式的
  /// bug,是画面内容本身决定的,只能靠限制目标分辨率、控制 quality、
  /// 必要时对超限文件重新以更低质量生成来兜底,无法完全消除差异。
  static const int _thumbSize = 160; // 输出边长(像素)，取代之前误导性的 320x180
  static const int _thumbMaxBytes = 40 * 1024; // 单张缩略图体积上限，超过则降质重试
  static const int _thumbFallbackQuality = 60; // 降质重试时使用的 quality

  Future<String> _generateWithFcNative(String videoPath, File outFile) async {
    try {
      final plugin = FcNativeVideoThumbnail();
      var ok = await plugin.saveThumbnailToFile(
        srcFile: videoPath,
        destFile: outFile.path,
        width: _thumbSize,
        height: _thumbSize,
        quality: 90,
      );
      if (!ok) return '';
      if (!await outFile.exists()) return '';

      // 体积保险：极端宽高比(尤其竖屏)的视频压缩后仍可能明显偏大，
      // 超过阈值时用更低 quality 重新生成一次，不再继续加码重试，
      // 避免为了压体积无限重试拖慢后台生成队列。
      final size = await outFile.length();
      if (size > _thumbMaxBytes) {
        ok = await plugin.saveThumbnailToFile(
          srcFile: videoPath,
          destFile: outFile.path,
          width: _thumbSize,
          height: _thumbSize,
          quality: _thumbFallbackQuality,
        );
        if (!ok || !await outFile.exists()) return '';
      }

      return AppDataDir.toRelative(outFile.path);
    } catch (_) {
      return '';
    }
  }

  /// 兜底方案：media_kit 打开视频、seek 到约 10% 位置截图。兼容性最好，
  /// 但需要真正启动一个播放器实例，耗时明显高于原生方案，仅在原生方案
  /// 失败时使用。
  Future<String> _generateWithMediaKit(String videoPath, File outFile) async {
    Player? player;
    String result = '';
    try {
      player = Player();
      // screenshot() 依赖关联的渲染纹理来取当前帧，即使这里不需要把画面显示
      // 在任何可见的 Video widget 上，也要挂一个 VideoController，否则某些
      // 平台上截图可能拿不到画面。
      //
      // 必须显式限制解码分辨率，否则 media_kit 会按视频源原始分辨率解码
      // 渲染，screenshot() 拿到的就是跟原视频同分辨率(如 1080p/4K)的
      // JPEG。这里跟原生方案(_generateWithFcNative)保持同样的 _thumbSize，
      // 避免同一批缩略图因为走了不同的生成路径(原生失败回退到这里)而
      // 出现尺寸/体积不一致的情况。
      VideoController(
        player,
        configuration: const VideoControllerConfiguration(
          width: _thumbSize,
          height: _thumbSize,
        ),
      );

      await player.open(Media(videoPath), play: false);

      // 等待时长信息可用，再跳转到大约 10% 位置截图（避免片头黑屏/片头 logo）。
      Duration duration = player.state.duration;
      if (duration == Duration.zero) {
        duration = await player.stream.duration
            .firstWhere((d) => d > Duration.zero)
            .timeout(const Duration(seconds: 5), onTimeout: () => Duration.zero);
      }
      final seekTo = duration > Duration.zero
          ? Duration(milliseconds: (duration.inMilliseconds * 0.1).round())
          : Duration.zero;
      if (seekTo > Duration.zero) {
        await player.seek(seekTo);
        // 给解码器一点时间把新位置的帧渲染出来
        await Future.delayed(const Duration(milliseconds: 300));
      }

      final bytes = await player.screenshot(format: 'image/jpeg');
      if (bytes != null && bytes.isNotEmpty) {
        await outFile.writeAsBytes(bytes, flush: true);
        // 存相对于 appdata 根目录的相对路径（而非绝对路径），这样整个程序
        // 文件夹（exe + appdata）被一起移动到别的磁盘/目录后，缓存依然有效，
        // 不需要用户重新扫描、也不会因为 containsKey 命中旧记录而卡住不重新
        // 生成（参见 _enqueueMissingThumbnails 的说明）。
        result = AppDataDir.toRelative(outFile.path);
      }
    } catch (_) {
      result = '';
    } finally {
      try {
        await player?.dispose();
      } catch (_) {}
      // VideoController 本身没有独立的 dispose 方法需要调用——它随
      // player.dispose() 一起释放底层资源；这里持有它只是为了保证
      // screenshot() 期间纹理链路是完整的。
    }
    return result;
  }

  String _stableHash(String input) {
    const int fnvPrime = 0x01000193;
    int hash = 0x811c9dc5;
    for (final codeUnit in input.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * fnvPrime) & 0xFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  Future<void> _scanAll() async {
    isScanning.value = true;
    _filesByPath.clear();
    final paths = AppSettingsController.instance.videoScanPaths;
    for (final dir in paths) {
      _filesByPath[dir] = await _scanPath(dir);
    }
    isScanning.value = false;
    _enqueueMissingThumbnails(_allFiles);
  }

  Future<List<VideoFile>> _scanPath(String dirPath) async {
    final result = <VideoFile>[];
    try {
      final dir = Directory(dirPath);
      if (!await dir.exists()) return result;
      await for (final e in dir.list(recursive: true)) {
        if (e is File &&
            videoExtensions.contains(p.extension(e.path).toLowerCase())) {
          final s = await e.stat();
          result.add(VideoFile(e.path, p.basename(e.path), s.size));
        }
      }
    } catch (_) {}
    return result;
  }

  Future<void> addPath() async {
    final result = await FilePicker.platform.getDirectoryPath();
    if (result != null) {
      await AppSettingsController.instance.addVideoScanPath(result);
      isScanning.value = true;
      final files = await _scanPath(result);
      _filesByPath[result] = files;
      isScanning.value = false;
      _enqueueMissingThumbnails(files);
    }
  }

  Future<void> removePath(String path) async {
    await AppSettingsController.instance.removeVideoScanPath(path);
    _filesByPath.remove(path);
    if (selectedPath.value == path) selectedPath.value = '';
  }

  @override
  void refresh() => _scanAll();

  void play(VideoFile f) {
    final list = filtered;
    final idx  = list.indexOf(f);
    Get.toNamed('/video/player', arguments: {
      'url':        f.path,
      'title':      p.withoutExtension(f.name),
      'isLocal':    true,
      'playlist':   list,
      'startIndex': idx < 0 ? 0 : idx,
    });
  }

  void playUrl(String url) {
    final u = url.trim();
    if (u.isEmpty) return;
    AppNavigator.toVideoPlayer(url: u, title: u, isLocal: false);
  }
}

// ── Root widget ───────────────────────────────────────────────────────────────

class VideoTabPage extends StatelessWidget {
  const VideoTabPage({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = Get.put(VideoLibraryController(), tag: 'video_lib');
    return _VideoShell(ctrl: ctrl);
  }
}

// ── Shell: left sidebar + right content ──────────────────────────────────────

class _VideoShell extends StatelessWidget {
  final VideoLibraryController ctrl;
  const _VideoShell({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      body: Row(
        children: [
          // ── Left sidebar ───────────────────────────────────────────────
          _Sidebar(ctrl: ctrl),

          // Divider
          VerticalDivider(
            width: 1,
            thickness: 1,
            color: scheme.outlineVariant.withAlpha(60),
          ),

          // ── Right content ──────────────────────────────────────────────
          Expanded(child: _ContentArea(ctrl: ctrl)),
        ],
      ),

      // ── FAB: play network video ────────────────────────────────────────
      floatingActionButton: FloatingActionButton(
        tooltip: '播放网络视频',
        onPressed: () => _showNetworkDialog(context, ctrl),
        child: const Icon(Icons.cast),
      ),
    );
  }

  void _showNetworkDialog(
      BuildContext context, VideoLibraryController ctrl) {
    final urlCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('播放网络视频'),
        content: SizedBox(
          width: 420,
          child: TextField(
            controller: urlCtrl,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: '输入视频链接（http / rtmp / rtsp）',
              prefixIcon: Icon(Icons.link),
              border: OutlineInputBorder(),
            ),
            onSubmitted: (v) {
              Navigator.pop(ctx);
              ctrl.playUrl(v);
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              ctrl.playUrl(urlCtrl.text);
            },
            child: const Text('播放'),
          ),
        ],
      ),
    );
  }
}

// ── Left sidebar ─────────────────────────────────────────────────────────────

class _Sidebar extends StatelessWidget {
  final VideoLibraryController ctrl;
  const _Sidebar({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text   = Theme.of(context).textTheme;

    return SizedBox(
      width: 200,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header row: title + add button
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 8, 6),
            child: Row(
              children: [
                Text('媒体库',
                    style: text.labelLarge
                        ?.copyWith(color: scheme.onSurfaceVariant)),
                const Spacer(),
                Tooltip(
                  message: '添加本地路径',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: ctrl.addPath,
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(Icons.create_new_folder_outlined,
                          size: 20, color: scheme.primary),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // "全部视频" button
          Obx(() {
            final allSelected = ctrl.selectedPath.value.isEmpty;
            return _SidebarItem(
              icon: Icons.video_library_outlined,
              label: '全部视频',
              count: ctrl.totalCount,
              selected: allSelected,
              onTap: () => ctrl.selectedPath.value = '',
            );
          }),

          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            child: Divider(height: 1),
          ),

          // Path list
          Expanded(
            child: Obx(() {
              final paths =
                  AppSettingsController.instance.videoScanPaths;
              if (paths.isEmpty) {
                return Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  child: Text('点击右上角 + 添加路径',
                      style: text.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                      textAlign: TextAlign.center),
                );
              }
              return ListView.builder(
                padding: EdgeInsets.zero,
                itemCount: paths.length,
                itemBuilder: (_, i) {
                  final path = paths[i];
                  final selected = ctrl.selectedPath.value == path;
                  // 用 Obx 包裹，让 count 能响应 _filesByPath（RxMap）的变化——
                  // 扫描/刷新完成后这里才能正确更新数量，不然只会显示构建瞬间
                  // （通常是扫描尚未完成时）的旧值。
                  return Obx(() {
                    final count = ctrl._filesByPath[path]?.length ?? 0;
                    return _SidebarItem(
                      icon: Icons.folder_outlined,
                      label: _shortName(path),
                      tooltip: path,
                      count: count,
                      selected: selected,
                      onTap: () => ctrl.selectedPath.value = path,
                      onRemove: () => ctrl.removePath(path),
                    );
                  });
                },
              );
            }),
          ),
        ],
      ),
    );
  }

  String _shortName(String path) {
    final parts = path.replaceAll('\\', '/').split('/');
    return parts.last.isEmpty && parts.length > 1
        ? parts[parts.length - 2]
        : (parts.last.isEmpty ? path : parts.last);
  }
}

class _SidebarItem extends StatefulWidget {
  final IconData icon;
  final String label;
  final String? tooltip;
  final int count;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onRemove;

  const _SidebarItem({
    required this.icon,
    required this.label,
    this.tooltip,
    required this.count,
    required this.selected,
    required this.onTap,
    this.onRemove,
  });

  @override
  State<_SidebarItem> createState() => _SidebarItemState();
}

class _SidebarItemState extends State<_SidebarItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text   = Theme.of(context).textTheme;

    Widget child = MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(7),
            color: widget.selected
                ? scheme.primaryContainer.withAlpha(160)
                : _hovered
                    ? scheme.surfaceContainerHighest.withAlpha(120)
                    : Colors.transparent,
          ),
          child: Row(
            children: [
              Icon(widget.icon,
                  size: 17,
                  color: widget.selected
                      ? scheme.primary
                      : scheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.label,
                  style: text.bodySmall?.copyWith(
                    fontWeight: widget.selected
                        ? FontWeight.w600
                        : FontWeight.normal,
                    color: widget.selected
                        ? scheme.onPrimaryContainer
                        : scheme.onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              if (_hovered && widget.onRemove != null)
                GestureDetector(
                  onTap: widget.onRemove,
                  child: Icon(Icons.close,
                      size: 14, color: scheme.onSurfaceVariant),
                )
              else
                Text(
                  '${widget.count}',
                  style: text.labelSmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
            ],
          ),
        ),
      ),
    );

    if (widget.tooltip != null) {
      child = Tooltip(message: widget.tooltip!, child: child);
    }
    return child;
  }
}

// ── Right content area ────────────────────────────────────────────────────────

class _ContentArea extends StatelessWidget {
  final VideoLibraryController ctrl;
  const _ContentArea({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text   = Theme.of(context).textTheme;

    return Column(
      children: [
        // ── Toolbar ────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 12, 6),
          child: Row(
            children: [
              // Current path label
              Obx(() {
                final sel = ctrl.selectedPath.value;
                return Text(
                  sel.isEmpty ? '全部视频' : _lastName(sel),
                  style: text.titleSmall
                      ?.copyWith(color: scheme.onSurface),
                );
              }),
              const SizedBox(width: 8),
              Obx(() => Text(
                    ctrl.isScanning.value
                        ? '扫描中...'
                        : '${ctrl.filtered.length} 个视频',
                    style: text.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  )),
              const Spacer(),
              // Search
              SizedBox(
                width: 220,
                height: 34,
                child: TextField(
                  decoration: InputDecoration(
                    hintText: '搜索视频...',
                    hintStyle:
                        text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                    prefixIcon: Icon(Icons.search,
                        size: 17, color: scheme.onSurfaceVariant),
                    isDense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(vertical: 8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                          color: scheme.outlineVariant),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                          color: scheme.outlineVariant),
                    ),
                  ),
                  onChanged: (v) => ctrl.search.value = v,
                ),
              ),
              const SizedBox(width: 6),
              // Refresh
              Tooltip(
                message: '重新扫描',
                child: IconButton(
                  icon: Obx(() => ctrl.isScanning.value
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: scheme.primary),
                        )
                      : const Icon(Icons.refresh, size: 20)),
                  onPressed: ctrl.refresh,
                ),
              ),
              // Sort
              Obx(() => PopupMenuButton<SortMode>(
                    tooltip: '排序',
                    icon: const Icon(Icons.sort, size: 20),
                    initialValue: ctrl.sortMode.value,
                    onSelected: ctrl.setSortMode,
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                          value: SortMode.name, child: Text('按名称')),
                      PopupMenuItem(
                          value: SortMode.size, child: Text('按大小')),
                      PopupMenuItem(
                          value: SortMode.ext,  child: Text('按格式')),
                    ],
                  )),
            ],
          ),
        ),

        const Divider(height: 1),

        // ── Grid / empty state ─────────────────────────────────────────
        Expanded(
          child: Obx(() {
            if (AppSettingsController.instance.videoScanPaths.isEmpty) {
              return _EmptyState(onAdd: ctrl.addPath);
            }
            if (ctrl.isScanning.value && ctrl.filtered.isEmpty) {
              return const Center(child: CircularProgressIndicator());
            }
            final list = ctrl.filtered;
            if (list.isEmpty) {
              return Center(
                child: Text('未找到视频',
                    style: text.bodyMedium
                        ?.copyWith(color: scheme.onSurfaceVariant)),
              );
            }
            return GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate:
                  const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 240,
                childAspectRatio: 16 / 10,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
              itemCount: list.length,
              itemBuilder: (_, i) => Obx(() => _VideoCard(
                    file: list[i],
                    // thumbnails 里存储的是相对于 appdata 的相对路径（兼容旧
                    // 数据可能仍是绝对路径），这里统一转换成当前环境下可直接
                    // 用于 Image.file() 读取的绝对路径。
                    thumbPath: AppDataDir.toAbsolute(
                        ctrl.thumbnails[list[i].path] ?? ''),
                    onTap: () => ctrl.play(list[i]),
                  )),
            );
          }),
        ),
      ],
    );
  }

  String _lastName(String path) {
    final parts = path.replaceAll('\\', '/').split('/');
    return parts.last.isEmpty && parts.length > 1
        ? parts[parts.length - 2]
        : (parts.last.isEmpty ? path : parts.last);
  }
}

// ── Video card ────────────────────────────────────────────────────────────────

class _VideoCard extends StatefulWidget {
  final VideoFile file;
  final String thumbPath;
  final VoidCallback onTap;
  const _VideoCard({
    required this.file,
    required this.onTap,
    this.thumbPath = '',
  });

  @override
  State<_VideoCard> createState() => _VideoCardState();
}

class _VideoCardState extends State<_VideoCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ext = p
        .extension(widget.file.name)
        .replaceFirst('.', '')
        .toUpperCase();
    final hasThumb = widget.thumbPath.isNotEmpty;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 130),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(9),
            color: _hovered
                ? scheme.primaryContainer.withAlpha(100)
                : scheme.surfaceContainerHighest.withAlpha(70),
            border: Border.all(
              color: _hovered
                  ? scheme.primary.withAlpha(160)
                  : scheme.outlineVariant.withAlpha(50),
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 缩略图铺满整张卡片作为背景；没有缩略图时用原来的图标占位
              if (hasThumb)
                Image.file(
                  File(widget.thumbPath),
                  fit: BoxFit.cover,
                  // 缩略图文件可能后续被清理/损坏，读取失败时退回占位图标，
                  // 不让整个网格因为一张坏图崩溃。
                  errorBuilder: (_, __, ___) => _placeholderIcon(scheme),
                )
              else
                _placeholderIcon(scheme),

              // 有缩略图时，在底部加一层渐变，让文件名文字在缩略图上依然清晰可读
              if (hasThumb)
                Positioned(
                  left: 0, right: 0, bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(8, 20, 8, 6),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black87],
                      ),
                    ),
                    child: Text(
                      p.withoutExtension(widget.file.name),
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w500),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),

              // 悬停时的播放图标（有缩略图/无缩略图都显示在中间）
              if (_hovered)
                Center(
                  child: Icon(Icons.play_circle_outline,
                      size: 40,
                      color: hasThumb ? Colors.white : scheme.primary),
                ),

              // Format badge
              Positioned(
                top: 6,
                right: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: scheme.primary.withAlpha(200),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(ext,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 没有缩略图时的占位内容：图标 + 文件名（保持原来的样式）。
  Widget _placeholderIcon(ColorScheme scheme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _hovered ? Icons.play_circle_outline : Icons.movie_outlined,
            size: 34,
            color: _hovered ? scheme.primary : scheme.onSurfaceVariant,
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              p.withoutExtension(widget.file.name),
              style: Theme.of(context).textTheme.bodySmall,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.video_library_outlined,
              size: 72, color: scheme.onSurfaceVariant.withAlpha(120)),
          const SizedBox(height: 16),
          Text('没有媒体库路径',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text('在左侧点击 + 添加本地文件夹',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 24),
          FilledButton.icon(
            icon: const Icon(Icons.create_new_folder_outlined, size: 18),
            label: const Text('添加媒体库路径'),
            onPressed: onAdd,
          ),
        ],
      ),
    );
  }
}
