import 'package:flutter/services.dart';

/// iOS 侧"已授权目录"的持久化书签桥接。
///
/// ## 背景
/// Android 端可以直接遍历 `/storage`、`/sdcard` 整个文件系统(见
/// `LocalScanner`),iOS App 运行在沙盒里,没有任何 API 能扫描整个设备
/// 存储——只能由用户通过系统的文件选择器(`UIDocumentPickerViewController`)
/// 明确选择某个文件夹,App 才能访问该文件夹内容。
///
/// 严格来说 iOS 并不支持 macOS 那种"security-scoped bookmark"(仅
/// macOS 独有的沙盒机制),但通过 `UIDocumentPickerViewController` 选中
/// 目录后,依然可以拿到一个"regular NSURL bookmark"并长期持久化,每次
/// 使用前调用 `startAccessingSecurityScopedResource()`、用完调用
/// `stopAccessingSecurityScopedResource()`(iOS 上这两个方法依然存在且
/// 有效,只是底层实现与 macOS 不同)。这是苹果官方在开发者论坛上确认过
/// 的正确用法(而不是"iOS 完全不支持任何持久化访问")。
///
/// 本类通过原生 Swift 侧(`ios/Runner/NexusDirectoryBookmark.swift`)封装
/// 这套机制,对 Dart 层暴露"添加目录 / 列出已授权目录 / 移除目录 / 枚举
/// 某个已授权目录下的文件"这几个原子操作,上层的 [IosLocalScanner] 只需要
/// 调用这些方法,不需要关心 bookmark 的具体存储格式。
class IosDirectoryBookmark {
  IosDirectoryBookmark._();

  static const MethodChannel _channel =
      MethodChannel('com.nexus.mobile/directory_bookmark');

  /// 弹出系统文件夹选择器,用户选定后在原生侧持久化一份 bookmark 并落盘,
  /// 成功返回该目录的显示名称(用于列表展示);用户取消选择返回 null。
  ///
  /// 重复选择同一个物理目录时,原生侧会去重(不会出现完全一样的目录被
  /// 添加两次)。
  static Future<String?> pickAndAddDirectory() async {
    final result =
        await _channel.invokeMethod<String>('pickAndAddDirectory');
    return result;
  }

  /// 列出当前所有已授权(已持久化 bookmark)的目录。
  ///
  /// 返回的每一项包含:
  /// - `id`:内部稳定标识(用于 [removeDirectory]),不是文件路径本身。
  /// - `displayName`:展示用名称(目录名)。
  /// - `accessible`:该 bookmark 当前是否仍能成功解析访问(用户可能在
  ///   系统"文件与文件夹"隐私设置里手动撤销过授权,或者原目录被移动/
  ///   删除,这种情况下 `accessible` 为 false,UI 侧应提示用户重新添加)。
  static Future<List<Map<String, dynamic>>> listDirectories() async {
    final result =
        await _channel.invokeMethod<List<dynamic>>('listDirectories');
    if (result == null) return const [];
    return result
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList(growable: false);
  }

  /// 移除一个已授权目录(不再持久化访问,原生侧会同时清理对应 bookmark
  /// 文件)。[id] 为 [listDirectories] 返回项里的 `id` 字段。
  static Future<void> removeDirectory(String id) async {
    await _channel.invokeMethod<void>('removeDirectory', {'id': id});
  }

  /// 枚举某个已授权目录([id])下、指定扩展名集合([extensions],均为小写
  /// 且带前导点,如 `.mp4`)匹配的文件,递归子目录。
  ///
  /// 原生侧会在枚举前调用一次 `startAccessingSecurityScopedResource()`、
  /// 枚举结束后调用 `stopAccessingSecurityScopedResource()`,整个过程
  /// 对 Dart 层透明。
  ///
  /// 返回的每一项包含 `path`(可直接交给 media_kit / video_player /
  /// AudioMetadataReader 使用的绝对路径,位于 App 沙盒内经系统授权后的
  /// 真实文件系统位置)、`name`、`size`、`modified`(毫秒时间戳)、
  /// `folder`(所在目录路径)。
  ///
  /// 若该 [id] 对应的 bookmark 已失效(用户撤销了授权/原目录被删除),
  /// 返回空列表,不会抛异常——调用方应结合 [listDirectories] 里的
  /// `accessible` 字段提示用户。
  static Future<List<Map<String, dynamic>>> listFiles({
    required String id,
    required Set<String> extensions,
  }) async {
    final result = await _channel.invokeMethod<List<dynamic>>('listFiles', {
      'id': id,
      'extensions': extensions.toList(),
    });
    if (result == null) return const [];
    return result
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList(growable: false);
  }
}
