import 'dart:io';

import 'package:path/path.dart' as p;

/// 用户数据目录（Hive 设置数据库、音乐封面缓存、视频缩略图等）相关路径。
///
/// 【与 Windows 端的关键差异】
/// Windows 端把 appdata 放在"程序同级目录"下，是因为 Windows 发行版通常是
/// 一个可以随意移动的独立文件夹（zip 解压即用），程序和数据绑在一起搬家很
/// 方便。macOS 应用的分发/安装方式完全不同：
/// - 应用以 `.app` bundle 形式分发，安装后通常放在 `/Applications` 下，
///   `.app` 内部（`Contents/MacOS/` 可执行文件同级目录）在未提权/未签名
///   开发者证书的情况下往往不可写，且每次重新安装/替换 `.app` 时 bundle
///   内容会被整体覆盖，"程序同级目录"这个概念在 macOS 上并不成立；
/// - macOS 的标准做法是把每个 App 的私有数据放在
///   `~/Library/Application Support/<AppName>/` 下，这是 Apple 官方文档
///   推荐的"Application Support"目录，与 Windows 的 `%APPDATA%`、Linux 的
///   `$XDG_DATA_HOME` 是同一层级的对应概念。
///
/// 因此 macOS 端不用"程序同级目录"，改用
/// `~/Library/Application Support/nexus`；除此之外，目录结构（covers/、
/// thumbnails/ 子目录）、相对路径存储/还原逻辑（[toRelative] /
/// [toAbsolute]）与 Windows 端完全一致，保证上层调用代码（音乐/视频扫描、
/// 缩略图生成等）不需要感知这个差异。
///
/// 程序启动时会自动检测数据目录是否存在，不存在则创建（见 [ensureCreated]）。
class AppDataDir {
  AppDataDir._();

  static Directory? _dataDir;
  static Directory? _coversDir;
  static Directory? _thumbsDir;

  /// `~/Library/Application Support/nexus`；连 HOME 都取不到的极端情况下
  /// （理论上不会发生），退回程序同级目录，保证至少能跑起来而不是直接崩溃。
  static Directory get root {
    if (_dataDir != null) return _dataDir!;
    final home = Platform.environment['HOME'];
    String base;
    if (home != null && home.isNotEmpty) {
      base = p.join(home, 'Library', 'Application Support');
    } else {
      base = p.dirname(Platform.resolvedExecutable);
    }
    return _dataDir ??= Directory(p.join(base, 'nexus'));
  }

  /// 数据目录下的 covers 子文件夹。历史遗留：旧版本曾把音乐文件内嵌封面写到
  /// 这里，现在封面统一改为内存分批加载(不落盘,详见
  /// `AudioCoverMemoryCache`)，不再有新代码写入此目录，仅保留目录创建
  /// 逻辑避免影响其他遗留数据读取路径。
  static Directory get coversDir {
    return _coversDir ??= Directory(p.join(root.path, 'covers'));
  }

  /// 数据目录下的 thumbnails 子文件夹，用于存放视频截图生成的缩略图。
  static Directory get thumbsDir {
    return _thumbsDir ??= Directory(p.join(root.path, 'thumbnails'));
  }

  /// 确保数据目录及其子目录都已创建。main() 启动时调用一次即可；
  /// 其余地方（如音乐/视频扫描逻辑）在写入缓存文件前也会各自再确认一次，
  /// 防止用户手动删除了子目录导致写入失败。
  static Future<void> ensureCreated() async {
    if (!await root.exists()) {
      await root.create(recursive: true);
    }
    if (!await coversDir.exists()) {
      await coversDir.create(recursive: true);
    }
    if (!await thumbsDir.exists()) {
      await thumbsDir.create(recursive: true);
    }
  }

  /// 把数据目录下某文件的绝对路径转成"相对于数据目录根目录"的相对路径，
  /// 用于持久化存储（如写入 Hive）。这样即便整个数据目录被一起移动/备份/
  /// 迁移到别的机器，之前存的路径依然有效，不需要用户重新扫描。
  ///
  /// 若传入路径不在数据目录下（理论上不应发生），原样返回，调用方按
  /// 旧的绝对路径逻辑处理，不会崩溃。
  static String toRelative(String absolutePath) {
    final rel = p.relative(absolutePath, from: root.path);
    // p.relative 在极端情况下会保留原始绝对路径，用一个简单校验兜底，
    // 避免把无法转换的路径误存成"看似相对"的脏数据。
    if (p.isAbsolute(rel)) return absolutePath;
    return rel;
  }

  /// 把（可能是旧格式绝对路径，也可能是新格式相对路径的）存储值还原成当前
  /// 环境下可直接使用的绝对路径。
  ///
  /// 兼容两种历史数据：
  /// - 旧版本写入的绝对路径（升级前生成的缓存）：直接原样返回，不做处理；
  ///   下次该文件重新生成时会自动切换成相对路径存储。
  /// - 新版本写入的相对路径：拼接当前 [root] 得到绝对路径。
  static String toAbsolute(String stored) {
    if (stored.isEmpty) return stored;
    if (p.isAbsolute(stored)) return stored;
    return p.join(root.path, stored);
  }
}
