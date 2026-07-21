import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as p;
// iOS 沙盒无法像 Android 那样遍历整个设备存储，隐藏共享包里的
// `LocalScanner`（全盘扫描实现），改用本 App 内基于"已授权目录书签"的
// `IosLocalScanner`（见下方 import），两者对外接口一致。
import 'package:player_shared/player_shared.dart' hide LocalScanner;

import 'package:nexus_ios/app/controller/app_settings_controller.dart';
import 'package:nexus_ios/app/routes.dart';
import 'package:nexus_ios/widgets/option_dialog.dart';
import 'package:nexus_ios/widgets/search_dialog.dart';
import 'package:nexus_ios/scanner/ios_local_scanner.dart';

/// 视频分类。
class VideoCategory {
  static const int video = 0; // 平铺视频列表
  static const int folder = 1; // 按文件夹分组
  const VideoCategory._();
}

/// 视频排序(平铺模式)。
class VideoSort {
  static const int nameAsc = 0;
  static const int nameDesc = 1;
  static const int timeAsc = 2;
  static const int timeDesc = 3;
  const VideoSort._();
}

/// 文件夹排序。
class VideoFolderSort {
  static const int nameAsc = 0;
  static const int nameDesc = 1;
  const VideoFolderSort._();
}

/// 文件夹分组项。
class VideoFolderEntry {
  final String path;
  final String name;
  final List<ScannedVideo> videos;
  const VideoFolderEntry({
    required this.path,
    required this.name,
    required this.videos,
  });
}

class VideoLibraryController extends GetxController {
  static VideoLibraryController get instance =>
      Get.find<VideoLibraryController>(tag: 'video_library');

  final RxList<ScannedVideo> allVideos = <ScannedVideo>[].obs;
  final RxList<VideoFolderEntry> folderEntries = <VideoFolderEntry>[].obs;

  final RxBool isScanning = false.obs;
  final RxBool hasPermission = false.obs;
  final RxBool permissionRequested = false.obs;

  final RxInt currentCategory = VideoCategory.video.obs;
  final RxInt currentSortVideo = VideoSort.nameAsc.obs;
  final RxInt currentSortFolder = VideoFolderSort.nameAsc.obs;

  /// 搜索关键字：只在当前展示层级内按名称模糊过滤（视频名 / 文件夹名），
  /// 不递归到子目录，与分类/排序一样是纯前端过滤，不触发重新扫描磁盘。
  final RxString searchKeyword = ''.obs;

  // 缩略图生成队列:限制同时最多 2 个视频在后台截图,避免一次性打开大量
  // 解码器实例占用过多 CPU/内存(与 Windows 端保持一致)。
  final List<ScannedVideo> _thumbQueue = [];
  int _thumbRunning = 0;
  static const int _thumbMaxConcurrent = 2;
  bool _disposed = false;

  @override
  void onInit() {
    super.onInit();
    _loadCategoryAndSort();
    _init();
  }

  @override
  void onClose() {
    _disposed = true;
    super.onClose();
  }

  /// 进入视频页时的启动逻辑:
  /// - 若本地已有缓存的视频数据,直接从缓存恢复展示,不接触磁盘、不重新扫描。
  /// - 若没有缓存(首次安装 / 用户清空过数据),检查是否已有授权目录,
  ///   有则扫描一次,扫描完成后写入缓存。
  /// 之后除非用户点击"刷新"按钮,否则不会再自动重新扫描。
  ///
  /// 注意:iOS 沙盒没有"存储权限"这个概念,`hasPermission` 在这里复用为
  /// "是否至少有一个已授权且可访问的目录"(见 [IosLocalScanner.
  /// hasAnyDirectory]),空状态下引导用户去"管理目录"页添加,而不是像
  /// Android 端那样弹系统权限对话框。
  Future<void> _init() async {
    final has = await IosLocalScanner.hasAnyDirectory();
    hasPermission.value = has;
    permissionRequested.value = true;
    if (!has) return;

    final cached = _loadCache();
    if (cached != null && cached.isNotEmpty) {
      allVideos.assignAll(cached);
      _buildFolderEntries();
      _enqueueMissingThumbnails(allVideos);
      return;
    }
    await scanAll();
  }

  /// 触发重新扫描（原"刷新"按钮的功能，现由设置页"扫描视频"入口调用）：
  /// 重新枚举当前所有已授权目录，覆盖本地缓存。[onFound] 可选，用于扫描
  /// 进度弹窗实时展示发现的文件名。若尚无任何已授权目录，直接跳转到
  /// "管理目录"页引导用户添加。
  Future<void> rescan({void Function(String fileName)? onFound}) async {
    final has = await IosLocalScanner.hasAnyDirectory();
    hasPermission.value = has;
    if (!has) {
      await Get.toNamed(AppRoutes.directoryManager);
      hasPermission.value = await IosLocalScanner.hasAnyDirectory();
      if (!hasPermission.value) return;
    }
    await scanAll(onFound: onFound);
  }

  // ── 分类 / 排序持久化 ─────────────────────────────────────────────────────

  void _loadCategoryAndSort() {
    currentCategory.value =
        _loadIntPref(StorageService.kVideoCategory, VideoCategory.video);
    currentSortVideo.value =
        _loadIntPref(StorageService.kVideoSortAndroid, VideoSort.nameAsc);
    currentSortFolder.value =
        _loadIntPref(StorageService.kVideoFolderSort, VideoFolderSort.nameAsc);
  }

  int _loadIntPref(String key, int fallback) {
    try {
      return StorageService.getValue<int>(key, fallback);
    } catch (_) {
      return fallback;
    }
  }

  // ── 扫描结果缓存持久化 ────────────────────────────────────────────────────

  List<ScannedVideo>? _loadCache() {
    try {
      final raw = StorageService.getValue<List>(
          StorageService.kVideoLibraryCache, const []);
      if (raw.isEmpty) return null;
      return raw
          .map((e) =>
              ScannedVideo.fromJson(Map<dynamic, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveCache() async {
    final raw = allVideos.map((v) => v.toJson()).toList();
    await StorageService.setValue(StorageService.kVideoLibraryCache, raw);
  }

  Future<void> scanAll({void Function(String fileName)? onFound}) async {
    isScanning.value = true;
    final videos = await IosLocalScanner.scanVideos(onFound: onFound);
    allVideos.assignAll(videos);
    _buildFolderEntries();
    isScanning.value = false;
    await _saveCache();
    // 后台异步生成缺失的缩略图,生成完成后落盘缓存
    _enqueueMissingThumbnails(allVideos);
  }

  // ── 缩略图生成 ────────────────────────────────────────────────────────────

  void _enqueueMissingThumbnails(List<ScannedVideo> videos) {
    for (final v in videos) {
      if (v.thumbPath.isNotEmpty) continue; // 已生成过
      if (_thumbQueue.any((q) => q.path == v.path)) continue; // 已在队列里
      _thumbQueue.add(v);
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

  Future<void> _generateThumbnail(ScannedVideo v) async {
    if (_disposed) return;
    String result = '';
    try {
      result = await VideoThumbnailGenerator.generate(v.path);
    } catch (_) {
      result = '';
    }
    if (_disposed) return;
    final idx = allVideos.indexWhere((e) => e.path == v.path);
    if (idx >= 0) {
      // 空字符串代表"生成失败",避免反复重试
      allVideos[idx] = allVideos[idx].copyWith(thumbPath: result);
      allVideos.refresh();
      _buildFolderEntries();
      await _saveCache();
    }
  }

  void _buildFolderEntries() {
    final map = <String, List<ScannedVideo>>{};
    for (final v in allVideos) {
      final fp = v.folder.isNotEmpty ? v.folder : '/';
      map.putIfAbsent(fp, () => []).add(v);
    }
    final entries = map.entries.map((e) {
      final leaf = p.basename(e.key);
      return VideoFolderEntry(
        path: e.key,
        name: leaf.isNotEmpty ? leaf : e.key,
        videos: e.value,
      );
    }).toList();
    folderEntries.assignAll(entries);
  }

  List<ScannedVideo> sortedVideos() {
    var list = allVideos.toList();
    final kw = searchKeyword.value.trim().toLowerCase();
    if (kw.isNotEmpty) {
      list = list.where((v) => v.name.toLowerCase().contains(kw)).toList();
    }
    switch (currentSortVideo.value) {
      case VideoSort.nameDesc:
        list.sort((a, b) => b.name.toLowerCase().compareTo(a.name.toLowerCase()));
        break;
      case VideoSort.timeAsc:
        list.sort((a, b) => a.modified.compareTo(b.modified));
        break;
      case VideoSort.timeDesc:
        list.sort((a, b) => b.modified.compareTo(a.modified));
        break;
      default:
        list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    }
    return list;
  }

  List<VideoFolderEntry> sortedFolders() {
    var list = folderEntries.toList();
    final kw = searchKeyword.value.trim().toLowerCase();
    if (kw.isNotEmpty) {
      list = list.where((f) => f.name.toLowerCase().contains(kw)).toList();
    }
    switch (currentSortFolder.value) {
      case VideoFolderSort.nameDesc:
        list.sort((a, b) => b.path.toLowerCase().compareTo(a.path.toLowerCase()));
        break;
      default:
        list.sort((a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()));
    }
    return list;
  }

  Future<void> setCategory(int c) async {
    currentCategory.value = c;
    await StorageService.setValue(StorageService.kVideoCategory, c);
  }

  Future<void> setSortVideo(int s) async {
    currentSortVideo.value = s;
    await StorageService.setValue(StorageService.kVideoSortAndroid, s);
  }

  Future<void> setSortFolder(int s) async {
    currentSortFolder.value = s;
    await StorageService.setValue(StorageService.kVideoFolderSort, s);
  }

  void openVideo(ScannedVideo v) {
    AppNavigator.toVideoPlayer(
      playlist: [{'path': v.path, 'name': v.name}],
      index: 0,
    );
  }

  void openFolder(VideoFolderEntry e) {
    AppNavigator.toVideoFolder(
      folderPath: e.path,
      folderName: e.name,
      sort: currentSortVideo.value,
      videos: e.videos
          .map((v) => {'path': v.path, 'name': v.name, 'thumbPath': v.thumbPath})
          .toList(),
    );
  }

  void playUrl(String url) {
    AppNavigator.toVideoPlayer(
      playlist: [{'path': url, 'name': url}],
      index: 0,
    );
  }
}

class VideoLibraryPage extends StatelessWidget {
  const VideoLibraryPage({super.key});

  @override
  Widget build(BuildContext context) {
    // 重要：不能直接用 Get.put(VideoLibraryController(), tag: ...)。
    // 本页面是 StatelessWidget，只要祖先 widget 树重建（例如 main.dart 中
    // 监听主题设置的最外层 Obx 在主题色/模式变化时重建了整个
    // GetMaterialApp），这里的 build() 就会被重新调用；Get.put 在 tag 已
    // 存在时默认会创建一个新实例并替换旧实例，导致旧实例的 Obx 监听器与
    // 新实例的数据交替生效，表现为列表内容重复渲染，并触发 GetX 的
    // "improper use of a GetX" 检测。
    // 改为"已注册则直接复用，未注册才创建"，确保整个 App 生命周期内
    // 只有一个 VideoLibraryController 实例。
    final ctrl = Get.isRegistered<VideoLibraryController>(tag: 'video_library')
        ? Get.find<VideoLibraryController>(tag: 'video_library')
        : Get.put(VideoLibraryController(), tag: 'video_library');

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        // 注意：这里不能用 Obx 包裹 AppBar。
        //
        // 之前的写法是 Obx(() => AppBar(actions: [...])), 但 actions 里
        // 所有用到 ctrl.xxx.value 的地方，全部在 onTap/onChanged 这些
        // "点击时才会执行"的回调闭包内部，并不会在 Obx 构建 AppBar 的
        // 那一刻被同步读取。也就是说这个 Obx 在 build 期间实际上没有
        // 读取任何响应式变量——这正是 GetX 官方仓库文档中明确指出的
        // "improper use of a GetX" 触发条件（If you are seeing this
        // error, you probably did not insert any observable variables
        // into GetX/Obx）。AppBar 本身也不需要响应式重建：这几个按钮
        // 的文案/图标都是固定的，点击时直接读取 ctrl 的最新值即可，
        // 不需要额外包一层 Obx。故这里直接去掉 Obx，改成普通 AppBar。
        child: AppBar(
            automaticallyImplyLeading: false,
            actions: [
              _TextBarButton(
                icon: Icons.search,
                label: '搜索',
                onTap: () => showSearchDialog(
                  context,
                  title: '搜索视频',
                  hintText: ctrl.currentCategory.value == VideoCategory.video
                      ? '输入视频名称'
                      : '输入文件夹名称',
                  initialText: ctrl.searchKeyword.value,
                  onChanged: (v) => ctrl.searchKeyword.value = v,
                ),
              ),
              _TextBarButton(
                label: '分类',
                onTap: () async {
                  final v = await showOptionDialog(
                    context,
                    '选择分类',
                    ['视频', '文件夹'],
                    selected: ctrl.currentCategory.value,
                  );
                  if (v != null) ctrl.setCategory(v);
                },
              ),
              _TextBarButton(
                label: '排序',
                onTap: () async {
                  if (ctrl.currentCategory.value == VideoCategory.video) {
                    final v = await showOptionDialog(
                      context,
                      '选择排序',
                      ['名称升序', '名称降序', '修改时间升序', '修改时间降序'],
                      selected: ctrl.currentSortVideo.value,
                    );
                    if (v != null) ctrl.setSortVideo(v);
                  } else {
                    final v = await showOptionDialog(
                      context,
                      '选择排序',
                      ['名称升序', '名称降序'],
                      selected: ctrl.currentSortFolder.value,
                    );
                    if (v != null) ctrl.setSortFolder(v);
                  }
                },
              ),
              IconButton(
                icon: const Icon(Icons.link, size: 22),
                tooltip: '链接播放',
                onPressed: () => showLinkPlayDialog(context),
              ),
            ],
          ),
      ),
      body: Obx(() {
        if (!ctrl.permissionRequested.value) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!ctrl.hasPermission.value) {
          return _buildPermissionDenied(context, ctrl);
        }
        return _buildContent(context, ctrl);
      }),
    );
  }

  Widget _buildPermissionDenied(
      BuildContext context, VideoLibraryController ctrl) {
    // iOS 沙盒下"无权限"实际含义是"还没有添加任何已授权目录"，引导用户
    // 直接前往"管理目录"页添加，而不是像 Android 端那样弹系统权限对话框。
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.folder_off_outlined,
                size: 80,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text('还没有导入任何视频文件夹',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'iOS 无法自动扫描整个设备，请手动添加存放视频的文件夹',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              icon: const Icon(Icons.create_new_folder_outlined),
              label: const Text('添加目录'),
              onPressed: ctrl.rescan,
            ),
          ],
        ),
      ),
    );
  }

  /// 注意：此方法在 [body] 的 Obx 回调内部被调用（同一层 build，不再
  /// 额外嵌套 Obx）。之前这里自己包了一层 Obx，与外层 Obx 形成嵌套，
  /// 当内层读取的响应式变量（如新增的 searchKeyword）在短时间内密集变化时，
  /// GetX 会因为同一构建过程中重复注册 observer 而抛出
  /// "improper use of a GetX" 异常，且异常发生前后 UI 会被构建两次，
  /// 表现为列表所有条目重复一份。此处不再包 Obx，读取的响应式变量全部
  /// 由外层 body 的 Obx 统一订阅。
  Widget _buildContent(BuildContext context, VideoLibraryController ctrl) {
    if (ctrl.isScanning.value && ctrl.allVideos.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    final isWide = MediaQuery.sizeOf(context).width >= 600;
    if (ctrl.currentCategory.value == VideoCategory.video) {
      final list = ctrl.sortedVideos();
      if (list.isEmpty) return _buildEmpty(context);
      if (isWide) {
        return GridView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisExtent: 84,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
          ),
          itemCount: list.length,
          itemBuilder: (_, i) => _buildVideoItem(context, ctrl, list[i]),
        );
      }
      return ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: list.length,
        itemBuilder: (_, i) => _buildVideoItem(context, ctrl, list[i]),
      );
    }
    final list = ctrl.sortedFolders();
    if (list.isEmpty) return _buildEmpty(context);
    if (isWide) {
      return GridView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisExtent: 84,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
        ),
        itemCount: list.length,
        itemBuilder: (_, i) => _buildFolderItem(context, ctrl, list[i]),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: list.length,
      itemBuilder: (_, i) => _buildFolderItem(context, ctrl, list[i]),
    );
  }

  /// NovaBox item_local_video_file: 扁平卡片(圆角8 #33FFFFFF),左36dp视频图标,
  /// 中间双行文字(文件名14sp黑 + 大小12sp黑50%),右24dp小播放图标。
  Widget _buildVideoItem(
      BuildContext context, VideoLibraryController ctrl, ScannedVideo v) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withAlpha(120),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant.withAlpha(120), width: 0.5),
      ),
      child: InkWell(
        onTap: () => ctrl.openVideo(v),
        child: Row(
          children: [
            _buildThumb(scheme, v.thumbPath, size: 36),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(v.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: scheme.onSurface, fontSize: 14)),
                  const SizedBox(height: 3),
                  Text(_fmtSize(v.size),
                      style: TextStyle(
                          color: scheme.onSurfaceVariant, fontSize: 12)),
                ],
              ),
            ),
            Icon(Icons.play_circle_outline,
                size: 24, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  /// 文件夹卡片: 左36dp文件夹图标 + 中间双行文字(名称15sp bold黑 + 数量12sp黑50%)+ 右20dp箭头。
  Widget _buildFolderItem(
      BuildContext context, VideoLibraryController ctrl, VideoFolderEntry e) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withAlpha(120),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant.withAlpha(120), width: 0.5),
      ),
      child: InkWell(
        onTap: () => ctrl.openFolder(e),
        child: Row(
          children: [
            Icon(Icons.folder, size: 36, color: scheme.onSurface),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(e.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: scheme.onSurface,
                          fontSize: 15,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 3),
                  Text('${e.videos.length} 个视频',
                      style: TextStyle(
                          color: scheme.onSurfaceVariant, fontSize: 12)),
                ],
              ),
            ),
            Icon(Icons.chevron_right,
                size: 20, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.video_library_outlined,
              size: 80, color: scheme.onSurfaceVariant),
          const SizedBox(height: 16),
          Text('未找到本地视频',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text('请将视频文件放在设备存储根目录',
              style: TextStyle(color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }

  /// 视频缩略图:有缓存缩略图文件则显示图片,否则退回视频图标。
  /// 缩略图文件可能在生成后被用户手动清理,读取失败时同样退回图标,
  /// 不让整个列表因为一张坏图崩溃。
  Widget _buildThumb(ColorScheme scheme, String thumbPath, {required double size}) {
    if (thumbPath.isEmpty) {
      return Icon(Icons.movie_outlined, size: size, color: scheme.onSurface);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Image.file(
        File(thumbPath),
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) =>
            Icon(Icons.movie_outlined, size: size, color: scheme.onSurface),
      ),
    );
  }

  String _fmtSize(int bytes) {
    if (bytes <= 0) return '0 B';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
  }
}

/// 顶栏文字按钮: 14sp,颜色跟随当前 AppBar 前景色, padding 8dp, 水波纹。
/// [icon] 可选,传入时显示在文字左侧(用于"搜索"等带图标的按钮)。
class _TextBarButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  const _TextBarButton({required this.label, this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = onTap == null
        ? Theme.of(context).disabledColor
        : (Theme.of(context).appBarTheme.foregroundColor ??
            Theme.of(context).colorScheme.onSurface);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 4),
              ],
              Text(label, style: TextStyle(color: color, fontSize: 14)),
            ],
          ),
        ),
      ),
    );
  }
}

/// 网络视频页面 — 保留旧的"链接播放"入口以便兼容。
///
/// 现已迁移到 [NetworkVideoPage] 子页;但 NovaBox 也支持从本地视频页面顶部
/// 直接打开链接,故保留一个简单的 URL 输入对话框入口。
Future<void> showLinkPlayDialog(BuildContext context) async {
  final urlCtrl = TextEditingController();
  final url = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('链接播放'),
      content: TextField(
        controller: urlCtrl,
        autofocus: true,
        decoration: const InputDecoration(
          hintText: '请输入地址...(http/https/rtmp/rtsp)',
          border: OutlineInputBorder(),
        ),
        keyboardType: TextInputType.url,
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消')),
        FilledButton(
            onPressed: () => Navigator.of(ctx).pop(urlCtrl.text.trim()),
            child: const Text('确定')),
      ],
    ),
  );
  if (url == null || url.isEmpty) return;
  if (!context.mounted) return;
  final settings = AppSettingsController.instance;
  settings.addRecentFile(url);
  // ignore: use_build_context_synchronously
  AppNavigator.toVideoPlayer(
    playlist: [{'path': url, 'name': url}],
    index: 0,
  );
}
