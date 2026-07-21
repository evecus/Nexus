import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as p;

import 'package:nexus_ios/app/routes.dart';
import 'package:nexus_ios/widgets/option_dialog.dart';
import 'package:nexus_ios/modules/video/local/video_library_page.dart'
    show VideoSort;

/// 视频文件夹详情页,完全照抄 NovaBox 的 `VideoFolderActivity`。
///
/// 展示某个文件夹内的视频列表,支持排序。手机端单列,平板端 2 列网格。
/// 点击视频进入播放器(以文件夹为播放列表,带 startIndex)。
class VideoFolderPage extends StatefulWidget {
  const VideoFolderPage({super.key});

  @override
  State<VideoFolderPage> createState() => _VideoFolderPageState();
}

class _VideoFolderPageState extends State<VideoFolderPage> {
  late String _folderName;
  late int _sort;
  late List<Map<String, String>> _videos;

  @override
  void initState() {
    super.initState();
    final args = Get.arguments as Map<String, dynamic>? ?? {};
    _folderName = args['folderName'] as String? ?? '视频列表';
    _sort = args['sort'] as int? ?? VideoSort.nameAsc;
    _videos = List<Map<String, String>>.from(
        (args['videos'] as List?)?.map((e) => Map<String, String>.from(e)) ??
            []);
    _sortList();
  }

  void _sortList() {
    switch (_sort) {
      case VideoSort.nameDesc:
        _videos.sort((a, b) =>
            (b['name'] ?? '').toLowerCase().compareTo((a['name'] ?? '').toLowerCase()));
        break;
      case VideoSort.timeAsc:
        // 时间字段未传递,按名称升序兜底
        _videos.sort((a, b) =>
            (a['name'] ?? '').toLowerCase().compareTo((b['name'] ?? '').toLowerCase()));
        break;
      case VideoSort.timeDesc:
        _videos.sort((a, b) =>
            (a['name'] ?? '').toLowerCase().compareTo((b['name'] ?? '').toLowerCase()));
        break;
      default:
        _videos.sort((a, b) =>
            (a['name'] ?? '').toLowerCase().compareTo((b['name'] ?? '').toLowerCase()));
    }
  }

  Future<void> _openSortDialog() async {
    final v = await showOptionDialog(
      context,
      '选择排序',
      ['名称升序', '名称降序', '修改时间升序', '修改时间降序'],
      selected: _sort,
    );
    if (v != null && mounted) {
      setState(() {
        _sort = v;
        _sortList();
      });
    }
  }

  void _playAt(int index) {
    AppNavigator.toVideoPlayer(playlist: _videos, index: index);
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 600;
    return Scaffold(
      appBar: AppBar(
        title: Text(_folderName,
            maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.sort, size: 20),
            label: const Text('排序'),
            onPressed: _openSortDialog,
          ),
        ],
      ),
      body: _videos.isEmpty
          ? Center(
              child: Text('文件夹为空',
                  style: Theme.of(context).textTheme.bodyMedium),
            )
          : isWide
              ? GridView.builder(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisExtent: 80,
                    crossAxisSpacing: 4,
                    mainAxisSpacing: 4,
                  ),
                  itemCount: _videos.length,
                  itemBuilder: (_, i) => _buildItem(i),
                )
              : ListView.builder(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  itemCount: _videos.length,
                  itemBuilder: (_, i) => _buildItem(i),
                ),
    );
  }

  Widget _buildItem(int i) {
    final v = _videos[i];
    final name = v['name'] ?? '';
    final thumbPath = v['thumbPath'] ?? '';
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: scheme.primaryContainer.withAlpha(80),
            borderRadius: BorderRadius.circular(8),
          ),
          clipBehavior: Clip.antiAlias,
          child: thumbPath.isEmpty
              ? Icon(Icons.movie_outlined, color: scheme.primary)
              : Image.file(
                  File(thumbPath),
                  width: 44,
                  height: 44,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      Icon(Icons.movie_outlined, color: scheme.primary),
                ),
        ),
        title: Text(p.withoutExtension(name),
            maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(name,
            style: Theme.of(context).textTheme.bodySmall),
        trailing: const Icon(Icons.play_circle_outline, size: 22),
        onTap: () => _playAt(i),
      ),
    );
  }
}
