import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as p;
// iOS 沙盒无法像 Android 那样遍历整个设备存储，隐藏共享包里的
// `LocalScanner`（全盘扫描实现），改用本 App 内基于"已授权目录书签"的
// `IosLocalScanner`，两者对外接口一致。
import 'package:player_shared/player_shared.dart' hide LocalScanner;

import 'package:nexus_ios/app/routes.dart';
import 'package:nexus_ios/widgets/option_dialog.dart';
import 'package:nexus_ios/widgets/search_dialog.dart';
import 'package:nexus_ios/scanner/ios_local_scanner.dart';

/// 音乐分类。
class MusicCategory {
  static const int song = 0;
  static const int album = 1;
  static const int artist = 2;
  static const int folder = 3;
  const MusicCategory._();
}

/// 歌曲排序。
class MusicSongSort {
  static const int titleAsc = 0;
  static const int titleDesc = 1;
  static const int artistAsc = 2;
  static const int artistDesc = 3;
  static const int timeAsc = 4;
  static const int timeDesc = 5;
  const MusicSongSort._();
}

/// 分组排序。
class MusicGroupSort {
  static const int nameAsc = 10;
  static const int nameDesc = 11;
  static const int timeAsc = 12;
  static const int timeDesc = 13;
  const MusicGroupSort._();
}

// SongEntry(歌曲项)现由 player_shared 提供(手机端与 TV 端共用),
// 详见 package:player_shared/src/music/song_entry.dart。

/// 分组项(专辑 / 艺术家 / 文件夹)。
class MusicGroupEntry {
  final String key;
  final String displayName;
  final List<SongEntry> songs;
  const MusicGroupEntry({
    required this.key,
    required this.displayName,
    required this.songs,
  });
}

class MusicLibraryController extends GetxController {
  static MusicLibraryController get instance =>
      Get.find<MusicLibraryController>(tag: 'music_library');

  final RxList<SongEntry> allSongs = <SongEntry>[].obs;
  final RxBool isScanning = false.obs;
  final RxBool hasPermission = false.obs;
  final RxBool permissionRequested = false.obs;
  final RxInt metaLoadCount = 0.obs;

  final RxInt currentCategory = MusicCategory.song.obs;
  final RxInt currentSortSong = MusicSongSort.titleAsc.obs;
  final RxInt currentSortGroup = MusicGroupSort.nameAsc.obs;

  /// 搜索关键字：只在当前展示层级内按名称模糊过滤（歌曲名 / 分组名），
  /// 不递归子分组，与分类/排序一样是纯前端过滤，不触发重新扫描磁盘。
  final RxString searchKeyword = ''.obs;

  bool _metaLoading = false;
  bool _disposed = false;

  /// 封面内存缓存 + 分批增量加载器:首批只读当前列表(按当前分类/排序
  /// 结果)的前 200 首封面;用户滚动到还没加载的位置时,再整批加载
  /// 下一个 200(200→400→600…),不是"前 200 后懒加载单条"。
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
  /// - 若没有缓存(首次安装 / 用户清空过数据),检查是否已有授权目录,
  ///   有则扫描一次,扫描完成后写入缓存。
  /// 之后除非用户点击"刷新"按钮,否则不会再自动重新扫描。
  ///
  /// 注意:iOS 沙盒没有"存储权限"这个概念,`hasPermission` 复用为"是否
  /// 至少有一个已授权且可访问的目录",空状态下引导用户去"管理目录"页
  /// 添加,而不是像 Android 端那样弹系统权限对话框。
  Future<void> _init() async {
    final has = await IosLocalScanner.hasAnyDirectory();
    hasPermission.value = has;
    permissionRequested.value = true;
    if (!has) return;

    final cached = _loadCache();
    if (cached != null && cached.isNotEmpty) {
      allSongs.assignAll(cached);
      // coverBytes 不落盘缓存(见 SongEntry.toJson 的注释)，从缓存恢复
      // 的歌曲此时封面字段都是 null，需要单独触发一次"只读前 200 首
      // 封面"的分批加载；标题/歌手/专辑/歌词已经在缓存里，不需要重新
      // 读一遍文件。
      ensureCoversForCurrentView();
      return;
    }
    await scanAll();
  }


  /// 触发重新扫描（原"刷新"按钮的功能，现由设置页"扫描音乐"入口调用）：
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
        _loadIntPref(StorageService.kMusicCategory, MusicCategory.song);
    currentSortSong.value =
        _loadIntPref(StorageService.kMusicSongSort, MusicSongSort.titleAsc);
    currentSortGroup.value =
        _loadIntPref(StorageService.kMusicGroupSort, MusicGroupSort.nameAsc);
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
          StorageService.kMusicLibraryCacheAndroid, const []);
      if (raw.isEmpty) return null;
      return raw
          .map((e) => SongEntry.fromJson(Map<dynamic, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveCache() async {
    final raw = allSongs.map((s) => s.toJson()).toList();
    await StorageService.setValue(
        StorageService.kMusicLibraryCacheAndroid, raw);
  }

  Future<void> scanAll({void Function(String fileName)? onFound}) async {
    isScanning.value = true;
    metaLoadCount.value = 0;
    _coverCache.reset();
    final audios = await IosLocalScanner.scanAudios(onFound: onFound);
    final songs = audios
        .map((a) => SongEntry.fromScan(
              path: a.path,
              name: a.name,
              folder: a.folder,
              size: a.size,
              modified: a.modified,
            ))
        .toList();
    allSongs.assignAll(songs);
    isScanning.value = false;
    // 后台异步加载元数据(标题/歌手/专辑/歌词),加载完成后落盘缓存。
    // 封面不在这里加载——封面改为按"当前展示列表"分批增量加载，
    // 见 ensureCoversForCurrentView / onSongVisible。
    await _loadMetadataInBackground();
  }

  Future<void> _loadMetadataInBackground() async {
    if (_metaLoading) return;
    _metaLoading = true;
    for (int i = 0; i < allSongs.length; i++) {
      if (_disposed) break;
      final s = allSongs[i];
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
        // 增量加载(前 200 首，滚动到后面再加载下一个 200)，避免整个
        // 音乐库(可能几千首)在后台一次性把所有封面都读进内存。
        // 触发响应式更新
        allSongs.refresh();
        metaLoadCount.value++;
        // 每处理 20 首落盘一次缓存,避免中途被杀进程时全部丢失,
        // 也避免每首歌都写一次 Hive 造成 IO 压力。
        // 注意：_saveCache 只序列化 SongEntry.toJson()，coverBytes 不会
        // 被写进 Hive（见 toJson 的注释），所以这里落盘的仍然只是标题/
        // 歌手/专辑/歌词这些文本字段，体积不会因为封面而膨胀。
        if (metaLoadCount.value % 20 == 0) {
          await _saveCache();
        }
      } catch (_) {
        s.metadataLoaded = true;
      }
      // 让出事件循环,避免阻塞 UI
      await Future.delayed(Duration.zero);
    }
    _metaLoading = false;
    if (!_disposed) {
      await _saveCache();
    }
    // 元数据(标题/歌手等排序用得到的字段)加载完成后，当前展示列表的
    // 顺序可能已经变化，这里补一次首批封面加载，覆盖"元数据还没加载
    // 完时就已经进入页面"的情况。
    ensureCoversForCurrentView();
  }

  /// 触发响应式更新，供封面分批加载器在每首歌加载完成后调用。
  void _refreshSongs() => allSongs.refresh();

  /// 当前展示列表：只有"歌曲"分类会在主列表页直接渲染每首歌的封面
  /// (专辑/艺术家/文件夹分类下这一页展示的是分组卡片，用静态文件夹
  /// 图标，不显示封面；点进某个分组后跳转到 MusicGroupPage，那边有
  /// 自己独立的封面分批加载器)，所以这里分组分类直接返回空列表，
  /// 避免做无意义的封面预读。
  List<SongEntry> _currentOrderedSongs() =>
      currentCategory.value == MusicCategory.song ? sortedSongs() : const [];

  /// 确保"当前展示列表"(按当前分类/排序结果)的前 200 首封面已加载。
  /// 在列表首次展示、分类/排序切换、从缓存恢复后调用。
  void ensureCoversForCurrentView() {
    _coverCache.ensureFirstBatch(_currentOrderedSongs(), onProgress: _refreshSongs);
  }

  /// 列表滚动到索引 [visibleIndex] 但该位置还没有封面时调用：按 200 首
  /// 为一批整批增量加载(200→400→600…)，不是逐条懒加载。
  void onSongVisible(int visibleIndex) {
    _coverCache.ensureVisible(visibleIndex, _currentOrderedSongs(),
        onProgress: _refreshSongs);
  }

  /// 展示列表的顺序/内容发生变化(分类、排序、搜索关键字)时调用：
  /// 清零已加载批次计数，按新列表重新从头计算"前 200"。
  void resetCoverBatchesAndReload() {
    _coverCache.reset();
    ensureCoversForCurrentView();
  }

  // ── 排序 ─────────────────────────────────────────────

  List<SongEntry> sortedSongs() {
    var list = allSongs.toList();
    final kw = searchKeyword.value.trim().toLowerCase();
    if (kw.isNotEmpty) {
      list = list
          .where((s) =>
              s.title.toLowerCase().contains(kw) ||
              s.artist.toLowerCase().contains(kw))
          .toList();
    }
    switch (currentSortSong.value) {
      case MusicSongSort.titleDesc:
        list.sort((a, b) =>
            b.title.toLowerCase().compareTo(a.title.toLowerCase()));
        break;
      case MusicSongSort.artistAsc:
        list.sort((a, b) =>
            a.artist.toLowerCase().compareTo(b.artist.toLowerCase()));
        break;
      case MusicSongSort.artistDesc:
        list.sort((a, b) =>
            b.artist.toLowerCase().compareTo(a.artist.toLowerCase()));
        break;
      case MusicSongSort.timeAsc:
        list.sort((a, b) => a.modified.compareTo(b.modified));
        break;
      case MusicSongSort.timeDesc:
        list.sort((a, b) => b.modified.compareTo(a.modified));
        break;
      default:
        list.sort((a, b) =>
            a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    }
    return list;
  }

  /// 构建分组(专辑 / 艺术家 / 文件夹)。
  List<MusicGroupEntry> buildGroups() {
    final cat = currentCategory.value;
    final map = <String, List<SongEntry>>{};
    for (final s in allSongs) {
      if (cat == MusicCategory.album) {
        final k = s.album.isNotEmpty ? s.album : '未知专辑';
        map.putIfAbsent(k, () => []).add(s);
      } else if (cat == MusicCategory.artist) {
        final artists = _splitArtists(s.artist);
        for (final a in artists) {
          map.putIfAbsent(a, () => []).add(s);
        }
      } else {
        // folder
        final k = s.folder.isNotEmpty ? s.folder : '/';
        map.putIfAbsent(k, () => []).add(s);
      }
    }
    return map.entries.map((e) {
      final display = cat == MusicCategory.folder
          ? (p.basename(e.key).isNotEmpty ? p.basename(e.key) : e.key)
          : e.key;
      return MusicGroupEntry(
          key: e.key, displayName: display, songs: e.value);
    }).toList();
  }

  List<String> _splitArtists(String artist) => ArtistSplitter.split(artist);

  List<MusicGroupEntry> sortedGroups() {
    var list = buildGroups();
    final kw = searchKeyword.value.trim().toLowerCase();
    if (kw.isNotEmpty) {
      list = list
          .where((g) => g.displayName.toLowerCase().contains(kw))
          .toList();
    }
    switch (currentSortGroup.value) {
      case MusicGroupSort.nameDesc:
        list.sort((a, b) =>
            b.displayName.toLowerCase().compareTo(a.displayName.toLowerCase()));
        break;
      case MusicGroupSort.timeAsc:
        list.sort((a, b) {
          final aMin = a.songs.map((s) => s.modified).reduce(_min);
          final bMin = b.songs.map((s) => s.modified).reduce(_min);
          return aMin.compareTo(bMin);
        });
        break;
      case MusicGroupSort.timeDesc:
        list.sort((a, b) {
          final aMax = a.songs.map((s) => s.modified).reduce(_max);
          final bMax = b.songs.map((s) => s.modified).reduce(_max);
          return bMax.compareTo(aMax);
        });
        break;
      default:
        list.sort((a, b) =>
            a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
    }
    return list;
  }

  static int _min(int a, int b) => a < b ? a : b;
  static int _max(int a, int b) => a > b ? a : b;

  Future<void> setCategory(int c) async {
    currentCategory.value = c;
    await StorageService.setValue(StorageService.kMusicCategory, c);
    // 切换分类后"当前展示列表"的顺序完全变了(歌曲 ↔ 专辑/艺术家/
    // 文件夹分组)，"前 200"需要按新列表重新计算，不能延续旧分类下
    // 已加载的批次位置。
    _coverCache.reset();
    ensureCoversForCurrentView();
  }

  Future<void> setSortSong(int s) async {
    currentSortSong.value = s;
    await StorageService.setValue(StorageService.kMusicSongSort, s);
    // 排序方式变化后，"前 200"对应的歌曲通常也变了，需要重新计算。
    _coverCache.reset();
    ensureCoversForCurrentView();
  }

  Future<void> setSortGroup(int s) async {
    currentSortGroup.value = s;
    await StorageService.setValue(StorageService.kMusicGroupSort, s);
    _coverCache.reset();
    ensureCoversForCurrentView();
  }

  // ── 播放入口 ────────────────────────────────────────

  void playSong(SongEntry s) {
    final list = sortedSongs();
    final idx = list.indexWhere((e) => e.path == s.path);
    AppNavigator.toMusicPlayer(
      playlist: list.map((e) => e.toMap()).toList(),
      index: idx < 0 ? 0 : idx,
    );
  }

  void openGroup(MusicGroupEntry e) {
    AppNavigator.toMusicGroup(
      title: e.displayName,
      songs: e.songs.map((s) => s.toMap()).toList(),
      sort: currentSortSong.value,
    );
  }
}

class MusicLibraryPage extends StatelessWidget {
  const MusicLibraryPage({super.key});

  @override
  Widget build(BuildContext context) {
    // 说明同 VideoLibraryPage：不能每次 build 都无条件 Get.put，否则祖先
    // widget 树重建（如主题设置变化触发 main.dart 最外层 Obx 重建）时会
    // 反复创建新 controller 实例覆盖旧实例，导致列表重复渲染并触发 GetX
    // 的 "improper use of a GetX" 异常。已注册则直接复用。
    final ctrl = Get.isRegistered<MusicLibraryController>(tag: 'music_library')
        ? Get.find<MusicLibraryController>(tag: 'music_library')
        : Get.put(MusicLibraryController(), tag: 'music_library');

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        // 注意：不能用 Obx 包裹 AppBar，原因同 VideoLibraryPage：
        // actions 里所有 ctrl.xxx.value 的读取都在 onTap 回调闭包内，
        // Obx 在构建 AppBar 时并未同步读取任何响应式变量，这正是 GetX
        // 官方文档说明的 "improper use of a GetX" 触发条件。AppBar 本身
        // 不需要响应式重建，直接去掉 Obx。
        child: AppBar(
              automaticallyImplyLeading: false,
              actions: [
                _TextBarButton(
                  icon: Icons.search,
                  label: '搜索',
                  onTap: () => showSearchDialog(
                    context,
                    title: '搜索音乐',
                    hintText: ctrl.currentCategory.value == MusicCategory.song
                        ? '输入歌曲名或歌手名'
                        : '输入分组名称',
                    initialText: ctrl.searchKeyword.value,
                    onChanged: (v) {
                      ctrl.searchKeyword.value = v;
                      // 搜索关键字变化后展示的列表内容也变了(过滤结果),
                      // "前 200"同样需要按新的展示顺序重新计算。
                      ctrl.resetCoverBatchesAndReload();
                    },
                  ),
                ),
                _TextBarButton(
                  label: '排序',
                  onTap: () async {
                    if (ctrl.currentCategory.value == MusicCategory.song) {
                      final v = await showOptionDialog(
                        context,
                        '选择排序',
                        ['标题升序', '标题降序', '歌手升序', '歌手降序', '修改时间升序', '修改时间降序'],
                        selected: ctrl.currentSortSong.value,
                      );
                      if (v != null) ctrl.setSortSong(v);
                    } else {
                      final idx = ctrl.currentSortGroup.value - 10;
                      final v = await showOptionDialog(
                        context,
                        '选择排序',
                        ['名称升序', '名称降序', '修改时间升序', '修改时间降序'],
                        selected: idx.clamp(0, 3),
                      );
                      if (v != null) ctrl.setSortGroup(v + 10);
                    }
                  },
                ),
                _TextBarButton(
                  label: '分类',
                  onTap: () async {
                    final v = await showOptionDialog(
                      context,
                      '选择分类',
                      ['歌曲', '专辑', '艺术家', '文件夹'],
                      selected: ctrl.currentCategory.value,
                    );
                    if (v != null) ctrl.setCategory(v);
                  },
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
      BuildContext context, MusicLibraryController ctrl) {
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
            Text('还没有导入任何音乐文件夹',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'iOS 无法自动扫描整个设备，请手动添加存放音乐的文件夹',
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
  /// 额外嵌套 Obx）。原因同视频库页面 _buildContent 的说明：嵌套 Obx 在
  /// 内层响应式变量（如新增的 searchKeyword）密集变化时会触发 GetX 的
  /// "improper use of a GetX" 异常，并伴随列表条目被重复构建一份。
  Widget _buildContent(BuildContext context, MusicLibraryController ctrl) {
    if (ctrl.isScanning.value && ctrl.allSongs.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    // NovaBox: 音频列表始终 LinearLayoutManager 1列,手机平板相同。
    if (ctrl.currentCategory.value == MusicCategory.song) {
      final list = ctrl.sortedSongs();
      if (list.isEmpty) return _buildEmpty(context);
      // 首次展示这份列表时确保前 200 首封面已在加载中(分类/排序切换
      // 已经在各自 setter 里触发过，这里是兜底，避免遗漏路径)。
      ctrl.ensureCoversForCurrentView();
      return ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: list.length,
        itemBuilder: (_, i) {
          // 滚动到还没加载封面的位置时，触发下一批 200 的增量加载。
          if (list[i].coverBytes == null) {
            ctrl.onSongVisible(i);
          }
          return _buildSongItem(context, ctrl, list[i]);
        },
      );
    }
    final list = ctrl.sortedGroups();
    if (list.isEmpty) return _buildEmpty(context);
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: list.length,
      itemBuilder: (_, i) => _buildGroupItem(context, ctrl, list[i]),
    );
  }

  /// NovaBox item_audio_song: 水波纹背景(非卡片),padding12dp mb4dp,
  /// 左 32dp 音符图标(tint #80000000)+ 右双行文字(标题15sp黑 + 副标题12sp黑50%)。
  Widget _buildSongItem(
      BuildContext context, MusicLibraryController ctrl, SongEntry s) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => ctrl.playSong(s),
        child: Container(
          padding: const EdgeInsets.all(12),
          margin: const EdgeInsets.only(bottom: 4),
          child: Row(
            children: [
              _buildCover(scheme, s.coverBytes, size: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: scheme.onSurface, fontSize: 15)),
                    if (s.artist.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(s.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: scheme.onSurfaceVariant, fontSize: 12)),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// NovaBox item_audio_group: 卡片(padding12dp mb8dp 圆角8 #33FFFFFF),
  /// 左 36dp 文件夹图标 + 中双行文字(组名15sp bold黑 + 数量12sp黑50%)+ 右 20dp 旋转箭头(alpha0.5)。
  Widget _buildGroupItem(
      BuildContext context, MusicLibraryController ctrl, MusicGroupEntry e) {
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
        onTap: () => ctrl.openGroup(e),
        child: Row(
          children: [
            Icon(Icons.folder, size: 36, color: scheme.onSurface),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(e.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: scheme.onSurface,
                          fontSize: 15,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 3),
                  Text('${e.songs.length} 首',
                      style: TextStyle(
                          color: scheme.onSurfaceVariant, fontSize: 12)),
                ],
              ),
            ),
            // icon_back 旋转 -90° 当右箭头
            Transform.rotate(
              angle: -1.5708, // -90°
              child: Icon(Icons.arrow_back,
                  size: 20, color: scheme.onSurfaceVariant),
            ),
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
          Icon(Icons.library_music_outlined,
              size: 80, color: scheme.onSurfaceVariant),
          const SizedBox(height: 16),
          Text('未找到本地音频',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text('请将音频文件放在设备存储根目录',
              style: TextStyle(color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }

  /// 歌曲/分组封面:有内存态封面字节则显示图片,否则退回音符图标。
  /// 封面字节来自内存态的 SongEntry.coverBytes(直接从音乐文件的 ID3
  /// 标签现读现用,不落盘缓存),为 null 时(尚未加载/没有内嵌封面/
  /// 读取失败)统一退回默认图标,不让整个列表因为一张坏图崩溃。
  Widget _buildCover(ColorScheme scheme, Uint8List? coverBytes, {required double size}) {
    if (coverBytes == null || coverBytes.isEmpty) {
      return Icon(Icons.music_note, size: size, color: scheme.onSurfaceVariant);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Image.memory(
        coverBytes,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) =>
            Icon(Icons.music_note, size: size, color: scheme.onSurfaceVariant),
      ),
    );
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
