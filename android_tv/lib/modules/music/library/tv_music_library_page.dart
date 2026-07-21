import 'dart:typed_data';

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

// 音乐分类
class _MusicCategory {
  static const int song = 0;
  static const int album = 1;
  static const int artist = 2;
  static const int folder = 3;
  const _MusicCategory._();
}

// 歌曲排序
class _MusicSongSort {
  static const int titleAsc = 0;
  static const int titleDesc = 1;
  static const int artistAsc = 2;
  static const int artistDesc = 3;
  static const int timeAsc = 4;
  static const int timeDesc = 5;
  const _MusicSongSort._();
}

// 分组排序
class _MusicGroupSort {
  static const int nameAsc = 10;
  static const int nameDesc = 11;
  static const int timeAsc = 12;
  static const int timeDesc = 13;
  const _MusicGroupSort._();
}

// SongEntry(歌曲项)现由 player_shared 提供(手机端与 TV 端共用),
// 详见 package:player_shared/src/music/song_entry.dart。

// 分组项(专辑 / 艺术家 / 文件夹)
class _GroupEntry {
  final String key;
  final String displayName;
  final List<SongEntry> songs;
  const _GroupEntry({
    required this.key,
    required this.displayName,
    required this.songs,
  });
}

class TvMusicLibraryController extends GetxController {
  final files = <SongEntry>[].obs;
  final isScanning = false.obs;
  final scanStatus = ''.obs;
  final metaLoadCount = 0.obs;

  final currentCategory = _MusicCategory.song.obs;
  final currentSortSong = _MusicSongSort.titleAsc.obs;
  final currentSortGroup = _MusicGroupSort.nameAsc.obs;
  // 分组歌曲列表模式:空 = 显示分组列表,非空 = 显示该分组的歌曲
  final selectedGroup = ''.obs;

  bool _metaLoading = false;
  bool _disposed = false;

  /// 封面内存缓存 + 分批增量加载器(TV 端与手机端统一策略)：只读当前
  /// 展示列表的前 200 首封面，滚动到还没加载的位置再整批加载下一个
  /// 200，不落盘。
  late final AudioCoverMemoryCache<SongEntry> _coverCache =
      AudioCoverMemoryCache<SongEntry>(
    batchSize: 200,
    pathOf: (s) => s.path,
    hasCover: (s) => s.coverBytes != null,
    applyCover: (s, meta) => s.coverBytes = meta.coverBytes,
  );

  @override
  void onInit() {
    super.onInit();
    _loadCategoryAndSort();
    _init();
  }

  @override
  void onClose() {
    _disposed = true;
    _coverCache.dispose();
    super.onClose();
  }

  /// 进入音乐页时的启动逻辑:
  /// - 若本地已有缓存的歌曲数据,直接从缓存恢复展示,不接触磁盘、不重新扫描。
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
      scanStatus.value = '共 ${files.length} 首';
      // coverBytes 不落盘缓存，从缓存恢复的歌曲此时封面字段都是
      // null，需要单独触发一次"只读前 200 首封面"的分批加载。
      ensureCoversForCurrentView();
      return;
    }
    await scanAll();
  }

  // ── 分类 / 排序持久化 ─────────────────────────────────────────────────────

  void _loadCategoryAndSort() {
    currentCategory.value =
        _loadIntPref(StorageService.kMusicCategory, _MusicCategory.song);
    currentSortSong.value = _loadIntPref(
        StorageService.kMusicSongSort, _MusicSongSort.titleAsc);
    currentSortGroup.value = _loadIntPref(
        StorageService.kMusicGroupSort, _MusicGroupSort.nameAsc);
  }

  int _loadIntPref(String key, int fallback) {
    try {
      return StorageService.getValue<int>(key, fallback);
    } catch (_) {
      return fallback;
    }
  }

  // ── 扫描结果缓存持久化 ────────────────────────────────────────────────────

  List<SongEntry>? _loadCache() {
    try {
      final raw = StorageService.getValue<List>(
          StorageService.kMusicLibraryCacheTv, const []);
      if (raw.isEmpty) return null;
      return raw
          .map((e) => SongEntry.fromJson(Map<dynamic, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveCache() async {
    final raw = files.map((s) => s.toJson()).toList();
    await StorageService.setValue(StorageService.kMusicLibraryCacheTv, raw);
  }

  // 全量扫描:先确认权限,再全局扫描本地目录,扫描完成后写入缓存
  Future<void> scanAll() async {
    final granted = await PermissionUtil.requestMediaPermissions();
    if (!granted) {
      scanStatus.value = '未获得存储权限,无法扫描';
      return;
    }
    isScanning.value = true;
    metaLoadCount.value = 0;
    selectedGroup.value = '';
    _coverCache.reset();
    try {
      final result = await LocalScanner.scanAudios();
      files.assignAll(result
          .map((a) => SongEntry.fromScan(
                path: a.path,
                name: a.name,
                folder: a.folder,
                size: a.size,
                modified: a.modified,
              ))
          .toList());
    } catch (_) {}
    isScanning.value = false;
    scanStatus.value = '共 ${files.length} 首';
    // 后台异步加载元数据(标题/歌手/专辑/歌词),加载完成后落盘缓存。
    // 封面不在这里加载——封面改为按"当前展示列表"分批增量加载，
    // 见 ensureCoversForCurrentView / onSongVisible。
    await _loadMetadataInBackground();
  }

  Future<void> _loadMetadataInBackground() async {
    if (_metaLoading) return;
    _metaLoading = true;
    for (int i = 0; i < files.length; i++) {
      if (_disposed) break;
      final s = files[i];
      if (s.metadataLoaded) continue;
      try {
        final meta = await AudioMetadataReader.readFile(s.path);
        s.metadataLoaded = true;
        if (meta.title != null && meta.title!.isNotEmpty) {
          s.title = meta.title!;
        }
        s.artist = meta.artist ?? '';
        s.album = meta.album ?? '';
        s.lyrics = meta.lyrics ?? '';
        // 注意：这里故意不读封面。封面改为只为"当前展示列表"分批
        // 增量加载(前 200 首，滚动到后面再加载下一个 200)。
        files.refresh();
        metaLoadCount.value++;
        if (metaLoadCount.value % 20 == 0) {
          await _saveCache();
        }
      } catch (_) {
        s.metadataLoaded = true;
      }
      await Future.delayed(Duration.zero);
    }
    _metaLoading = false;
    if (!_disposed) {
      await _saveCache();
    }
    // 元数据加载完成后，当前展示列表顺序可能已经变化，补一次首批
    // 封面加载。
    ensureCoversForCurrentView();
  }

  /// 触发响应式更新，供封面分批加载器在每首歌加载完成后调用。
  void _refreshFiles() => files.refresh();

  /// 当前展示列表：与 [currentSongs] 保持完全一致的顺序/内容——
  /// 歌曲分类下是全库排序结果；专辑/艺术家/文件夹分类下，若已经点进了
  /// 某个具体分组，则只是该分组内的歌曲(按当前排序)；若还停留在分组
  /// 卡片列表(没有 selectedGroup)，此时页面本身不展示任何歌曲封面，
  /// 返回空列表即可(卡片本身没有封面图，不需要分批加载)。
  List<SongEntry> _currentOrderedSongs() => currentSongs();

  /// 确保"当前展示列表"的前 200 首封面已加载。在列表首次展示、
  /// 分类/排序切换、从缓存恢复后调用。
  void ensureCoversForCurrentView() {
    _coverCache.ensureFirstBatch(_currentOrderedSongs(), onProgress: _refreshFiles);
  }

  /// 列表滚动到索引 [visibleIndex] 但该位置还没有封面时调用：按 200 首
  /// 为一批整批增量加载(200→400→600…)，不是逐条懒加载。
  void onSongVisible(int visibleIndex) {
    _coverCache.ensureVisible(visibleIndex, _currentOrderedSongs(),
        onProgress: _refreshFiles);
  }

  Future<void> setCategory(int c) async {
    currentCategory.value = c;
    selectedGroup.value = '';
    await StorageService.setValue(StorageService.kMusicCategory, c);
    // 切换分类后"当前展示列表"顺序完全变了，"前 200"需要重新计算。
    _coverCache.reset();
    ensureCoversForCurrentView();
  }

  Future<void> setSortSong(int s) async {
    currentSortSong.value = s;
    await StorageService.setValue(StorageService.kMusicSongSort, s);
    _coverCache.reset();
    ensureCoversForCurrentView();
  }

  Future<void> setSortGroup(int s) async {
    currentSortGroup.value = s;
    await StorageService.setValue(StorageService.kMusicGroupSort, s);
    _coverCache.reset();
    ensureCoversForCurrentView();
  }

  void openGroup(_GroupEntry e) {
    selectedGroup.value = e.key;
    // 进入分组后展示的歌曲列表变了(该分组内的歌曲，而不是全库列表)，
    // "前 200"需要按分组内列表重新计算。
    _coverCache.reset();
    ensureCoversForCurrentView();
  }
  void backToGroups() {
    selectedGroup.value = '';
    _coverCache.reset();
    ensureCoversForCurrentView();
  }

  // 排序后的歌曲列表(歌曲分类下使用)
  List<SongEntry> sortedSongs() {
    final list = files.toList();
    switch (currentSortSong.value) {
      case _MusicSongSort.titleDesc:
        list.sort((a, b) =>
            b.title.toLowerCase().compareTo(a.title.toLowerCase()));
        break;
      case _MusicSongSort.artistAsc:
        list.sort((a, b) =>
            a.artist.toLowerCase().compareTo(b.artist.toLowerCase()));
        break;
      case _MusicSongSort.artistDesc:
        list.sort((a, b) =>
            b.artist.toLowerCase().compareTo(a.artist.toLowerCase()));
        break;
      case _MusicSongSort.timeAsc:
        list.sort((a, b) => a.modified.compareTo(b.modified));
        break;
      case _MusicSongSort.timeDesc:
        list.sort((a, b) => b.modified.compareTo(a.modified));
        break;
      default:
        list.sort((a, b) =>
            a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    }
    return list;
  }

  List<String> _splitArtists(String artist) => ArtistSplitter.split(artist);

  // 按当前分类构建分组列表
  List<_GroupEntry> buildGroups() {
    final cat = currentCategory.value;
    final map = <String, List<SongEntry>>{};
    for (final s in files) {
      if (cat == _MusicCategory.album) {
        final k = s.album.isEmpty ? '未知专辑' : s.album;
        map.putIfAbsent(k, () => []).add(s);
      } else if (cat == _MusicCategory.artist) {
        final artists = _splitArtists(s.artist);
        for (final artist in artists) {
          map.putIfAbsent(artist, () => []).add(s);
        }
      } else {
        // 文件夹分组:按文件所在目录路径
        final k = s.folder.isNotEmpty ? s.folder : '/';
        map.putIfAbsent(k, () => []).add(s);
      }
    }
    return map.entries.map((e) {
      final display = cat == _MusicCategory.folder
          ? (p.basename(e.key).isNotEmpty ? p.basename(e.key) : e.key)
          : e.key;
      return _GroupEntry(key: e.key, displayName: display, songs: e.value);
    }).toList();
  }

  // 排序后的分组列表
  List<_GroupEntry> sortedGroups() {
    final list = buildGroups();
    switch (currentSortGroup.value) {
      case _MusicGroupSort.nameDesc:
        list.sort((a, b) => b.displayName
            .toLowerCase()
            .compareTo(a.displayName.toLowerCase()));
        break;
      case _MusicGroupSort.timeAsc:
        list.sort((a, b) {
          final aMin = a.songs.map((s) => s.modified).reduce(_min);
          final bMin = b.songs.map((s) => s.modified).reduce(_min);
          return aMin.compareTo(bMin);
        });
        break;
      case _MusicGroupSort.timeDesc:
        list.sort((a, b) {
          final aMax = a.songs.map((s) => s.modified).reduce(_max);
          final bMax = b.songs.map((s) => s.modified).reduce(_max);
          return bMax.compareTo(aMax);
        });
        break;
      default:
        list.sort((a, b) => a.displayName
            .toLowerCase()
            .compareTo(b.displayName.toLowerCase()));
    }
    return list;
  }

  static int _min(int a, int b) => a < b ? a : b;
  static int _max(int a, int b) => a > b ? a : b;

  // 当前显示的歌曲列表(歌曲分类或分组内歌曲)
  List<SongEntry> currentSongs() {
    if (currentCategory.value == _MusicCategory.song) {
      return sortedSongs();
    }
    if (selectedGroup.value.isEmpty) return [];
    final groups = buildGroups();
    for (final g in groups) {
      if (g.key == selectedGroup.value) {
        final list = List<SongEntry>.from(g.songs);
        switch (currentSortSong.value) {
          case _MusicSongSort.titleDesc:
            list.sort((a, b) =>
                b.title.toLowerCase().compareTo(a.title.toLowerCase()));
            break;
          case _MusicSongSort.timeAsc:
            list.sort((a, b) => a.modified.compareTo(b.modified));
            break;
          case _MusicSongSort.timeDesc:
            list.sort((a, b) => b.modified.compareTo(a.modified));
            break;
          default:
            list.sort((a, b) =>
                a.title.toLowerCase().compareTo(b.title.toLowerCase()));
        }
        return list;
      }
    }
    return [];
  }

  // 点击播放:进入全屏播放页
  void playSong(SongEntry s) {
    final list = currentSongs();
    final idx = list.indexWhere((e) => e.path == s.path);
    TvNavigator.toMusicPlayer(
      playlist: list.map((e) => e.toMap()).toList(),
      index: idx < 0 ? 0 : idx,
    );
  }
}

class TvMusicLibraryPage extends StatelessWidget {
  const TvMusicLibraryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = Get.put(TvMusicLibraryController());
    return Obx(() => Scaffold(
          backgroundColor: TvColors.background,
          body: Column(
            children: [
              _buildTopBar(context, ctrl),
              Container(height: 1, color: TvColors.divider),
              _buildCategoryBar(context, ctrl),
              Container(height: 1, color: TvColors.divider),
              Expanded(child: _buildBody(context, ctrl)),
            ],
          ),
        ));
  }

  // 顶栏:返回 + 标题 + 操作(排序 / 刷新 / 添加路径)
  Widget _buildTopBar(BuildContext context, TvMusicLibraryController ctrl) {
    return Container(
      height: 96.w,
      padding: EdgeInsets.symmetric(horizontal: 32.w),
      color: TvColors.surface,
      child: Row(
        children: [
          Text('音乐', style: TvStyle.titleMedium),
          // 分组歌曲列表模式下显示"返回分组"
          Obx(() => ctrl.selectedGroup.value.isNotEmpty
              ? Padding(
                  padding: EdgeInsets.only(left: 16.w),
                  child: _TopBarButton(
                    icon: Icons.folder_open,
                    label: '返回分组',
                    onTap: ctrl.backToGroups,
                  ),
                )
              : const SizedBox.shrink()),
          const Spacer(),
          const TvPlaybackEntry(),
          SizedBox(width: 16.w),
          _TopBarButton(
            icon: Icons.sort,
            label: '排序',
            onTap: () => _showSortDialog(context, ctrl),
          ),
          SizedBox(width: 12.w),
          Obx(() => _TopBarButton(
                icon: Icons.refresh,
                label: ctrl.isScanning.value ? '扫描中' : '刷新',
                onTap: ctrl.isScanning.value ? null : ctrl.scanAll,
              )),
        ],
      ),
    );
  }

  // 分类标签栏:歌曲 / 专辑 / 艺术家 / 文件夹
  Widget _buildCategoryBar(BuildContext context, TvMusicLibraryController ctrl) {
    final tabs = ['歌曲', '专辑', '艺术家', '文件夹'];
    return Container(
      height: 80.w,
      color: TvColors.background,
      padding: EdgeInsets.symmetric(horizontal: 32.w),
      child: Row(
        children: [
          for (int i = 0; i < tabs.length; i++) ...[
            if (i > 0) SizedBox(width: 8.w),
            Obx(() => _CategoryTab(
                  label: tabs[i],
                  selected: ctrl.currentCategory.value == i,
                  onTap: () => ctrl.setCategory(i),
                )),
          ],
          const Spacer(),
          Obx(() => Text(ctrl.scanStatus.value, style: TvStyle.labelSmall)),
        ],
      ),
    );
  }

  // 主体内容
  Widget _buildBody(BuildContext context, TvMusicLibraryController ctrl) {
    return Obx(() {
      // 扫描中且无文件
      if (ctrl.isScanning.value && ctrl.files.isEmpty) {
        return const Center(child: CircularProgressIndicator());
      }
      // 无文件
      if (ctrl.files.isEmpty) {
        return _buildEmpty();
      }
      // 歌曲分类:直接显示歌曲网格
      if (ctrl.currentCategory.value == _MusicCategory.song) {
        final list = ctrl.sortedSongs();
        if (list.isEmpty) return _buildEmpty();
        // 兜底：确保前 200 首封面已在加载中(分类/排序/进组切换已经在
        // 各自入口触发过，这里避免遗漏路径)。
        ctrl.ensureCoversForCurrentView();
        return _buildSongGrid(ctrl, list);
      }
      // 分组分类
      if (ctrl.selectedGroup.value.isEmpty) {
        // 显示分组卡片
        final groups = ctrl.sortedGroups();
        if (groups.isEmpty) return _buildEmpty();
        return _buildGroupGrid(ctrl, groups);
      }
      // 显示选中分组的歌曲
      final songs = ctrl.currentSongs();
      if (songs.isEmpty) return _buildEmpty();
      ctrl.ensureCoversForCurrentView();
      return _buildSongGrid(ctrl, songs);
    });
  }

  // 歌曲卡片网格
  Widget _buildSongGrid(TvMusicLibraryController ctrl, List<SongEntry> list) {
    return GridView.builder(
      padding: EdgeInsets.all(16.w),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 5,
        mainAxisSpacing: 16.w,
        crossAxisSpacing: 16.w,
        childAspectRatio: 1.0,
      ),
      itemCount: list.length,
      itemBuilder: (_, i) {
        // 滚动到还没加载封面的位置时，触发下一批 200 的增量加载。
        if (list[i].coverBytes == null) {
          ctrl.onSongVisible(i);
        }
        return _SongCard(
          song: list[i],
          autofocus: i == 0,
          onTap: () => ctrl.playSong(list[i]),
        );
      },
    );
  }

  // 分组卡片网格
  Widget _buildGroupGrid(
      TvMusicLibraryController ctrl, List<_GroupEntry> list) {
    return GridView.builder(
      padding: EdgeInsets.all(16.w),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 5,
        mainAxisSpacing: 16.w,
        crossAxisSpacing: 16.w,
        childAspectRatio: 1.0,
      ),
      itemCount: list.length,
      itemBuilder: (_, i) => _GroupCard(
        group: list[i],
        category: ctrl.currentCategory.value,
        autofocus: i == 0,
        onTap: () => ctrl.openGroup(list[i]),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.music_off, size: 80.w, color: TvColors.textSecondary),
          TvStyle.vGap16,
          Text('未找到音乐文件', style: TvStyle.bodyLarge),
        ],
      ),
    );
  }

  // 排序对话框:歌曲模式用歌曲排序,分组列表模式用分组排序
  void _showSortDialog(BuildContext context, TvMusicLibraryController ctrl) {
    if (ctrl.currentCategory.value == _MusicCategory.song ||
        ctrl.selectedGroup.value.isNotEmpty) {
      _showOptionDialog(
        context,
        '选择排序',
        ['标题升序', '标题降序', '歌手升序', '歌手降序', '修改时间升序', '修改时间降序'],
        ctrl.currentSortSong.value,
        ctrl.setSortSong,
      );
    } else {
      _showOptionDialog(
        context,
        '选择排序',
        ['名称升序', '名称降序', '修改时间升序', '修改时间降序'],
        ctrl.currentSortGroup.value - 10,
        (v) => ctrl.setSortGroup(v + 10),
      );
    }
  }
}

// 歌曲卡片(遥控器可聚焦)
class _SongCard extends StatefulWidget {
  final SongEntry song;
  final bool autofocus;
  final VoidCallback onTap;
  const _SongCard({
    required this.song,
    required this.autofocus,
    required this.onTap,
  });
  @override
  State<_SongCard> createState() => _SongCardState();
}

class _SongCardState extends State<_SongCard> {
  final _focus = TvFocusNode();
  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ext = p
        .extension(widget.song.name)
        .replaceFirst('.', '')
        .toUpperCase();
    // 封面改为内存态字节(不落盘)：coverBytes 为 null 表示尚未加载/
    // 没有内嵌封面/读取失败，统一退回默认音符图标。
    final coverBytes = widget.song.coverBytes;
    return TvHighlight(
      focusNode: _focus,
      autofocus: widget.autofocus,
      onTap: widget.onTap,
      borderRadius: TvStyle.radius12,
      child: Container(
        padding: EdgeInsets.all(16.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 封面图 / 音符图标区域(填充满可用高度)
            Expanded(
              child: Container(
                width: double.infinity,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: TvColors.accent.withAlpha(40),
                  borderRadius: TvStyle.radius8,
                ),
                child: (coverBytes == null || coverBytes.isEmpty)
                    ? Center(
                        child: Icon(Icons.music_note,
                            size: 64.w, color: TvColors.accent),
                      )
                    : Image.memory(
                        coverBytes,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Center(
                          child: Icon(Icons.music_note,
                              size: 64.w, color: TvColors.accent),
                        ),
                      ),
              ),
            ),
            SizedBox(height: 12.w),
            Text(
              widget.song.title,
              style: TvStyle.bodyMedium,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            SizedBox(height: 4.w),
            Text(ext, style: TvStyle.labelSmall),
          ],
        ),
      ),
    );
  }
}

// 分组卡片(遥控器可聚焦)
class _GroupCard extends StatefulWidget {
  final _GroupEntry group;
  final int category;
  final bool autofocus;
  final VoidCallback onTap;
  const _GroupCard({
    required this.group,
    required this.category,
    required this.autofocus,
    required this.onTap,
  });
  @override
  State<_GroupCard> createState() => _GroupCardState();
}

class _GroupCardState extends State<_GroupCard> {
  final _focus = TvFocusNode();
  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 根据分类切换图标
    final icon = widget.category == _MusicCategory.album
        ? Icons.album
        : widget.category == _MusicCategory.artist
            ? Icons.person
            : Icons.folder;
    return TvHighlight(
      focusNode: _focus,
      autofocus: widget.autofocus,
      onTap: widget.onTap,
      borderRadius: TvStyle.radius12,
      child: Container(
        padding: EdgeInsets.all(16.w),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 64.w, color: TvColors.accent),
            SizedBox(height: 12.w),
            Text(
              widget.group.displayName,
              style: TvStyle.bodyMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            SizedBox(height: 4.w),
            Text('${widget.group.songs.length} 首', style: TvStyle.labelSmall),
          ],
        ),
      ),
    );
  }
}

// 分类标签(遥控器可聚焦)
class _CategoryTab extends StatefulWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _CategoryTab({
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
          ? TvColors.accent.withAlpha(60)
          : Colors.transparent,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 12.w),
        child: Text(
          widget.label,
          style: widget.selected
              ? TvStyle.bodyMedium.copyWith(
                  color: TvColors.accent, fontWeight: FontWeight.w600)
              : TvStyle.bodyMedium,
        ),
      ),
    );
  }
}

// 顶栏按钮(遥控器可聚焦)
class _TopBarButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  const _TopBarButton({
    required this.icon,
    required this.label,
    this.onTap,
  });
  @override
  State<_TopBarButton> createState() => _TopBarButtonState();
}

class _TopBarButtonState extends State<_TopBarButton> {
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
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.w),
        child: Row(
          children: [
            Icon(widget.icon, size: 24.w, color: TvColors.accent),
            SizedBox(width: 8.w),
            Text(widget.label, style: TvStyle.bodyMedium),
          ],
        ),
      ),
    );
  }
}

// 选项对话框中的选项行(遥控器可聚焦)
class _OptionItem extends StatefulWidget {
  final String label;
  final bool selected;
  final bool autofocus;
  final VoidCallback onTap;
  const _OptionItem({
    required this.label,
    required this.selected,
    required this.autofocus,
    required this.onTap,
  });
  @override
  State<_OptionItem> createState() => _OptionItemState();
}

class _OptionItemState extends State<_OptionItem> {
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
      color: widget.selected
          ? TvColors.primary.withAlpha(40)
          : Colors.transparent,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 14.w),
        child: Row(
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
    );
  }
}

// 通用单选对话框(用 TvHighlight 包裹选项,支持遥控器)
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
          children: [
            for (int i = 0; i < options.length; i++) ...[
              if (i > 0) SizedBox(height: 4.w),
              _OptionItem(
                label: options[i],
                selected: i == selected,
                autofocus: i == 0,
                onTap: () {
                  Get.back();
                  onSelect(i);
                },
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
