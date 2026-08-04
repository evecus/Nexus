import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:player_shared/player_shared.dart';

import '../theme/app_theme.dart';

/// Windows-specific settings: theme mode + seed color on top of shared base.
class AppSettingsController extends BaseSettingsController {
  static AppSettingsController get instance =>
      Get.find<AppSettingsController>();

  final themeMode = 0.obs; // 0=system 1=light 2=dark
  final seedColor  = AppColors.defaultSeed.toARGB32().obs;

  @override
  void onInit() {
    loadBase();
    themeMode.value =
        StorageService.getValue(StorageService.kThemeMode, 0);
    seedColor.value =
        StorageService.getValue(StorageService.kSeedColor, AppColors.defaultSeed.toARGB32());

    // Windows 端 IPTV 默认使用 VLC（对 HLS/TS/RTMP 兼容性最好）。
    // loadBase 从存储读出的 auto（老用户或首次启动）在这里迁移为 vlc。
    // UI 不展示 auto 选项，用户只会选 mpv/vlc，因此不会反复覆盖。
    if (iptvBackend.value == PlayerBackendChoice.auto) {
      iptvBackend.value = PlayerBackendChoice.vlc;
      StorageService.setValue(StorageService.kIptvBackend, 'vlc');
    }

    // Windows 端"视频播放后端"也只提供 MPV / VLC 两个选项（设置页已移除
    // auto）。把存储里残留的 auto 迁移为 mpv（默认后端），exo 同样不展示
    // 也一并迁移为 mpv。
    if (playerBackend.value == PlayerBackendChoice.auto ||
        playerBackend.value == PlayerBackendChoice.exo) {
      playerBackend.value = PlayerBackendChoice.mpv;
      StorageService.setValue(StorageService.kPlayerBackend, 'mpv');
    }

    super.onInit();
  }

  Future<void> setThemeMode(int mode) async {
    themeMode.value = mode;
    await StorageService.setValue(StorageService.kThemeMode, mode);
  }

  Future<void> setSeedColor(Color color) async {
    seedColor.value = color.toARGB32();
    await StorageService.setValue(StorageService.kSeedColor, color.toARGB32());
  }
}
