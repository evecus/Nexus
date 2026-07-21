import 'dart:io';

import 'package:path/path.dart' as p;

/// 程序所在目录下的 appdata 文件夹相关路径。
///
/// 所有本地数据（Hive 设置数据库、音乐封面缓存、视频缩略图等）都存放在这里。
/// 之所以不用 "data" 这个名字，是因为 Flutter 打包发布时本身就会在程序同级
/// 生成一个 data 文件夹（里面是 flutter_assets、icudtl.dat 等引擎/UI 资源），
/// 如果我们的用户数据也存在 "data" 里，以后更新程序替换这些官方资源文件时，
/// 用户数据会被一起覆盖/丢失，两者完全绑在了一起没法分开处理。用 "appdata"
/// 这个不会跟 Flutter 自带产物重名的目录，以后更新程序（替换 flutter_assets、
/// app.so、exe 本体等）时只要不动 appdata 目录，用户数据就不受影响。
///
/// 程序启动时会自动检测 appdata 目录是否存在，不存在则创建（见
/// [ensureCreated]），不需要做任何迁移——目前仍是测试阶段，旧的 data 目录
/// 及其中数据不做处理，按需手动清理即可。
class AppDataDir {
  AppDataDir._();

  static Directory? _dataDir;
  static Directory? _coversDir;
  static Directory? _thumbsDir;

  /// 程序同级的 appdata 文件夹。
  static Directory get root {
    return _dataDir ??= Directory(
      p.join(p.dirname(Platform.resolvedExecutable), 'appdata'),
    );
  }

  /// appdata/covers 子文件夹。历史遗留：旧版本曾把音乐文件内嵌封面写到
  /// 这里，现在封面统一改为内存分批加载(不落盘,详见
  /// `AudioCoverMemoryCache`)，不再有新代码写入此目录，仅保留目录创建
  /// 逻辑避免影响其他遗留数据读取路径。
  static Directory get coversDir {
    return _coversDir ??= Directory(p.join(root.path, 'covers'));
  }

  /// appdata/thumbnails 子文件夹，用于存放视频截图生成的缩略图。
  static Directory get thumbsDir {
    return _thumbsDir ??= Directory(p.join(root.path, 'thumbnails'));
  }

  /// 确保 appdata 及其子目录都已创建。main() 启动时调用一次即可；
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

  /// 把 appdata 目录下某文件的绝对路径转成"相对于 appdata 根目录"的相对路径，
  /// 用于持久化存储（如写入 Hive）。这样即便整个程序文件夹（exe + appdata）
  /// 被一起移动到别的磁盘/目录，之前存的路径依然有效，不需要用户重新扫描。
  ///
  /// 若传入路径不在 appdata 目录下（理论上不应发生），原样返回，调用方按
  /// 旧的绝对路径逻辑处理，不会崩溃。
  static String toRelative(String absolutePath) {
    final rel = p.relative(absolutePath, from: root.path);
    // p.relative 在极端情况下（如跨磁盘盘符）会保留原始绝对路径，
    // 用一个简单校验兜底，避免把无法转换的路径误存成"看似相对"的脏数据。
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
