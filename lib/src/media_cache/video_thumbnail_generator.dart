import 'dart:io';

import 'package:fc_native_video_thumbnail/fc_native_video_thumbnail.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;
import 'package:video_thumbnail/video_thumbnail.dart' as vt;

import 'app_data_dir.dart';

/// 视频缩略图生成工具(手机端与 TV 端共用)。
///
/// 优先使用平台原生取帧 API,只在原生方案不可用/失败时才回退到 media_kit
/// 播放器截图方案:
/// - Android / Android TV: `video_thumbnail` 插件,底层调用系统的
///   `MediaMetadataRetriever` 直接抽取一帧,不需要解封装整个媒体流、
///   不需要真正"打开"一个播放器实例,耗时通常是 media_kit 方案的几分之一。
/// - Windows: `fc_native_video_thumbnail` 插件,底层调用 Media Foundation
///   完成取帧与编码,同样不依赖启动播放器。
/// - 其它平台或原生插件调用异常(极少数编码格式、损坏文件等): 回退到
///   media_kit 打开视频 + seek 到 10% 位置 + screenshot() 截图,兼容性
///   最好但耗时最长,仅作兜底。
///
/// 三种路径最终都写入同一个 App 私有目录
/// `appdata/thumbnails/<hash(视频绝对路径)>.jpg`,用视频路径做稳定 hash
/// 命名,保证同一个视频重复生成时直接覆盖旧文件,不会无限堆积。
class VideoThumbnailGenerator {
  VideoThumbnailGenerator._();

  /// 缩略图目标尺寸。画质对于列表小图标(见 video_library_page.dart 的
  /// _buildThumb,实际只以 36~56dp 显示)完全够用,同时把单张 JPEG 体积
  /// 控制在几 KB~几十 KB,避免视频库越大、appdata/thumbnails 占用越夸张。
  static const int _thumbWidth = 320;
  static const int _thumbHeight = 180;

  /// 为单个视频生成缩略图,返回缩略图文件的绝对路径;失败返回空字符串。
  static Future<String> generate(String videoPath) async {
    await AppDataDir.ensureCreated();
    final thumbsDir = await AppDataDir.thumbsDir;
    final hash = _stableHash(videoPath);
    final outFile = File(p.join(thumbsDir.path, '$hash.jpg'));

    // 1) 优先走平台原生方案。
    String result = '';
    try {
      if (Platform.isAndroid) {
        result = await _generateWithVideoThumbnail(videoPath, outFile);
      } else if (Platform.isWindows) {
        result = await _generateWithFcNative(videoPath, outFile);
      }
    } catch (_) {
      result = '';
    }
    if (result.isNotEmpty) return result;

    // 2) 原生方案不可用/失败时,回退到 media_kit 截图方案。
    try {
      result = await _generateWithMediaKit(videoPath, outFile);
    } catch (_) {
      result = '';
    }
    return result;
  }

  /// Android / Android TV: 用 `video_thumbnail` 直接生成缩略图文件。
  /// 底层是 MediaMetadataRetriever,只抽帧不解封装整个流,速度快、占用低。
  static Future<String> _generateWithVideoThumbnail(
    String videoPath,
    File outFile,
  ) async {
    final path = await vt.VideoThumbnail.thumbnailFile(
      video: videoPath,
      thumbnailPath: outFile.parent.path,
      imageFormat: vt.ImageFormat.JPEG,
      maxWidth: _thumbWidth,
      quality: 70,
    );
    if (path == null || path.isEmpty) return '';
    final generated = File(path);
    if (!await generated.exists()) return '';
    // video_thumbnail 生成的文件名由插件内部决定,统一重命名/移动成我们
    // 自己的 hash 命名规则,和 media_kit 方案保持一致的缓存文件路径。
    if (generated.path != outFile.path) {
      await generated.copy(outFile.path);
      try {
        await generated.delete();
      } catch (_) {}
    }
    return outFile.path;
  }

  /// Windows: 用 `fc_native_video_thumbnail` 生成缩略图文件。
  /// 底层是 Media Foundation 原生取帧,不需要启动完整播放器。
  ///
  /// 注意: Windows 端该插件不支持非正方形缩略图,只使用 width 参数,最终
  /// 生成的是 width x width 的正方形图。列表 UI 用 centerCrop 类似的方式
  /// 显示时不受影响(裁剪掉多余部分即可),这里仍传入 16:9 的
  /// width/height 只是为了让其它平台走到这个分支时(理论上不会发生)
  /// 也有合理默认值。
  static Future<String> _generateWithFcNative(
    String videoPath,
    File outFile,
  ) async {
    final plugin = FcNativeVideoThumbnail();
    final ok = await plugin.saveThumbnailToFile(
      srcFile: videoPath,
      destFile: outFile.path,
      width: _thumbWidth,
      height: _thumbHeight,
      quality: 90,
    );
    if (!ok) return '';
    if (!await outFile.exists()) return '';
    return outFile.path;
  }

  /// 兜底方案: media_kit 打开视频、seek 到约 10% 位置截图。
  /// 兼容性最好(支持 media_kit/libmpv 能播放的几乎所有格式),但需要真正
  /// 打开一个播放器实例,耗时明显高于上面两种原生方案,仅在原生方案失败
  /// 时使用。
  static Future<String> _generateWithMediaKit(
    String videoPath,
    File outFile,
  ) async {
    Player? player;
    String result = '';
    try {
      player = Player();
      // screenshot() 依赖关联的渲染纹理取当前帧,即使不需要把画面显示在
      // 任何可见的 Video widget 上,也要挂一个 VideoController。
      // 不保留引用,仅需要构造时产生的绑定副作用。
      //
      // 必须给 VideoController 传入较小的 width/height,否则 media_kit
      // 会按视频源原始分辨率解码渲染,screenshot() 拿到的就是跟原视频
      // 同分辨率(如 1080p/4K)的 JPEG。
      VideoController(
        player,
        configuration: const VideoControllerConfiguration(
          width: _thumbWidth,
          height: _thumbHeight,
        ),
      );

      await player.open(Media(videoPath), play: false);

      Duration duration = player.state.duration;
      if (duration == Duration.zero) {
        duration = await player.stream.duration
            .firstWhere((d) => d > Duration.zero)
            .timeout(const Duration(seconds: 5), onTimeout: () => Duration.zero);
      }
      final seekTo = duration > Duration.zero
          ? Duration(milliseconds: (duration.inMilliseconds * 0.1).round())
          : Duration.zero;
      if (seekTo > Duration.zero) {
        await player.seek(seekTo);
        await Future.delayed(const Duration(milliseconds: 300));
      }

      final bytes = await player.screenshot(format: 'image/jpeg');
      if (bytes != null && bytes.isNotEmpty) {
        await outFile.writeAsBytes(bytes, flush: true);
        result = outFile.path;
      }
    } catch (_) {
      result = '';
    } finally {
      try {
        await player?.dispose();
      } catch (_) {}
    }
    return result;
  }

  static String _stableHash(String input) {
    const int fnvPrime = 0x01000193;
    int hash = 0x811c9dc5;
    for (final codeUnit in input.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * fnvPrime) & 0xFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }
}
