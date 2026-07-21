import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as p;
import 'package:player_shared/player_shared.dart' hide AppDataDir;

import 'package:nexus_macos/app/controller/app_settings_controller.dart';
import 'package:nexus_macos/app/routes.dart';

// ══════════════════════════════════════════════════════════════════════════════
//  支持的音频扩展名
// ══════════════════════════════════════════════════════════════════════════════

const Set<String> musicExtensions = {
  '.mp3', '.flac', '.aac', '.wav', '.ogg',
  '.m4a', '.wma', '.opus', '.ape',
};

// ══════════════════════════════════════════════════════════════════════════════
//  枚举
// ══════════════════════════════════════════════════════════════════════════════

enum MusicCategory { song, album, artist }

enum SongSortMode { titleAsc, titleDesc, artistAsc, artistDesc, timeAsc, timeDesc }

enum GroupSortMode { nameAsc, nameDesc, timeAsc, timeDesc }

// ══════════════════════════════════════════════════════════════════════════════
//  Controller
// ══════════════════════════════════════════════════════════════════════════════

class MusicLibraryController extends GetxController {
  final _filesByPath = <String, List<RichMusicFile>>{}.obs;

  final isScanning   = false.obs;
  final scanProgress = 0.obs;
  final scanTotal    = 0.obs;

  final search       = ''.obs;
  final selectedPath = ''.obs;

  final category  = MusicCategory.song.obs;
  final songSort  = SongSortMode.titleAsc.obs;
  final groupSort = GroupSortMode.nameAsc.obs;

  final Rx<String?> drillGroup = Rx<String?>(null);

  /// 封面内存缓存 + 分批增量加载器（三端统一策略）：
  /// 只读当前展示列表（按当前分类/排序/搜索/目录筛选结果）的前 200 首
  /// 封面，滚动到还没加载的位置再整批加载下一个 200，不落盘。
  late final AudioCoverMemoryCache<RichMusicFile> _coverCache =
      AudioCoverMemoryCache<RichMusicFile>(
    batchSize: 200,
    pathOf: (f) => f.path,
    hasCover: (f) => f.coverBytes != null,
    applyCover: (f, meta) => f.coverBytes = meta.coverBytes,
  );

  // ── Computed ───────────────────────────────────────────────────────────────

  List<RichMusicFile> get _allFiles =>
      _filesByPath.values.expand((l) => l).toList();

  List<RichMusicFile> get _sourceFiles =>
      selectedPath.value.isEmpty
          ? _allFiles
          : (_filesByPath[selectedPath.value] ?? []);

  int get totalCount => _allFiles.length;

  List<RichMusicFile> get _searchFiltered {
    var list = _sourceFiles;
    final q = search.value.toLowerCase().trim();
    if (q.isEmpty) return list;
    return list.where((f) =>
        f.title.toLowerCase().contains(q) ||
        f.artist.toLowerCase().contains(q) ||
        f.album.toLowerCase().contains(q)).toList();
  }

  List<RichMusicFile> get sortedSongs {
    final list = List<RichMusicFile>.from(_searchFiltered);
    _applySongSort(list);
    return list;
  }

  void _applySongSort(List<RichMusicFile> list) {
    switch (songSort.value) {
      case SongSortMode.titleAsc:
        list.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
        break;
      case SongSortMode.titleDesc:
        list.sort((a, b) => b.title.toLowerCase().compareTo(a.title.toLowerCase()));
        break;
      case SongSortMode.artistAsc:
        list.sort((a, b) => a.artist.toLowerCase().compareTo(b.artist.toLowerCase()));
        break;
      case SongSortMode.artistDesc:
        list.sort((a, b) => b.artist.toLowerCase().compareTo(a.artist.toLowerCase()));
        break;
      case SongSortMode.timeAsc:
        list.sort((a, b) => a.modifiedMs.compareTo(b.modifiedMs));
        break;
      case SongSortMode.timeDesc:
        list.sort((a, b) => b.modifiedMs.compareTo(a.modifiedMs));
        break;
    }
  }

  Map<String, List<RichMusicFile>> get groups {
    final map = <String, List<RichMusicFile>>{};
    for (final f in _sourceFiles) {
      final List<String> keys;
      if (category.value == MusicCategory.artist) {
        keys = _splitArtists(f.artist);
      } else {
        keys = [(f.album.isNotEmpty) ? f.album : '未知专辑'];
      }
      for (final k in keys) {
        map.putIfAbsent(k, () => []).add(f);
      }
    }
    return map;
  }

  List<MapEntry<String, List<RichMusicFile>>> get sortedGroups {
    final entries = groups.entries.toList();
    switch (groupSort.value) {
      case GroupSortMode.nameAsc:
        entries.sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()));
        break;
      case GroupSortMode.nameDesc:
        entries.sort((a, b) => b.key.toLowerCase().compareTo(a.key.toLowerCase()));
        break;
      case GroupSortMode.timeAsc:
        entries.sort((a, b) => _minTime(a.value).compareTo(_minTime(b.value)));
        break;
      case GroupSortMode.timeDesc:
        entries.sort((a, b) => _maxTime(b.value).compareTo(_maxTime(a.value)));
        break;
    }
    return entries;
  }

  List<RichMusicFile> get drillSongs {
    final gName = drillGroup.value;
    if (gName == null) return [];
    final list = List<RichMusicFile>.from(groups[gName] ?? []);
    _applySongSort(list);
    return list;
  }

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void onInit() {
    super.onInit();
    _loadCategoryAndSort();
    _loadFromCacheThenScanNewPaths();
  }

  @override
  void onClose() {
    _coverCache.dispose();
    super.onClose();
  }

  // ── 分类 / 排序持久化 ────────────────────────────────────────────────────────

  void _loadCategoryAndSort() {
    final catStr = StorageService.getValue<String>(
        StorageService.kMusicCategory, MusicCategory.song.name);
    category.value = MusicCategory.values.firstWhere(
      (c) => c.name == catStr,
      orElse: () => MusicCategory.song,
    );

    final songSortStr = StorageService.getValue<String>(
        StorageService.kMusicSongSort, SongSortMode.titleAsc.name);
    songSort.value = SongSortMode.values.firstWhere(
      (s) => s.name == songSortStr,
      orElse: () => SongSortMode.titleAsc,
    );

    final groupSortStr = StorageService.getValue<String>(
        StorageService.kMusicGroupSort, GroupSortMode.nameAsc.name);
    groupSort.value = GroupSortMode.values.firstWhere(
      (s) => s.name == groupSortStr,
      orElse: () => GroupSortMode.nameAsc,
    );
  }

  Future<void> setSongSort(SongSortMode mode) async {
    songSort.value = mode;
    await StorageService.setValue(StorageService.kMusicSongSort, mode.name);
    // 排序方式变化后"前 200"对应的曲目通常也变了，按新展示顺序重新计算。
    resetCoverBatchesAndReload();
  }

  Future<void> setGroupSort(GroupSortMode mode) async {
    groupSort.value = mode;
    await StorageService.setValue(StorageService.kMusicGroupSort, mode.name);
    resetCoverBatchesAndReload();
  }

  // ── 封面：内存分批增量加载 ───────────────────────────────────────────────────
  //
  // 三端统一策略：封面不落盘，只在内存里持有；只为"当前展示列表"分批
  // 加载，默认每批 200 首。切换分类/排序/搜索/目录筛选后，"当前展示
  // 列表"的顺序或内容会变化，需要重新从头计算"前 200"。

  /// 触发响应式更新，供封面分批加载器在每首歌加载完成后调用。
  void _refreshFiles() => _filesByPath.refresh();

  /// 当前展示列表：优先按"进入了某个分组详情"(drillSongs)，否则按
  /// "歌曲/专辑/艺术家分类下的排序结果"取值，与页面实际渲染的列表
  /// 顺序保持一致。
  List<RichMusicFile> _currentOrderedFiles() {
    if (drillGroup.value != null) return drillSongs;
    if (category.value == MusicCategory.song) return sortedSongs;
    return sortedGroups.expand((e) => e.value).toList(growable: false);
  }

  /// 确保"当前展示列表"的前 200 首封面已加载。在列表首次展示、
  /// 分类/排序/搜索切换、从缓存恢复、扫描完成后调用。
  void ensureCoversForCurrentView() {
    _coverCache.ensureFirstBatch(_currentOrderedFiles(), onProgress: _refreshFiles);
  }

  /// 列表滚动到索引 [visibleIndex] 但该位置还没有封面时调用：按 200 首
  /// 为一批整批增量加载(200→400→600…)，不是逐条懒加载。
  void onSongVisible(int visibleIndex) {
    _coverCache.ensureVisible(visibleIndex, _currentOrderedFiles(),
        onProgress: _refreshFiles);
  }

  /// 展示列表的顺序/内容发生变化(分类、排序、搜索关键字、目录筛选、
  /// 进入/退出分组详情)时调用：清零已加载批次计数，按新列表重新从头
  /// 计算"前 200"。
  void resetCoverBatchesAndReload() {
    _coverCache.reset();
    ensureCoversForCurrentView();
  }

  // ── 扫描结果缓存持久化 ───────────────────────────────────────────────────────
  //
  // 缓存整体存为一个 Map<String path, List<Map>>，序列化后写入 Hive 的
  // kMusicLibraryCache 键。启动/进入音乐页时优先从缓存恢复，避免每次都
  // 重新遍历磁盘、重新解析 ID3 标签（对大音乐库来说很慢）。

  Map<String, dynamic> _loadCacheRaw() {
    final raw = StorageService.getValue<Map>(
        StorageService.kMusicLibraryCache, <String, dynamic>{});
    return Map<String, dynamic>.from(raw);
  }

  Future<void> _saveCache() async {
    final raw = <String, dynamic>{
      for (final entry in _filesByPath.entries)
        entry.key: entry.value.map((f) => f.toJson()).toList(),
    };
    await StorageService.setValue(StorageService.kMusicLibraryCache, raw);
  }

  /// 启动时：先把缓存里已有的路径直接展示出来（不接触磁盘）；
  /// 对缓存里没有的路径（例如刚添加还没扫描过、或缓存被清空过）才去扫描一次。
  /// 这样保证"首次添加路径扫描一次，之后启动/进入页面不再自动扫描"。
  Future<void> _loadFromCacheThenScanNewPaths() async {
    final cacheRaw = _loadCacheRaw();
    final configuredPaths = AppSettingsController.instance.musicScanPaths;

    // 先从缓存恢复所有已配置路径中"缓存里存在"的部分
    for (final dir in configuredPaths) {
      final cached = cacheRaw[dir];
      if (cached is List) {
        try {
          _filesByPath[dir] = cached
              .map((e) => RichMusicFile.fromJson(Map.from(e as Map)))
              .toList();
        } catch (_) {
          _filesByPath[dir] = [];
        }
      }
    }

    // coverBytes 不落盘缓存，从缓存恢复的曲目此时封面字段都是 null，
    // 需要单独触发一次"只读前 200 首封面"的分批加载。
    if (_filesByPath.isNotEmpty) {
      ensureCoversForCurrentView();
    }

    // 找出配置了但缓存里完全没有的路径（新添加、从未扫描过），只对这些扫描
    final newPaths =
        configuredPaths.where((d) => !cacheRaw.containsKey(d)).toList();
    if (newPaths.isEmpty) return;

    isScanning.value = true;
    drillGroup.value = null;
    for (final dir in newPaths) {
      _filesByPath[dir] = await _scanPath(dir);
    }
    isScanning.value = false;
    await _saveCache();
    resetCoverBatchesAndReload();
  }

  // ── Scan ───────────────────────────────────────────────────────────────────

  /// 对"当前正在查看"的目录重新扫描：
  /// - 若当前选中了某个具体目录（selectedPath 非空），只重新扫描该目录；
  /// - 若当前在"全部音乐"视图（selectedPath 为空），重新扫描所有已配置目录。
  /// 对应刷新按钮：只刷新用户正在看的内容，而不是无条件全量重扫。
  @override
  Future<void> refresh() async {
    if (isScanning.value) return;
    drillGroup.value = null;
    final sel = selectedPath.value;
    if (sel.isEmpty) {
      await _scanAll();
    } else {
      isScanning.value = true;
      _filesByPath[sel] = await _scanPath(sel);
      isScanning.value = false;
      await _saveCache();
    }
    resetCoverBatchesAndReload();
  }

  Future<void> _scanAll() async {
    if (isScanning.value) return;
    isScanning.value = true;
    drillGroup.value = null;
    _filesByPath.clear();
    for (final dir in AppSettingsController.instance.musicScanPaths) {
      _filesByPath[dir] = await _scanPath(dir);
    }
    isScanning.value = false;
    await _saveCache();
  }

  Future<List<RichMusicFile>> _scanPath(String dirPath) async {
    final result = <RichMusicFile>[];
    try {
      final dir = Directory(dirPath);
      if (!await dir.exists()) return result;

      final files = <File>[];
      await for (final e in dir.list(recursive: true)) {
        if (e is File &&
            musicExtensions.contains(p.extension(e.path).toLowerCase())) {
          files.add(e);
        }
      }

      scanTotal.value    = files.length;
      scanProgress.value = 0;

      for (final file in files) {
        final stat     = await file.stat();
        final baseFile = MusicFile(file.path, p.basename(file.path), stat.size);

        AudioMetadata meta;
        try {
          meta = await AudioMetadataReader.readFile(file.path);
        } catch (_) {
          meta = const AudioMetadata();
        }

        // 注意：这里故意不读/不落盘封面。封面改为按"当前展示列表"
        // 分批增量加载(前 200 首，滚动到后面再加载下一个 200)，见
        // ensureCoversForCurrentView / onSongVisible，避免整个音乐库
        // 在扫描阶段就把所有封面读进内存或写入磁盘。
        result.add(RichMusicFile.fromMetadata(
          base:       baseFile,
          metaTitle:  meta.title,
          metaArtist: meta.artist,
          metaAlbum:  meta.album,
          modifiedMs: stat.modified.millisecondsSinceEpoch,
        ));

        scanProgress.value++;
        if (scanProgress.value % 20 == 0) {
          _filesByPath[dirPath] = List.from(result);
        }
      }
    } catch (_) {}
    return result;
  }

  // ── Actions ────────────────────────────────────────────────────────────────

  Future<void> addPath() async {
    final result = await FilePicker.platform.getDirectoryPath();
    if (result == null) return;
    await AppSettingsController.instance.addMusicScanPath(result);
    isScanning.value = true;
    _filesByPath[result] = await _scanPath(result);
    isScanning.value = false;
    await _saveCache();
    resetCoverBatchesAndReload();
  }

  Future<void> removePath(String path) async {
    await AppSettingsController.instance.removeMusicScanPath(path);
    _filesByPath.remove(path);
    if (selectedPath.value == path) selectedPath.value = '';
    drillGroup.value = null;
    await _saveCache();
    resetCoverBatchesAndReload();
  }

  Future<void> selectCategory(MusicCategory cat) async {
    category.value   = cat;
    drillGroup.value = null;
    await StorageService.setValue(StorageService.kMusicCategory, cat.name);
    // 切换分类后"当前展示列表"顺序完全变了，"前 200"需要重新计算。
    resetCoverBatchesAndReload();
  }

  void enterGroup(String name) {
    drillGroup.value = name;
    // 进入分组详情后展示的曲目列表变了(该分组内的曲目)，重新计算。
    resetCoverBatchesAndReload();
  }

  void exitGroup() {
    drillGroup.value = null;
    resetCoverBatchesAndReload();
  }

  void play(List<RichMusicFile> playlist, int index) {
    AppNavigator.toMusicPlayer(
      playlist: playlist.map((f) => f.toPlayMap()).toList(),
      index:    index,
    );
  }

  // ── Utils ──────────────────────────────────────────────────────────────────

  List<String> _splitArtists(String raw) {
    if (raw.isEmpty) return ['未知艺术家'];
    final normalized = raw
        .replaceAll(RegExp(r'\bfeat\.?\s*', caseSensitive: false), '|')
        .replaceAll(RegExp(r'\bft\.?\s*',   caseSensitive: false), '|')
        .replaceAll(RegExp(r'\bvs\.?\s*',   caseSensitive: false), '|')
        .replaceAll(RegExp(r'[/,&×·；、]'),                         '|');
    final parts = normalized.split('|')
        .map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    return parts.isEmpty ? ['未知艺术家'] : parts;
  }

  int _minTime(List<RichMusicFile> l) =>
      l.isEmpty ? 0 : l.map((f) => f.modifiedMs).reduce((a, b) => a < b ? a : b);
  int _maxTime(List<RichMusicFile> l) =>
      l.isEmpty ? 0 : l.map((f) => f.modifiedMs).reduce((a, b) => a > b ? a : b);
}

// ══════════════════════════════════════════════════════════════════════════════
//  Root Widget
// ══════════════════════════════════════════════════════════════════════════════

class MusicTabPage extends StatelessWidget {
  const MusicTabPage({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = Get.put(MusicLibraryController(), tag: 'music_lib');
    return _MusicShell(ctrl: ctrl);
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  Shell
// ══════════════════════════════════════════════════════════════════════════════

class _MusicShell extends StatelessWidget {
  final MusicLibraryController ctrl;
  const _MusicShell({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surface,
      body: Row(
        children: [
          _Sidebar(ctrl: ctrl),
          VerticalDivider(width: 1, thickness: 1,
              color: scheme.outlineVariant.withAlpha(60)),
          Expanded(child: _ContentArea(ctrl: ctrl)),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  Sidebar
// ══════════════════════════════════════════════════════════════════════════════

class _Sidebar extends StatelessWidget {
  final MusicLibraryController ctrl;
  const _Sidebar({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text   = Theme.of(context).textTheme;

    return SizedBox(
      width: 200,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 8, 6),
          child: Row(children: [
            Text('音乐库',
                style: text.labelLarge?.copyWith(color: scheme.onSurfaceVariant)),
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
          ]),
        ),
        Obx(() => _SidebarItem(
              icon: Icons.library_music_outlined,
              label: '全部音乐',
              count: ctrl.totalCount,
              selected: ctrl.selectedPath.value.isEmpty,
              onTap: () {
                ctrl.selectedPath.value = '';
                ctrl.drillGroup.value   = null;
                ctrl.resetCoverBatchesAndReload();
              },
            )),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: Divider(height: 1, color: scheme.outlineVariant.withAlpha(60)),
        ),
        Expanded(
          child: Obx(() {
            final paths = AppSettingsController.instance.musicScanPaths;
            if (paths.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: Text('点击右上角 + 添加路径',
                    style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                    textAlign: TextAlign.center),
              );
            }
            return ListView.builder(
              padding: EdgeInsets.zero,
              itemCount: paths.length,
              itemBuilder: (_, i) {
                final path  = paths[i];
                final count = ctrl._filesByPath[path]?.length ?? 0;
                return Obx(() => _SidebarItem(
                      icon:     Icons.folder_outlined,
                      label:    _lastName(path),
                      tooltip:  path,
                      count:    count,
                      selected: ctrl.selectedPath.value == path,
                      onTap: () {
                        ctrl.selectedPath.value = path;
                        ctrl.drillGroup.value   = null;
                        ctrl.resetCoverBatchesAndReload();
                      },
                      onRemove: () => ctrl.removePath(path),
                    ));
              },
            );
          }),
        ),
      ]),
    );
  }

  String _lastName(String path) {
    final parts = path.replaceAll('\\', '/').split('/');
    return parts.lastWhere((s) => s.isNotEmpty, orElse: () => path);
  }
}

// ── Sidebar Item ─────────────────────────────────────────────────────────────

class _SidebarItem extends StatefulWidget {
  final IconData icon;
  final String   label;
  final String?  tooltip;
  final int      count;
  final bool     selected;
  final VoidCallback  onTap;
  final VoidCallback? onRemove;

  const _SidebarItem({
    required this.icon, required this.label, this.tooltip,
    required this.count, required this.selected,
    required this.onTap, this.onRemove,
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
          child: Row(children: [
            Icon(widget.icon, size: 17,
                color: widget.selected ? scheme.primary : scheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(
              child: Text(widget.label,
                  style: text.bodySmall?.copyWith(
                    fontWeight: widget.selected ? FontWeight.w600 : FontWeight.normal,
                    color: widget.selected
                        ? scheme.onPrimaryContainer
                        : scheme.onSurface,
                  ),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(width: 4),
            if (_hovered && widget.onRemove != null)
              GestureDetector(
                onTap: widget.onRemove,
                child: Icon(Icons.close, size: 14, color: scheme.onSurfaceVariant),
              )
            else
              Text('${widget.count}',
                  style: text.labelSmall
                      ?.copyWith(color: scheme.onSurfaceVariant)),
          ]),
        ),
      ),
    );

    if (widget.tooltip != null) {
      child = Tooltip(message: widget.tooltip!, child: child);
    }
    return child;
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  Content Area
// ══════════════════════════════════════════════════════════════════════════════

class _ContentArea extends StatelessWidget {
  final MusicLibraryController ctrl;
  const _ContentArea({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text   = Theme.of(context).textTheme;

    return Column(children: [
      // Toolbar
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 6),
        child: Row(children: [
          // Breadcrumb
          Obx(() {
            final sel   = ctrl.selectedPath.value;
            final drill = ctrl.drillGroup.value;
            final pathLabel = sel.isEmpty ? '全部音乐' : _lastName(sel);
            if (drill != null) {
              return Row(mainAxisSize: MainAxisSize.min, children: [
                InkWell(
                  onTap: ctrl.exitGroup,
                  borderRadius: BorderRadius.circular(4),
                  child: Text(pathLabel,
                      style: text.titleSmall?.copyWith(color: scheme.primary)),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(Icons.chevron_right, size: 18,
                      color: scheme.onSurfaceVariant),
                ),
                Text(drill,
                    style: text.titleSmall?.copyWith(color: scheme.onSurface)),
              ]);
            }
            return Text(pathLabel,
                style: text.titleSmall?.copyWith(color: scheme.onSurface));
          }),

          const SizedBox(width: 8),

          // Count / scanning
          Obx(() {
            if (ctrl.isScanning.value) {
              return Text(
                '扫描中 ${ctrl.scanProgress.value}/${ctrl.scanTotal.value}',
                style: text.bodySmall?.copyWith(color: scheme.primary),
              );
            }
            final drill = ctrl.drillGroup.value;
            final count = drill != null
                ? ctrl.drillSongs.length
                : ctrl.category.value == MusicCategory.song
                    ? ctrl.sortedSongs.length
                    : ctrl.sortedGroups.length;
            final unit = (ctrl.category.value == MusicCategory.song ||
                    drill != null)
                ? '首'
                : ctrl.category.value == MusicCategory.album
                    ? '张专辑'
                    : '位歌手';
            return Text('$count $unit',
                style: text.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant));
          }),

          const Spacer(),

          // Search (song view or drilled)
          Obx(() {
            final showSearch = ctrl.category.value == MusicCategory.song ||
                ctrl.drillGroup.value != null;
            if (!showSearch) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(right: 4),
              child: SizedBox(
                width: 200, height: 34,
                child: TextField(
                  decoration: InputDecoration(
                    hintText: '搜索音乐...',
                    hintStyle: text.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                    prefixIcon: Icon(Icons.search, size: 17,
                        color: scheme.onSurfaceVariant),
                    isDense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(vertical: 8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: scheme.outlineVariant),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: scheme.outlineVariant),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide:
                          BorderSide(color: scheme.primary, width: 1.5),
                    ),
                  ),
                  onChanged: (v) {
                    ctrl.search.value = v;
                    ctrl.resetCoverBatchesAndReload();
                  },
                ),
              ),
            );
          }),

          // Refresh
          Tooltip(
            message: '重新扫描',
            child: IconButton(
              icon: Obx(() => ctrl.isScanning.value
                  ? SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: scheme.primary))
                  : const Icon(Icons.refresh, size: 20)),
              onPressed: ctrl.isScanning.value ? null : ctrl.refresh,
            ),
          ),

          // Category
          Obx(() => PopupMenuButton<MusicCategory>(
                tooltip: '分类',
                icon: const Icon(Icons.category_outlined, size: 20),
                initialValue: ctrl.category.value,
                onSelected: ctrl.selectCategory,
                itemBuilder: (_) => [
                  _catItem(MusicCategory.song,   '按歌曲',
                      Icons.music_note_outlined,  ctrl.category.value),
                  _catItem(MusicCategory.album,  '按专辑',
                      Icons.album_outlined,       ctrl.category.value),
                  _catItem(MusicCategory.artist, '按歌手',
                      Icons.person_outline,       ctrl.category.value),
                ],
              )),

          // Sort
          Obx(() {
            final inGroupRoot = ctrl.category.value != MusicCategory.song &&
                ctrl.drillGroup.value == null;
            if (inGroupRoot) {
              return PopupMenuButton<GroupSortMode>(
                tooltip: '排序',
                icon: const Icon(Icons.sort, size: 20),
                initialValue: ctrl.groupSort.value,
                onSelected: ctrl.setGroupSort,
                itemBuilder: (_) => [
                  _sortItem(GroupSortMode.nameAsc,  '按名称升序',   ctrl.groupSort.value),
                  _sortItem(GroupSortMode.nameDesc, '按名称降序',   ctrl.groupSort.value),
                  _sortItem(GroupSortMode.timeAsc,  '按修改时间升序', ctrl.groupSort.value),
                  _sortItem(GroupSortMode.timeDesc, '按修改时间降序', ctrl.groupSort.value),
                ],
              );
            }
            return PopupMenuButton<SongSortMode>(
              tooltip: '排序',
              icon: const Icon(Icons.sort, size: 20),
              initialValue: ctrl.songSort.value,
              onSelected: ctrl.setSongSort,
              itemBuilder: (_) => [
                _sortItem(SongSortMode.titleAsc,   '按歌曲名升序',  ctrl.songSort.value),
                _sortItem(SongSortMode.titleDesc,  '按歌曲名降序',  ctrl.songSort.value),
                _sortItem(SongSortMode.artistAsc,  '按艺术家升序',  ctrl.songSort.value),
                _sortItem(SongSortMode.artistDesc, '按艺术家降序',  ctrl.songSort.value),
                _sortItem(SongSortMode.timeAsc,    '按修改时间升序', ctrl.songSort.value),
                _sortItem(SongSortMode.timeDesc,   '按修改时间降序', ctrl.songSort.value),
              ],
            );
          }),
        ]),
      ),

      Divider(height: 1, color: scheme.outlineVariant.withAlpha(60)),

      // Main content
      Expanded(
        child: Obx(() {
          if (AppSettingsController.instance.musicScanPaths.isEmpty) {
            return _EmptyState(onAdd: ctrl.addPath);
          }
          if (ctrl.isScanning.value && ctrl.totalCount == 0) {
            return Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 12),
                Obx(() => Text(
                      '正在读取音频标签 ${ctrl.scanProgress.value}/${ctrl.scanTotal.value}',
                      style: text.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant))),
              ]),
            );
          }
          if (ctrl.category.value == MusicCategory.song) {
            return _SongListView(ctrl: ctrl, songs: ctrl.sortedSongs);
          }
          final drill = ctrl.drillGroup.value;
          if (drill == null) {
            return _GroupListView(ctrl: ctrl);
          } else {
            return _SongListView(ctrl: ctrl, songs: ctrl.drillSongs);
          }
        }),
      ),
    ]);
  }

  PopupMenuItem<MusicCategory> _catItem(
      MusicCategory value, String label, IconData icon, MusicCategory current) {
    return PopupMenuItem(
      value: value,
      child: Row(children: [
        Icon(icon, size: 16),
        const SizedBox(width: 8),
        Text(label),
        if (current == value) ...[const Spacer(), const Icon(Icons.check, size: 14)],
      ]),
    );
  }

  PopupMenuItem<T> _sortItem<T>(T value, String label, T current) {
    return PopupMenuItem(
      value: value,
      child: Row(children: [
        Text(label),
        if (current == value) ...[const Spacer(), const Icon(Icons.check, size: 14)],
      ]),
    );
  }

  String _lastName(String path) {
    final parts = path.replaceAll('\\', '/').split('/');
    return parts.lastWhere((s) => s.isNotEmpty, orElse: () => path);
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  Song List View
// ══════════════════════════════════════════════════════════════════════════════

class _SongListView extends StatelessWidget {
  final MusicLibraryController ctrl;
  final List<RichMusicFile>    songs;
  const _SongListView({required this.ctrl, required this.songs});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (songs.isEmpty) {
      return Center(
        child: Text('未找到音乐文件',
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: scheme.onSurfaceVariant)));
    }
    // 兜底：确保前 200 首封面已在加载中(分类/排序/搜索/目录切换已经在
    // 各自入口触发过，这里避免遗漏路径，例如页面首次构建)。
    ctrl.ensureCoversForCurrentView();
    return ListView.builder(
      itemCount: songs.length,
      itemBuilder: (_, i) {
        final f   = songs[i];
        final ext = p.extension(f.name).replaceFirst('.', '').toUpperCase();
        // 滚动到还没加载封面的位置时，触发下一批 200 的增量加载。
        if (f.coverBytes == null) {
          ctrl.onSongVisible(i);
        }
        return _TrackTile(
          key: ValueKey(f.path),
          index:  i + 1,
          title:  f.title,
          artist: f.artist,
          album:  f.album,
          format: ext,
          // 封面改为内存态字节(不落盘)：coverBytes 为 null 表示尚未
          // 加载 / 没有内嵌封面 / 读取失败，统一退回默认音符图标。
          coverBytes: f.coverBytes,
          // 用 f 反查它在 songs 里的真实下标再播放，避免 ListView 复用/
          // 响应式列表重算导致"点击这一项却播放了下一项"的错位问题。
          onTap:  () {
            final idx = songs.indexOf(f);
            ctrl.play(songs, idx >= 0 ? idx : i);
          },
        );
      },
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  Group List View
// ══════════════════════════════════════════════════════════════════════════════

class _GroupListView extends StatelessWidget {
  final MusicLibraryController ctrl;
  const _GroupListView({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    final scheme  = Theme.of(context).colorScheme;
    final entries = ctrl.sortedGroups;
    final isAlbum = ctrl.category.value == MusicCategory.album;

    if (entries.isEmpty) {
      return Center(
        child: Text('未找到音乐文件',
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: scheme.onSurfaceVariant)));
    }
    return ListView.builder(
      itemCount: entries.length,
      itemBuilder: (_, i) {
        final e = entries[i];
        return _GroupTile(
          name:    e.key,
          count:   e.value.length,
          isAlbum: isAlbum,
          onTap:   () => ctrl.enterGroup(e.key),
        );
      },
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  Track Tile
// ══════════════════════════════════════════════════════════════════════════════

class _TrackTile extends StatefulWidget {
  final int    index;
  final String title;
  final String artist;
  final String album;
  final String format;
  final Uint8List? coverBytes;
  final VoidCallback onTap;

  const _TrackTile({
    super.key,
    required this.index,  required this.title,  required this.artist,
    required this.album,  required this.format, required this.onTap,
    this.coverBytes,
  });

  @override
  State<_TrackTile> createState() => _TrackTileState();
}

class _TrackTileState extends State<_TrackTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final coverBytes = widget.coverBytes;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      child: InkWell(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          color: _hovered
              ? scheme.primaryContainer.withAlpha(60)
              : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(children: [
            SizedBox(
              width: 36,
              child: Center(
                child: _hovered
                    ? Icon(Icons.play_arrow, size: 20, color: scheme.primary)
                    : Text('${widget.index}',
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                        textAlign: TextAlign.center),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: scheme.tertiaryContainer.withAlpha(80),
                borderRadius: BorderRadius.circular(6),
              ),
              clipBehavior: Clip.antiAlias,
              child: (coverBytes != null && coverBytes.isNotEmpty)
                  ? Image.memory(
                      coverBytes,
                      width: 36, height: 36,
                      fit: BoxFit.cover,
                      // 内存数据本身解码失败(极少见的损坏图片)时退回
                      // 音符图标，不让整个列表因为一张坏图崩溃。
                      errorBuilder: (_, __, ___) =>
                          Icon(Icons.music_note, size: 20, color: scheme.tertiary),
                    )
                  : Icon(Icons.music_note, size: 20, color: scheme.tertiary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(widget.title,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium),
                  if (widget.artist.isNotEmpty || widget.album.isNotEmpty)
                    Text(
                      [widget.artist, widget.album]
                          .where((s) => s.isNotEmpty)
                          .join(' · '),
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(widget.format,
                  style: Theme.of(context).textTheme.labelSmall
                      ?.copyWith(color: scheme.onSurfaceVariant)),
            ),
          ]),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  Group Tile
// ══════════════════════════════════════════════════════════════════════════════

class _GroupTile extends StatefulWidget {
  final String name;
  final int    count;
  final bool   isAlbum;
  final VoidCallback onTap;

  const _GroupTile({
    required this.name, required this.count,
    required this.isAlbum, required this.onTap,
  });

  @override
  State<_GroupTile> createState() => _GroupTileState();
}

class _GroupTileState extends State<_GroupTile> {
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
          duration: const Duration(milliseconds: 120),
          color: _hovered
              ? scheme.primaryContainer.withAlpha(60)
              : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: scheme.secondaryContainer.withAlpha(100),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                widget.isAlbum ? Icons.album_outlined : Icons.person_outline,
                size: 22, color: scheme.secondary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(widget.name,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium),
            ),
            Text('${widget.count} 首',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, size: 18, color: scheme.onSurfaceVariant),
          ]),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  Empty State
// ══════════════════════════════════════════════════════════════════════════════

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.library_music_outlined, size: 72,
            color: scheme.onSurfaceVariant.withAlpha(100)),
        const SizedBox(height: 16),
        Text('没有音乐库路径', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text('在左侧点击 + 添加本地文件夹',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant)),
        const SizedBox(height: 24),
        FilledButton.icon(
          icon: const Icon(Icons.create_new_folder_outlined, size: 18),
          label: const Text('添加音乐库路径'),
          onPressed: onAdd,
        ),
      ]),
    );
  }
}
