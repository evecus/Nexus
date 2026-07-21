import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as p;
import 'package:player_shared/player_shared.dart';

import 'package:nexus_ios/app/routes.dart';
import 'package:nexus_ios/widgets/option_dialog.dart';
import 'package:nexus_ios/modules/music/library/music_library_page.dart'
    show MusicSongSort;

/// 音乐分组详情页,完全照抄 NovaBox 的 `LocalAudioDirActivity`。
///
/// 展示某专辑 / 艺术家 / 文件夹分组下的歌曲列表,支持 6 种排序。
/// 由于 NovaBox 音频页本身仅使用列表,本页手机端和平板端均使用单列列表
/// (与 NovaBox 行为一致)。点击歌曲进入播放器,以当前列表为播放列表。
class MusicGroupPage extends StatefulWidget {
  const MusicGroupPage({super.key});

  @override
  State<MusicGroupPage> createState() => _MusicGroupPageState();
}

class _MusicGroupPageState extends State<MusicGroupPage> {
  late String _title;
  late int _sort;
  late List<SongEntry> _songs;
  bool _metadataLoading = false;

  /// 封面内存缓存 + 分批增量加载器：与音乐库主页一致的策略——只读
  /// 当前(按当前排序)列表的前 200 首封面，滚动到后面再整批加载下一个
  /// 200，不落盘。
  late final AudioCoverMemoryCache<SongEntry> _coverCache =
      AudioCoverMemoryCache<SongEntry>(
    batchSize: 200,
    pathOf: (s) => s.path,
    hasCover: (s) => s.coverBytes != null,
    applyCover: (s, meta) => s.coverBytes = meta.coverBytes,
  );

  @override
  void initState() {
    super.initState();
    final args = Get.arguments as Map<String, dynamic>? ?? {};
    _title = args['title'] as String? ?? '歌曲列表';
    _sort = args['sort'] as int? ?? MusicSongSort.titleAsc;
    final raw = (args['songs'] as List?)?.map((e) => Map<String, String>.from(e as Map)) ?? [];
    _songs = raw
        .map((m) => SongEntry(
              path: m['path'] ?? '',
              name: m['name'] ?? '',
              folder: '',
              size: 0,
              modified: 0,
              title: p.withoutExtension(m['name'] ?? ''),
              lyrics: m['lyrics'] ?? '',
            ))
        .toList();
    _sortList();
    _ensureMetadata();
  }

  @override
  void dispose() {
    _coverCache.dispose();
    super.dispose();
  }

  Future<void> _ensureMetadata() async {
    final pending = _songs.where((s) => !s.metadataLoaded).toList();
    if (pending.isEmpty) {
      // 标题/歌手等已加载过(比如从缓存恢复)，仍需单独触发一次封面的
      // 首批(前 200)加载——封面不落盘，每次进页面都是内存态空白。
      _ensureCoversForCurrentView();
      return;
    }
    setState(() => _metadataLoading = true);
    for (final s in pending) {
      try {
        final meta = await AudioMetadataReader.readFile(s.path);
        s.metadataLoaded = true;
        if (meta.title != null && meta.title!.isNotEmpty) {
          s.title = meta.title!;
        }
        s.artist = meta.artist ?? '';
        s.album = meta.album ?? '';
        // 注意：这里故意不读封面。封面改为按"当前展示列表"分批增量
        // 加载(前 200 首，滚动到后面再加载下一个 200)，见
        // _ensureCoversForCurrentView / _onSongVisible。
      } catch (_) {
        s.metadataLoaded = true;
      }
      if (!mounted) return;
      setState(() {});
      await Future.delayed(Duration.zero);
    }
    if (mounted) setState(() => _metadataLoading = false);
    // 标题/歌手加载完成、排序结果可能已经变化，这里补一次首批封面加载。
    _ensureCoversForCurrentView();
  }

  /// 确保当前(按 _sort 排好序)列表的前 200 首封面已加载。
  void _ensureCoversForCurrentView() {
    _coverCache.ensureFirstBatch(_songs, onProgress: () async {
      if (mounted) setState(() {});
    });
  }

  /// 列表滚动到索引 [visibleIndex] 但该位置还没有封面时调用。
  void _onSongVisible(int visibleIndex) {
    _coverCache.ensureVisible(visibleIndex, _songs, onProgress: () async {
      if (mounted) setState(() {});
    });
  }

  void _sortList() {
    switch (_sort) {
      case MusicSongSort.titleDesc:
        _songs.sort((a, b) =>
            b.title.toLowerCase().compareTo(a.title.toLowerCase()));
        break;
      case MusicSongSort.artistAsc:
        _songs.sort((a, b) =>
            a.artist.toLowerCase().compareTo(b.artist.toLowerCase()));
        break;
      case MusicSongSort.artistDesc:
        _songs.sort((a, b) =>
            b.artist.toLowerCase().compareTo(a.artist.toLowerCase()));
        break;
      case MusicSongSort.timeAsc:
        _songs.sort((a, b) => a.modified.compareTo(b.modified));
        break;
      case MusicSongSort.timeDesc:
        _songs.sort((a, b) => b.modified.compareTo(a.modified));
        break;
      default:
        _songs.sort((a, b) =>
            a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    }
  }

  Future<void> _openSortDialog() async {
    final v = await showOptionDialog(
      context,
      '选择排序',
      ['标题升序', '标题降序', '歌手升序', '歌手降序', '修改时间升序', '修改时间降序'],
      selected: _sort,
    );
    if (v != null && mounted) {
      setState(() {
        _sort = v;
        _sortList();
      });
      // 排序方式变化后"前 200"对应的歌曲通常也变了，按新顺序重新计算。
      _coverCache.reset();
      _ensureCoversForCurrentView();
    }
  }

  void _playAt(int index) {
    AppNavigator.toMusicPlayer(
      playlist: _songs.map((s) => s.toMap()).toList(),
      index: index,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (_metadataLoading)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          TextButton.icon(
            icon: const Icon(Icons.sort, size: 20),
            label: const Text('排序'),
            onPressed: _openSortDialog,
          ),
        ],
      ),
      body: _songs.isEmpty
          ? Center(
              child: Text('列表为空',
                  style: Theme.of(context).textTheme.bodyMedium),
            )
          : ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              itemCount: _songs.length,
              itemBuilder: (_, i) {
                // 滚动到还没加载封面的位置时，触发下一批 200 的增量加载。
                if (_songs[i].coverBytes == null) {
                  _onSongVisible(i);
                }
                return _buildItem(context, i);
              },
            ),
    );
  }

  Widget _buildItem(BuildContext context, int i) {
    final s = _songs[i];
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: scheme.tertiaryContainer.withAlpha(80),
            borderRadius: BorderRadius.circular(8),
          ),
          clipBehavior: Clip.antiAlias,
          child: s.coverBytes == null || s.coverBytes!.isEmpty
              ? Icon(Icons.music_note, color: scheme.tertiary)
              : Image.memory(
                  s.coverBytes!,
                  width: 44,
                  height: 44,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      Icon(Icons.music_note, color: scheme.tertiary),
                ),
        ),
        title: Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: s.artist.isEmpty
            ? null
            : Text(s.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall),
        trailing: const Icon(Icons.play_circle_outline, size: 22),
        onTap: () => _playAt(i),
      ),
    );
  }
}
