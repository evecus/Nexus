import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

/// 权限分两类独立管理，互不自动升级：
///
/// 1. **基础媒体权限**（READ_MEDIA_VIDEO / READ_MEDIA_AUDIO，旧版设备为
///    READ_EXTERNAL_STORAGE）—— App 启动时就应该主动申请，用户看到的是
///    标准系统权限弹窗（"允许访问照片和视频/音乐和音频文件"），不会跳转
///    设置页。这类权限足以覆盖"内部存储 + 系统识别的标准媒体目录"。
///
/// 2. **所有文件访问权限**（MANAGE_EXTERNAL_STORAGE）—— 仅在用户的设备
///    确实插了 SD 卡/U 盘、需要扫描这些外部卷任意目录时才需要。这个权限
///    必须跳转到系统设置里的专属页面由用户手动打开开关，无法通过普通
///    弹窗申请，所以不在 App 启动时自动触发，而是在"设置"页放一个按钮，
///    用户根据自己是否有外部存储设备来决定要不要开。
class PermissionUtil {
  PermissionUtil._();

  // ══════════════════════════════════════════════════════════════════════
  //  基础媒体权限 —— App 启动时自动申请
  // ══════════════════════════════════════════════════════════════════════

  /// 请求访问本地视频与音频所需的基础权限。
  ///
  /// 只处理 READ_MEDIA_VIDEO/AUDIO（新版）或 READ_EXTERNAL_STORAGE（旧版）
  /// 这类会弹标准系统对话框的权限，不会跳转设置页，可以放心在 App 启动时
  /// 直接调用。返回 true 表示至少拥有访问能力；否则为 false。
  static Future<bool> requestMediaPermissions() async {
    if (!Platform.isAndroid) return true;

    // 第一步:主动请求经典存储权限(与 NovaTV 一致,触发真实系统弹窗)。
    // permission_handler 在 Android 13+ 设备上会自动把这个请求映射为
    // READ_MEDIA_IMAGES/VIDEO/AUDIO 的组合弹窗;Android 12 及以下则是
    // 传统的 READ/WRITE_EXTERNAL_STORAGE 弹窗。两种情况下都是一次性的
    // 系统对话框,不会跳转设置页。
    final storageResult = await Permission.storage.request();
    _restoreTransparentSystemBars();
    if (storageResult.isGranted || storageResult.isLimited) {
      return true;
    }

    // 第二步:细粒度媒体权限(某些厂商 ROM 上,storage 请求可能已经隐式
    // 覆盖了这些,这里再显式请求一次,确保视频/音频访问都拿到)。
    final results = await [Permission.videos, Permission.audio].request();
    _restoreTransparentSystemBars();
    final bool granted =
        results.values.every((s) => s.isGranted || s.isLimited);
    return granted;
  }

  /// 检查当前是否拥有基础媒体访问权限。
  ///
  /// 注意：不再把 [hasAllFilesAccess] 也算进来——这两类权限彻底独立，
  /// 拥有"所有文件访问"不代表基础媒体权限的系统状态一定是 granted
  /// （两者是两套不同的系统权限记录），调用方如果只是想判断"能不能扫本地
  /// 媒体库"，请优先看 [hasAnyStorageAccess]。
  static Future<bool> hasMediaPermissions() async {
    if (!Platform.isAndroid) return true;

    final s = await Permission.storage.status;
    if (s.isGranted || s.isLimited) return true;

    final v = await Permission.videos.status;
    final a = await Permission.audio.status;
    return (v.isGranted || v.isLimited) && (a.isGranted || a.isLimited);
  }

  /// 综合判断：基础媒体权限或所有文件访问权限，任一满足即可正常使用
  /// 视频/音乐库的扫描功能（供页面级的"是否需要展示权限引导"判断使用）。
  static Future<bool> hasAnyStorageAccess() async {
    if (!Platform.isAndroid) return true;
    if (await hasMediaPermissions()) return true;
    return hasAllFilesAccess();
  }

  // ══════════════════════════════════════════════════════════════════════
  //  所有文件访问权限 —— 仅在设置页由用户主动开启（用于 SD 卡/U 盘）
  // ══════════════════════════════════════════════════════════════════════

  /// 查询是否已经拥有"所有文件访问权限"(MANAGE_EXTERNAL_STORAGE)。
  ///
  /// 这个权限决定了 App 能否用 `dart:io` 的 Directory/File 直接遍历 SD 卡、
  /// U 盘等外部存储卷的任意目录——只有基础媒体权限是做不到的（那类权限
  /// 只能读到内部存储和系统识别的标准媒体目录）。
  static Future<bool> hasAllFilesAccess() async {
    if (!Platform.isAndroid) return true;
    final m = await Permission.manageExternalStorage.status;
    return m.isGranted;
  }

  /// 引导用户开启"所有文件访问权限"。
  ///
  /// 与基础媒体权限不同，这个权限无法通过普通系统弹窗申请——
  /// `Permission.manageExternalStorage.request()` 实际上会直接跳转到
  /// 系统设置里"所有文件访问权限"这个专属管理页面，需要用户手动点开关，
  /// 然后返回 App。调用方应只在用户主动点击"外部存储权限"这类设置项时
  /// 才调用本方法，不要在 App 启动时自动触发（会显得很突兀，且大多数
  /// 只用内部存储的用户根本不需要这个权限）。
  ///
  /// 返回 true 表示用户从设置页返回时该权限已经是 granted 状态。
  static Future<bool> requestAllFilesAccess() async {
    if (!Platform.isAndroid) return true;
    final manage = await Permission.manageExternalStorage.request();
    _restoreTransparentSystemBars();
    return manage.isGranted;
  }

  static void _restoreTransparentSystemBars() {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
    ));
  }

  /// 打开应用设置页(用于用户在拒绝权限后手动授权)。
  static Future<void> openAppSettingsPage() => openAppSettings();
}
