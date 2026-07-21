import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as p;
import 'package:player_shared/player_shared.dart';

import 'package:nexus_tv/app/routes/tv_routes.dart';
import 'package:nexus_tv/app/theme/tv_theme.dart';
import 'package:nexus_tv/app/tv_focus_node.dart';
import 'package:nexus_tv/app/tv_style.dart';
import 'package:nexus_tv/widgets/tv_highlight.dart';
import 'package:nexus_tv/widgets/tv_playback_entry.dart';

/// 视频分类:与手机端一致(视频平铺 / 按文件夹分组)。
class _VideoCategory {
  static const int video = 0;
  static const int folder = 1;
  const _VideoCategory._();
}

/// 视频排序(平铺模式),与手机端保持一致的枚举含义。
class _VideoSort {
  static const int nameAsc = 0;
  static const int nameDesc = 1;
  static const int timeAsc = 2;
  static const int timeDesc = 3;
  const _VideoSort._();
}

/// 文件夹排序。
class _VideoFolderSort {
  static const int nameAsc = 0;
  static const int nameDesc = 1;
  const _VideoFolderSort._();
}

/// 文件夹分组项。
class _VideoFolderEntry {
  final String path;
  final String name;
  final List<ScannedVideo> videos;
  const _VideoFolderEntry({
    required this.path,
    required this.name,
    required this.videos,
  });
}

/// 格式化文件大小
String _fmtSize(int bytes) {
  if (bytes <= 0) return '0 B';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
  return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
}

class TvVideoController extends GetxController {
  /// 扫描到的全部视频文件
  final files = <ScannedVideo>[].obs;
  final folderEntries = <_VideoFolderEntry>[].obs;
  final isScanning = false.obs;
  final scanStatus = ''.obs;

  final currentCategory = _VideoCategory.video.obs;
  final currentSortVideo = _VideoSort.nameAsc.obs;
  final currentSortFolder = _VideoFolderSort.nameAsc.obs;

  /// 文件夹分类下的钻取状态:空 = 显示文件夹列表,非空 = 显示该文件夹内视频
  final selectedFolder = ''.obs;

  // 缩略图生成队列:限制同时最多 2 个视频在后台截图,避免一次性打开大量
  // 解码器实例占用过多 CPU/内存(与手机端、Windows 端保持一致)。
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
  /// - 若没有缓存(首次安装 / 用户清空过数据),才请求权限并扫描一次,
  ///   扫描完成后写入缓存。
  /// 之后除非用户点击"刷新"按钮,否则不会再自动重新扫描。
  Future<void> _init() async {
    final has = await PermissionUtil.hasMediaPermissions();
    if (!has) {
      final granted = await PermissionUtil.requestMediaPermissions();
      if (!granted) {
        scanStatus.value = '未获得存储权限,无法扫描';
        return;
      }
    }

    final cached = _loadCache();
    if (cached != null && cached.isNotEmpty) {
      files.assignAll(cached);
      _buildFolderEntries();
      scanStatus.value = '共 ${files.length} 个视频';
      _enqueueMissingThumbnails(files);
      return;
    }
    await scanAll();
  }

  // ── 分类 / 排序持久化 ─────────────────────────────────────────────────────

  void _loadCategoryAndSort() {
    currentCategory.value =
        _loadIntPref(StorageService.kVideoCategory, _VideoCategory.video);
    currentSortVideo.value =
        _loadIntPref(StorageService.kVideoSortTv, _VideoSort.nameAsc);
    currentSortFolder.value = _loadIntPref(
        StorageService.kVideoFolderSort, _VideoFolderSort.nameAsc);
  }

  int _loadIntPref(String key, int fallback) {
    try {
      return StorageService.getValue<int>(key, fallback);
    } catch (_) {
      return fallback;
    }
  }

  Future<void> setCategory(int c) async {
    currentCategory.value = c;
    selectedFolder.value = '';
    await StorageService.setValue(StorageService.kVideoCategory, c);
  }

  Future<void> setSortVideo(int s) async {
    currentSortVideo.value = s;
    await StorageService.setValue(StorageService.kVideoSortTv, s);
  }

  Future<void> setSortFolder(int s) async {
    currentSortFolder.value = s;
    await StorageService.setValue(StorageService.kVideoFolderSort, s);
  }

  // ── 扫描结果缓存持久化 ────────────────────────────────────────────────────

  List<ScannedVideo>? _loadCache() {
    try {
      final raw = StorageService.getValue<List>(
          StorageService.kVideoLibraryCacheTv, const []);
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
    final raw = files.map((v) => v.toJson()).toList();
    await StorageService.setValue(StorageService.kVideoLibraryCacheTv, raw);
  }

  /// 刷新按钮:无条件重新扫描一次,覆盖本地缓存(与安卓端一致:先确认权限,
  /// 再全局扫描本地目录)。
  Future<void> scanAll() async {
    final granted = await PermissionUtil.requestMediaPermissions();
    if (!granted) {
      scanStatus.value = '未获得存储权限,无法扫描';
      return;
    }
    isScanning.value = true;
    selectedFolder.value = '';
    try {
      final result = await LocalScanner.scanVideos();
      files.assignAll(result);
    } catch (_) {}
    _buildFolderEntries();
    isScanning.value = false;
    scanStatus.value = '共 ${files.length} 个视频';
    await _saveCache();
    // 后台异步生成缺失的缩略图,生成完成后落盘缓存
    _enqueueMissingThumbnails(files);
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
    final idx = files.indexWhere((e) => e.path == v.path);
    if (idx >= 0) {
      // 空字符串代表"生成失败",避免反复重试
      files[idx] = files[idx].copyWith(thumbPath: result);
      files.refresh();
      _buildFolderEntries();
      await _saveCache();
    }
  }

  // ── 分类:视频平铺 / 文件夹分组 ────────────────────────────────────────────

  void _buildFolderEntries() {
    final map = <String, List<ScannedVideo>>{};
    for (final v in files) {
      final k = v.folder.isNotEmpty ? v.folder : '/';
      map.putIfAbsent(k, () => []).add(v);
    }
    folderEntries.assignAll(map.entries
        .map((e) => _VideoFolderEntry(
              path: e.key,
              name: p.basename(e.key).isNotEmpty ? p.basename(e.key) : e.key,
              videos: e.value,
            ))
        .toList());
  }

  List<_VideoFolderEntry> sortedFolders() {
    final list = folderEntries.toList();
    switch (currentSortFolder.value) {
      case _VideoFolderSort.nameDesc:
        list.sort(
            (a, b) => b.name.toLowerCase().compareTo(a.name.toLowerCase()));
        break;
      default:
        list.sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    }
    return list;
  }

  List<ScannedVideo> _sortVideos(List<ScannedVideo> list, int sort) {
    final l = list.toList();
    switch (sort) {
      case _VideoSort.nameDesc:
        l.sort((a, b) => b.name.toLowerCase().compareTo(a.name.toLowerCase()));
        break;
      case _VideoSort.timeAsc:
        l.sort((a, b) => a.modified.compareTo(b.modified));
        break;
      case _VideoSort.timeDesc:
        l.sort((a, b) => b.modified.compareTo(a.modified));
        break;
      default:
        l.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    }
    return l;
  }

  /// 当前显示的视频列表(平铺分类,或文件夹分类下已点入某个文件夹)
  List<ScannedVideo> get sortedFiles {
    if (currentCategory.value == _VideoCategory.video) {
      return _sortVideos(files, currentSortVideo.value);
    }
    if (selectedFolder.value.isEmpty) return [];
    final entry = folderEntries.firstWhereOrNull(
        (e) => e.path == selectedFolder.value);
    if (entry == null) return [];
    return _sortVideos(entry.videos, currentSortVideo.value);
  }

  void openFolder(_VideoFolderEntry e) => selectedFolder.value = e.path;
  void backToFolders() => selectedFolder.value = '';

  /// 直接全屏播放,把整个可见列表传入,支持播放页内切换。
  void play(List<ScannedVideo> list, int index) {
    if (list.isEmpty || index < 0 || index >= list.length) return;
    final playlist = list
        .map((f) => {'path': f.path, 'name': f.name, 'thumbPath': f.thumbPath})
        .toList();
    TvNavigator.toVideoPlayer(playlist: playlist, index: index);
  }
}

class TvVideoPage extends StatelessWidget {
  const TvVideoPage({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = Get.put(TvVideoController());
    return Obx(() => Scaffold(
          backgroundColor: TvColors.background,
          body: Column(
            children: [
              _buildTopBar(context, ctrl),
              Container(
                  height: 1.w, width: double.infinity, color: TvColors.divider),
              _buildCategoryBar(ctrl),
              Container(
                  height: 1.w, width: double.infinity, color: TvColors.divider),
              Expanded(child: _buildBody(ctrl)),
            ],
          ),
        ));
  }

  /// 顶部栏:标题 + (文件夹钻取中显示"返回文件夹") + 排序/刷新
  Widget _buildTopBar(BuildContext context, TvVideoController ctrl) {
    return Container(
      height: 96.w,
      padding: EdgeInsets.symmetric(horizontal: 32.w),
      color: TvColors.surface,
      child: Row(
        children: [
          Text('视频', style: TvStyle.titleMedium),
          Obx(() => ctrl.selectedFolder.value.isNotEmpty
              ? Padding(
                  padding: EdgeInsets.only(left: 16.w),
                  child: _ActionButton(
                    label: '返回文件夹',
                    icon: Icons.folder_open,
                    onTap: ctrl.backToFolders,
                  ),
                )
              : const SizedBox.shrink()),
          const Spacer(),
          const TvPlaybackEntry(),
          SizedBox(width: 16.w),
          _ActionButton(
            label: '排序',
            icon: Icons.sort,
            onTap: () => _showSortDialog(context, ctrl),
          ),
          SizedBox(width: 16.w),
          Obx(() => _ActionButton(
                label: ctrl.isScanning.value ? '扫描中' : '刷新',
                icon: Icons.refresh,
                onTap: ctrl.isScanning.value ? null : ctrl.scanAll,
              )),
        ],
      ),
    );
  }

  /// 分类标签栏:视频 / 文件夹(与手机端语义一致)
  Widget _buildCategoryBar(TvVideoController ctrl) {
    final tabs = ['视频', '文件夹'];
    return Obx(() => Container(
          height: 80.w,
          color: TvColors.surface,
          padding: EdgeInsets.symmetric(horizontal: 24.w),
          child: Row(
            children: [
              for (int i = 0; i < tabs.length; i++) ...[
                if (i > 0) SizedBox(width: 8.w),
                _CategoryTab(
                  key: ValueKey('cat_$i'),
                  label: tabs[i],
                  selected: ctrl.currentCategory.value == i,
                  onTap: () => ctrl.setCategory(i),
                ),
              ],
              const Spacer(),
              Text(ctrl.scanStatus.value, style: TvStyle.labelSmall),
            ],
          ),
        ));
  }

  /// 主体:加载中 / 文件夹网格 / 视频卡片网格 / 空状态
  Widget _buildBody(TvVideoController ctrl) {
    return Obx(() {
      // 扫描中且尚无文件
      if (ctrl.isScanning.value && ctrl.files.isEmpty) {
        return Center(
          child: CircularProgressIndicator(color: TvColors.primary),
        );
      }
      // 文件夹分类 + 尚未点入某个文件夹:展示文件夹网格
      if (ctrl.currentCategory.value == _VideoCategory.folder &&
          ctrl.selectedFolder.value.isEmpty) {
        final folders = ctrl.sortedFolders();
        if (folders.isEmpty) {
          return _buildEmptyState(
            icon: Icons.video_library_outlined,
            title: '未找到视频文件',
            actionLabel: '重新扫描',
            actionIcon: Icons.refresh,
            onAction: ctrl.scanAll,
          );
        }
        return _buildFolderGrid(ctrl, folders);
      }
      final list = ctrl.sortedFiles;
      if (list.isEmpty) {
        return _buildEmptyState(
          icon: Icons.video_library_outlined,
          title: '未找到视频文件',
          actionLabel: '重新扫描',
          actionIcon: Icons.refresh,
          onAction: ctrl.scanAll,
        );
      }
      return _buildGrid(ctrl, list);
    });
  }

  /// 视频卡片网格
  Widget _buildGrid(TvVideoController ctrl, List<ScannedVideo> list) {
    return GridView.builder(
      padding: EdgeInsets.symmetric(horizontal: 32.w, vertical: 24.w),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 5,
        mainAxisExtent: 360.w,
        crossAxisSpacing: 16.w,
        mainAxisSpacing: 16.w,
      ),
      itemCount: list.length,
      itemBuilder: (_, i) {
        final f = list[i];
        return _VideoCard(
          key: ValueKey(f.path),
          file: f,
          autofocus: i == 0,
          onTap: () => ctrl.play(list, i),
        );
      },
    );
  }

  /// 文件夹卡片网格
  Widget _buildFolderGrid(
      TvVideoController ctrl, List<_VideoFolderEntry> list) {
    return GridView.builder(
      padding: EdgeInsets.symmetric(horizontal: 32.w, vertical: 24.w),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 5,
        mainAxisExtent: 220.w,
        crossAxisSpacing: 16.w,
        mainAxisSpacing: 16.w,
      ),
      itemCount: list.length,
      itemBuilder: (_, i) {
        final f = list[i];
        return _FolderCard(
          key: ValueKey(f.path),
          folder: f,
          autofocus: i == 0,
          onTap: () => ctrl.openFolder(f),
        );
      },
    );
  }

  /// 空状态占位
  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String actionLabel,
    required IconData actionIcon,
    required VoidCallback onAction,
  }) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 100.w, color: TvColors.textSecondary),
          TvStyle.vGap24,
          Text(title, style: TvStyle.titleMedium),
          TvStyle.vGap24,
          _ActionButton(
            label: actionLabel,
            icon: actionIcon,
            autofocus: true,
            onTap: onAction,
          ),
        ],
      ),
    );
  }

  /// 排序选择对话框(视频分类下按平铺排序,文件夹分类下按文件夹排序;
  /// 已点入某个文件夹时,列表内部仍按平铺排序)
  void _showSortDialog(BuildContext context, TvVideoController ctrl) {
    final inFolderCategory = ctrl.currentCategory.value == _VideoCategory.folder;
    final showingFolderList =
        inFolderCategory && ctrl.selectedFolder.value.isEmpty;
    if (showingFolderList) {
      _showOptionDialog(
        context,
        '选择排序',
        ['名称升序', '名称降序'],
        ctrl.currentSortFolder.value,
        (i) => ctrl.setSortFolder(i),
      );
    } else {
      _showOptionDialog(
        context,
        '选择排序',
        ['名称升序', '名称降序', '修改时间升序', '修改时间降序'],
        ctrl.currentSortVideo.value,
        (i) => ctrl.setSortVideo(i),
      );
    }
  }
}

/// 通用选项对话框,选项用 TvHighlight 包裹确保遥控器可聚焦
void _showOptionDialog(
  BuildContext context,
  String title,
  List<String> options,
  int selected,
  ValueChanged<int> onSelect,
) {
  showDialog(
    context: context,
    builder: (_) => AlertDialog(
      backgroundColor: TvColors.surface,
      title: Text(title, style: TvStyle.titleMedium),
      content: SizedBox(
        width: 500.w,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: options.asMap().entries.map((e) {
            return _OptionTile(
              label: e.value,
              selected: e.key == selected,
              autofocus: e.key == 0,
              onTap: () {
                Get.back();
                onSelect(e.key);
              },
            );
          }).toList(),
        ),
      ),
    ),
  );
}

/// 视频卡片
class _VideoCard extends StatefulWidget {
  final ScannedVideo file;
  final bool autofocus;
  final VoidCallback onTap;
  const _VideoCard({
    super.key,
    required this.file,
    required this.onTap,
    this.autofocus = false,
  });

  @override
  State<_VideoCard> createState() => _VideoCardState();
}

class _VideoCardState extends State<_VideoCard> {
  final _focus = TvFocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.file;
    return TvHighlight(
      focusNode: _focus,
      autofocus: widget.autofocus,
      onTap: widget.onTap,
      borderRadius: TvStyle.radius12,
      color: TvColors.card,
      child: Padding(
        padding: EdgeInsets.all(16.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 缩略图(有缓存则显示图片,否则退回图标占位)
            Container(
              height: 180.w,
              width: double.infinity,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: TvColors.primary.withAlpha(40),
                borderRadius: TvStyle.radius8,
              ),
              child: f.thumbPath.isEmpty
                  ? Center(
                      child: Obx(() => Icon(
                            Icons.movie,
                            size: 64.w,
                            color: _focus.isFocused.value
                                ? TvColors.textPrimary
                                : TvColors.primary,
                          )),
                    )
                  : Image.file(
                      File(f.thumbPath),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Center(
                        child: Icon(Icons.movie,
                            size: 64.w, color: TvColors.primary),
                      ),
                    ),
            ),
            SizedBox(height: 12.w),
            Text(
              p.withoutExtension(f.name),
              style: TvStyle.bodyMedium,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            SizedBox(height: 4.w),
            Text(_fmtSize(f.size), style: TvStyle.labelSmall),
          ],
        ),
      ),
    );
  }
}

/// 文件夹卡片
class _FolderCard extends StatefulWidget {
  final _VideoFolderEntry folder;
  final bool autofocus;
  final VoidCallback onTap;
  const _FolderCard({
    super.key,
    required this.folder,
    required this.onTap,
    this.autofocus = false,
  });

  @override
  State<_FolderCard> createState() => _FolderCardState();
}

class _FolderCardState extends State<_FolderCard> {
  final _focus = TvFocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.folder;
    return TvHighlight(
      focusNode: _focus,
      autofocus: widget.autofocus,
      onTap: widget.onTap,
      borderRadius: TvStyle.radius12,
      color: TvColors.card,
      child: Padding(
        padding: EdgeInsets.all(16.w),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.folder, size: 64.w, color: TvColors.primary),
            SizedBox(height: 12.w),
            Text(
              f.name,
              style: TvStyle.bodyMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            SizedBox(height: 4.w),
            Text('${f.videos.length} 个视频', style: TvStyle.labelSmall),
          ],
        ),
      ),
    );
  }
}

/// 分类标签
class _CategoryTab extends StatefulWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _CategoryTab({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_CategoryTab> createState() => _CategoryTabState();
}

class _CategoryTabState extends State<_CategoryTab> {
  final _focus = TvFocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TvHighlight(
      focusNode: _focus,
      onTap: widget.onTap,
      borderRadius: TvStyle.radius8,
      color: widget.selected
          ? TvColors.primary.withAlpha(40)
          : Colors.transparent,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 16.w),
        child: Text(
          widget.label,
          style: TvStyle.bodyMedium.copyWith(
            color: widget.selected
                ? TvColors.primary
                : TvColors.textSecondary,
            fontWeight:
                widget.selected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

/// 操作按钮(图标 + 文字)
class _ActionButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool autofocus;
  const _ActionButton({
    super.key,
    required this.label,
    required this.icon,
    this.onTap,
    this.autofocus = false,
  });

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton> {
  final _focus = TvFocusNode();

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
      color: TvColors.card,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 12.w),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(widget.icon, size: 24.w, color: Colors.white),
            SizedBox(width: 8.w),
            Text(widget.label, style: TvStyle.bodyMedium),
          ],
        ),
      ),
    );
  }
}

/// 纯图标按钮(返回等)
class _IconButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final bool autofocus;
  const _IconButton({
    super.key,
    required this.icon,
    this.onTap,
    this.autofocus = false,
  });

  @override
  State<_IconButton> createState() => _IconButtonState();
}

class _IconButtonState extends State<_IconButton> {
  final _focus = TvFocusNode();

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
      child: Padding(
        padding: EdgeInsets.all(12.w),
        child: Icon(widget.icon, size: 32.w, color: Colors.white),
      ),
    );
  }
}

/// 对话框选项
class _OptionTile extends StatefulWidget {
  final String label;
  final bool selected;
  final bool autofocus;
  final VoidCallback onTap;
  const _OptionTile({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.autofocus = false,
  });

  @override
  State<_OptionTile> createState() => _OptionTileState();
}

class _OptionTileState extends State<_OptionTile> {
  final _focus = TvFocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4.w),
      child: TvHighlight(
        focusNode: _focus,
        autofocus: widget.autofocus,
        onTap: widget.onTap,
        borderRadius: TvStyle.radius8,
        color: widget.selected
            ? TvColors.primary.withAlpha(40)
            : Colors.transparent,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 14.w),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.selected
                    ? Icons.check_circle
                    : Icons.radio_button_unchecked,
                color: widget.selected
                    ? TvColors.primary
                    : TvColors.textSecondary,
                size: 28.w,
              ),
              SizedBox(width: 12.w),
              Text(widget.label, style: TvStyle.bodyMedium),
            ],
          ),
        ),
      ),
    );
  }
}
