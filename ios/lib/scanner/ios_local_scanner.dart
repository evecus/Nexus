import 'package:player_shared/player_shared.dart';

import '../bookmarks/ios_directory_bookmark.dart';

/// iOS 端本地媒体扫描器。
///
/// 与 Android/TV 共用的 `LocalScanner`(遍历整个设备存储)不同,iOS 沙盒
/// 不允许扫描任意路径,只能扫描用户通过系统文件夹选择器明确"导入"过、
/// 且仍持久化授权中的目录(见 [IosDirectoryBookmark])。
///
/// 对外接口刻意与 `LocalScanner.scanVideos` / `scanAudios` 保持一致
/// (相同的返回类型 [ScannedVideo] / [ScannedAudio]),这样 Android 端
/// 原有的音乐库/视频库 Controller、UI 页面代码可以原样复用,只需要把
/// `import 'package:player_shared/player_shared.dart'` 里的 `LocalScanner`
/// 换成本类,分类/排序/搜索/分组等所有界面逻辑都不需要改动。
///
/// "扫描"在 iOS 语境下的含义是:遍历当前所有已授权目录,重新枚举其中
/// 匹配扩展名的文件——不会主动弹出目录选择器(选择新目录是独立的"添加
/// 目录"操作,见设置页的"管理目录"入口),这与安卓端"点击刷新=重新扫描
/// 已知范围"的语义对齐。
class IosLocalScanner {
  IosLocalScanner._();

  /// 扫描所有已授权目录中的视频文件。[onFound] 用途与 [LocalScanner]
  /// 一致:每发现一个匹配文件回调一次文件名,用于扫描进度弹窗。
  static Future<List<ScannedVideo>> scanVideos({
    void Function(String fileName)? onFound,
  }) async {
    return _scan(extensions: videoExtensions, onFound: onFound)
        .then((list) => list.map(_toScannedVideo).toList());
  }

  /// 扫描所有已授权目录中的音频文件。
  static Future<List<ScannedAudio>> scanAudios({
    void Function(String fileName)? onFound,
  }) async {
    return _scan(extensions: musicExtensions, onFound: onFound)
        .then((list) => list.map(_toScannedAudio).toList());
  }

  static Future<List<Map<String, dynamic>>> _scan({
    required Set<String> extensions,
    void Function(String fileName)? onFound,
  }) async {
    final dirs = await IosDirectoryBookmark.listDirectories();
    final out = <Map<String, dynamic>>[];
    final seen = <String>{};
    for (final dir in dirs) {
      final id = dir['id'] as String?;
      final accessible = dir['accessible'] as bool? ?? false;
      if (id == null || !accessible) continue;
      List<Map<String, dynamic>> files;
      try {
        files = await IosDirectoryBookmark.listFiles(
          id: id,
          extensions: extensions,
        );
      } catch (_) {
        continue;
      }
      for (final f in files) {
        final path = f['path'] as String?;
        if (path == null || !seen.add(path)) continue;
        out.add(f);
        final name = f['name'] as String?;
        if (name != null) onFound?.call(name);
      }
    }
    return out;
  }

  static ScannedVideo _toScannedVideo(Map<String, dynamic> f) => ScannedVideo(
        path: f['path'] as String? ?? '',
        name: f['name'] as String? ?? '',
        size: (f['size'] as num?)?.toInt() ?? 0,
        modified: (f['modified'] as num?)?.toInt() ?? 0,
        folder: f['folder'] as String? ?? '',
      );

  static ScannedAudio _toScannedAudio(Map<String, dynamic> f) => ScannedAudio(
        path: f['path'] as String? ?? '',
        name: f['name'] as String? ?? '',
        size: (f['size'] as num?)?.toInt() ?? 0,
        modified: (f['modified'] as num?)?.toInt() ?? 0,
        folder: f['folder'] as String? ?? '',
      );

  /// 是否至少有一个已授权且当前可访问的目录。供 UI 判断"是否需要引导
  /// 用户先去添加目录"(与安卓端 `PermissionUtil.hasAnyStorageAccess`
  /// 语义对齐,但 iOS 判断的是"有没有已导入目录"而不是"系统权限")。
  static Future<bool> hasAnyDirectory() async {
    final dirs = await IosDirectoryBookmark.listDirectories();
    return dirs.any((d) => d['accessible'] as bool? ?? false);
  }
}
