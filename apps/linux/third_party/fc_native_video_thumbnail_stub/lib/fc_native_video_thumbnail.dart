/// Linux-only stub for `fc_native_video_thumbnail`.
///
/// 为什么需要这个桩包，见同目录 pubspec.yaml 顶部注释和
/// linux/pubspec.yaml 里 dependency_overrides 处的注释。
///
/// API 签名（构造函数 + saveThumbnailToFile 的参数列表/返回类型）与真实
/// 插件保持一致，这样 lib/src/media_cache/video_thumbnail_generator.dart
/// 里的调用代码不需要做任何平台特判就能通过编译；该方法在 Nexus 里只在
/// `Platform.isWindows` 分支下才会被调用，Linux 运行时永远不会真正执行到
/// 这里。即便被意外调用，直接返回 false 也是安全的：调用方在拿到 false
/// 时会自动回退到 media_kit 截图方案生成缩略图，与真实插件在"取帧失败"
/// 时的行为完全一致，不会导致崩溃或功能缺失。
class FcNativeVideoThumbnail {
  const FcNativeVideoThumbnail();

  /// 始终返回 false（视为"取帧失败"），触发调用方的 media_kit 兜底方案。
  Future<bool> saveThumbnailToFile({
    required String srcFile,
    bool srcFileUri = false,
    required String destFile,
    required int width,
    int? height,
    String format = 'jpeg',
    int quality = 90,
  }) async {
    return false;
  }
}
