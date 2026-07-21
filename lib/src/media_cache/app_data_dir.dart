import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// App 沙盒内的 appdata 文件夹相关路径(手机端与 TV 端共用)。
///
/// 视频缩略图需要解码视频帧生成图片，成本较高，仍然落地为磁盘文件，
/// 只把文件路径存进 Hive 缓存里，随 App 卸载自动清理。
///
/// 音乐封面已经和 Windows 端统一改为"只在内存里持有、不落盘"的策略
/// (见 `AudioCoverMemoryCache`)，因为封面数据本来就直接嵌在音频文件的
/// 标签里，读取成本很低，没必要额外占用本地存储。[coversDir] 保留只是
/// 为了不破坏旧版本可能残留的封面缓存文件路径，新代码不会再往这个目录
/// 写入任何文件。
class AppDataDir {
  AppDataDir._();

  static Directory? _root;
  static Directory? _coversDir;
  static Directory? _thumbsDir;

  static Future<Directory> get _rootDir async {
    if (_root != null) return _root!;
    final docs = await getApplicationDocumentsDirectory();
    _root = Directory(p.join(docs.path, 'appdata'));
    return _root!;
  }

  /// appdata/covers 子文件夹。历史遗留：旧版本曾把音频内嵌封面写到这里，
  /// 现在封面统一走内存分批加载，不再有新代码写入此目录。
  static Future<Directory> get coversDir async {
    if (_coversDir != null) return _coversDir!;
    final root = await _rootDir;
    _coversDir = Directory(p.join(root.path, 'covers'));
    return _coversDir!;
  }

  /// appdata/thumbnails 子文件夹,存放视频截图生成的缩略图。
  static Future<Directory> get thumbsDir async {
    if (_thumbsDir != null) return _thumbsDir!;
    final root = await _rootDir;
    _thumbsDir = Directory(p.join(root.path, 'thumbnails'));
    return _thumbsDir!;
  }

  /// 确保 appdata 及其子目录都已创建。在写入缩略图文件前调用一次即可,
  /// 防止目录不存在导致写入失败。
  static Future<void> ensureCreated() async {
    final root = await _rootDir;
    if (!await root.exists()) {
      await root.create(recursive: true);
    }
    final thumbs = await thumbsDir;
    if (!await thumbs.exists()) {
      await thumbs.create(recursive: true);
    }
  }
}
