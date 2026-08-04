import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../player/media_file.dart';

/// 本地媒体扫描工具(手机端与 TV 端共用)。
///
/// 从设备所有存储卷的根目录递归遍历,过滤扩展名,跳过隐藏目录与 `Android`
/// 目录,最大递归深度 8 层。
///
/// 存储卷根目录不再写死成 `/storage/emulated/0` + `/sdcard` 这两个内部
/// 存储路径——那样会导致外插 SD 卡、U 盘(USB OTG)等外部存储完全扫描
/// 不到。改为在运行时动态发现"当前设备到底挂了哪些存储卷":
/// - Android: 优先用 `path_provider` 的 `getExternalStorageDirectories()`,
///   它会为每一个挂载的外部存储卷(内部存储 + 每张 SD 卡/U 盘)各返回一个
///   该卷下"本应用专属"的目录(形如 `/storage/XXXX-XXXX/Android/data/
///   <package>/files`),从这个路径反推出卷的根目录(`/storage/XXXX-XXXX`)。
///   由于 App 已经申请了 `MANAGE_EXTERNAL_STORAGE`(全部文件访问权限),
///   从"本应用专属目录"反推出的卷根路径可以被完整遍历,不受作用域存储限制。
/// - 再叠加直接枚举 `/storage` 目录下的条目作为兜底:部分厂商 ROM /
///   USB OTG 转接的外部存储可能不会出现在 `getExternalStorageDirectories()`
///   的结果里,但依然会在 `/storage/<卷名>` 下挂载出一个可读目录。
/// - 保留 `/storage/emulated/0`、`/sdcard` 作为最后的兜底,兼容极少数
///   `path_provider` 调用失败或返回空列表的机型。
class LocalScanner {
  LocalScanner._();

  /// 最大递归深度。
  static const int _maxDepth = 8;

  /// 枚举当前设备上所有可扫描的存储卷根目录(内部存储 + SD 卡 + U 盘等)。
  static Future<List<String>> _discoverRoots() async {
    final roots = <String>{};

    // 1) path_provider：为每个已挂载的外部存储卷返回一个本应用专属目录，
    //    从中反推出卷根目录。仅 Android 支持，其它平台返回 null/抛异常时
    //    直接忽略即可。
    try {
      final dirs = await getExternalStorageDirectories();
      if (dirs != null) {
        for (final dir in dirs) {
          final root = _volumeRootFromAppDir(dir.path);
          if (root != null) roots.add(root);
        }
      }
    } catch (_) {
      // 忽略：非 Android 平台，或个别机型上该调用异常。
    }

    // 2) 直接枚举 /storage 下的条目作为补充，覆盖 path_provider 可能漏掉
    //    的 U 盘 / 特殊挂载点。跳过 self、emulated（emulated 下的 0 已经
    //    等价于内部存储主卷，单独处理见下方兜底）。
    try {
      final storageDir = Directory('/storage');
      if (await storageDir.exists()) {
        final entries = storageDir.listSync(followLinks: false);
        for (final e in entries) {
          final name = p.basename(e.path);
          if (name == 'self' || name == 'emulated') continue;
          if (e is Directory) roots.add(e.path);
        }
      }
    } catch (_) {
      // 忽略：无权限访问 /storage 本身列举时不影响其它来源。
    }

    // 3) 兜底：经典内部存储路径，确保即使上面两步都失败也至少能扫内部存储。
    roots.addAll(const ['/storage/emulated/0', '/sdcard']);

    // 过滤掉实际不存在 / 无法访问的路径，避免后续扫描浪费时间。
    //
    // 关键：必须在这里对路径做符号链接解析(resolveSymbolicLinks)后再按
    // "解析后的真实路径"去重。像 `/sdcard` 在几乎所有 Android 设备上都是
    // 指向 `/storage/emulated/0` 的符号链接——两者是同一个物理目录，但作为
    // *字符串* 并不相等，之前的 Set<String> 去重完全无法识别，导致这两个
    // 根目录被当成两个不同的根各自完整扫描一遍。而扫描内部虽然也有按
    // 文件路径去重的 `seen` 集合，但用的是 `entity.absolute.path`——这只是
    // "转成绝对路径"，并不会解析符号链接，所以通过 `/sdcard/x.mp4` 和
    // `/storage/emulated/0/x.mp4` 两条路径访问到的同一个物理文件，各自
    // 得到的 absolute.path 字符串仍然不同，去重同样失效。
    // 最终表现就是：视频/音乐库里每一条记录都精确重复一次。
    final resolved = <String, String>{}; // 真实路径 -> 保留的原始路径
    for (final root in roots) {
      try {
        final dir = Directory(root);
        if (!await dir.exists()) continue;
        final real = await dir.resolveSymbolicLinks();
        resolved.putIfAbsent(real, () => root);
      } catch (_) {}
    }
    return resolved.values.toList();
  }

  /// 从形如 `/storage/XXXX-XXXX/Android/data/<pkg>/files` 的本应用专属
  /// 目录路径反推出卷根目录 `/storage/XXXX-XXXX`。
  /// 若路径中找不到 `Android` 分段（说明不是预期格式），返回 null。
  static String? _volumeRootFromAppDir(String appDirPath) {
    final normalized = appDirPath.replaceAll('\\', '/');
    final idx = normalized.indexOf('/Android/');
    if (idx <= 0) return null;
    return normalized.substring(0, idx);
  }

  /// 扫描本地视频文件。
  ///
  /// 返回的列表按文件路径去重。每个 [VideoFile] 的 [VideoFile.name] 为文件名
  /// (含扩展名),[VideoFile.size] 为字节大小。
  ///
  /// [onFound] 可选:每发现一个匹配的文件就回调一次(文件名),用于扫描
  /// 进度弹窗实时滚动展示,不影响返回值。
  static Future<List<ScannedVideo>> scanVideos({
    void Function(String fileName)? onFound,
  }) async {
    final seen = <String>{};
    final out = <ScannedVideo>[];
    final roots = await _discoverRoots();
    for (final root in roots) {
      final dir = Directory(root);
      if (!await dir.exists()) continue;
      try {
        await _scanDir(dir, seen, out, null, _maxDepth,
            isVideo: true, onFound: onFound);
      } catch (_) {}
    }
    return out;
  }

  /// 扫描本地音频文件。[onFound] 用途同 [scanVideos]。
  static Future<List<ScannedAudio>> scanAudios({
    void Function(String fileName)? onFound,
  }) async {
    final seen = <String>{};
    final out = <ScannedAudio>[];
    final roots = await _discoverRoots();
    for (final root in roots) {
      final dir = Directory(root);
      if (!await dir.exists()) continue;
      try {
        await _scanDir(dir, seen, null, out, _maxDepth,
            isVideo: false, onFound: onFound);
      } catch (_) {}
    }
    return out;
  }

  static Future<void> _scanDir(
    Directory dir,
    Set<String> seen,
    List<ScannedVideo>? videos,
    List<ScannedAudio>? audios,
    int depth, {
    required bool isVideo,
    void Function(String fileName)? onFound,
  }) async {
    if (depth < 0) return;
    List<FileSystemEntity> entities;
    try {
      entities = dir.listSync(followLinks: false);
    } catch (_) {
      return;
    }
    for (final entity in entities) {
      final name = p.basename(entity.path);
      if (entity is Directory) {
        if (name.startsWith('.') || name == 'Android') continue;
        try {
          await _scanDir(entity, seen, videos, audios, depth - 1,
              isVideo: isVideo, onFound: onFound);
        } catch (_) {}
      } else if (entity is File) {
        final ext = p.extension(entity.path).toLowerCase();
        final match = isVideo
            ? videoExtensions.contains(ext)
            : musicExtensions.contains(ext);
        if (!match) continue;
        final abs = entity.absolute.path;
        // 去重键使用解析符号链接后的真实路径：即便根目录去重后仍有漏网的
        // 路径别名（例如某个子目录本身是指向已扫描过的另一棵子树的
        // 符号链接），也能在文件级别兜底去重，避免重复记录。展示给用户的
        // path/folder 字段仍使用原始路径（如 /sdcard/...），更符合用户
        // 认知，不强制换成解析后可能很陌生的 /storage/emulated/0/... 形式。
        String dedupeKey = abs;
        try {
          dedupeKey = await entity.resolveSymbolicLinks();
        } catch (_) {
          // 解析失败（极少数情况，如权限问题）时退回用原始绝对路径去重。
        }
        if (!seen.add(dedupeKey)) continue;
        try {
          final stat = await entity.stat();
          final size = stat.size;
          final modified = stat.modified.millisecondsSinceEpoch;
          final folder = entity.parent.path;
          if (isVideo) {
            videos?.add(ScannedVideo(
              path: abs,
              name: name,
              size: size,
              modified: modified,
              folder: folder,
            ));
          } else {
            audios?.add(ScannedAudio(
              path: abs,
              name: name,
              size: size,
              modified: modified,
              folder: folder,
            ));
          }
          onFound?.call(name);
        } catch (_) {}
      }
    }
  }
}

/// 扫描得到的视频文件(扩展自 [VideoFile],附带修改时间与所在目录)。
///
/// [thumbPath] 为磁盘缓存目录中的缩略图文件路径(由
/// `VideoThumbnailGenerator` 在后台异步生成后写入);空字符串表示还未生成
/// 或生成失败。与文件列表一起序列化进本地缓存,下次进入视频页时可以
/// 直接从缓存恢复,不需要重新扫描磁盘、重新截图。
class ScannedVideo {
  final String path;
  final String name;
  final int size;
  final int modified;
  final String folder;
  final String thumbPath;

  const ScannedVideo({
    required this.path,
    required this.name,
    required this.size,
    required this.modified,
    required this.folder,
    this.thumbPath = '',
  });

  VideoFile toBase() => VideoFile(path, name, size);

  ScannedVideo copyWith({String? thumbPath}) => ScannedVideo(
        path: path,
        name: name,
        size: size,
        modified: modified,
        folder: folder,
        thumbPath: thumbPath ?? this.thumbPath,
      );

  /// 序列化为可存入 Hive 的纯 Map。
  Map<String, dynamic> toJson() => {
        'path': path,
        'name': name,
        'size': size,
        'modified': modified,
        'folder': folder,
        'thumbPath': thumbPath,
      };

  /// 从缓存的 Map 还原。字段缺失时给出安全默认值,避免旧缓存格式导致崩溃。
  factory ScannedVideo.fromJson(Map<dynamic, dynamic> json) {
    return ScannedVideo(
      path: (json['path'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      size: (json['size'] as num?)?.toInt() ?? 0,
      modified: (json['modified'] as num?)?.toInt() ?? 0,
      folder: (json['folder'] as String?) ?? '',
      thumbPath: (json['thumbPath'] as String?) ?? '',
    );
  }
}

/// 扫描得到的音频文件。
class ScannedAudio {
  final String path;
  final String name;
  final int size;
  final int modified;
  final String folder;

  const ScannedAudio({
    required this.path,
    required this.name,
    required this.size,
    required this.modified,
    required this.folder,
  });

  MusicFile toBase() => MusicFile(path, name, size);
}
