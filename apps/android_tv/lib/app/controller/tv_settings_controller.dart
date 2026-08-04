import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:player_shared/player_shared.dart';

import '../theme/tv_theme.dart';

/// TV settings: extends the shared base, plus TV 自己的外观设置
/// (主题模式 / 主题色),与安卓、Windows 端保持一致。
class TvSettingsController extends BaseSettingsController {
  static TvSettingsController get instance => Get.find();

  /// 0 = 跟随系统, 1 = 浅色, 2 = 深色
  var themeMode = 0.obs;
  var seedColor = kTvDefaultSeed.toARGB32().obs;

  @override
  void onInit() {
    loadBase();
    themeMode.value = StorageService.getValue(StorageService.kThemeMode, 0);
    seedColor.value = StorageService.getValue(
        StorageService.kSeedColor, kTvDefaultSeed.toARGB32());
    _syncColors();

    // Android TV 端设置页只展示 Exo / MPV 两个后端选项（与 Windows /
    // Android 端保持一致的"视频后端 + IPTV 后端"双独立选择）。把存储里
    // 残留的 auto/vlc 一次性迁移为具体值：
    //   - 视频播放后端：默认 ExoPlayer
    //   - IPTV 播放后端：默认 MPV
    // 迁移后立即持久化，下次启动就不会再走这段逻辑。
    if (playerBackend.value == PlayerBackendChoice.auto ||
        playerBackend.value == PlayerBackendChoice.vlc) {
      playerBackend.value = PlayerBackendChoice.exo;
      StorageService.setValue(StorageService.kPlayerBackend, 'exo');
    }
    if (iptvBackend.value == PlayerBackendChoice.auto ||
        iptvBackend.value == PlayerBackendChoice.vlc) {
      iptvBackend.value = PlayerBackendChoice.mpv;
      StorageService.setValue(StorageService.kIptvBackend, 'mpv');
    }

    super.onInit();
  }

  Future<void> setThemeMode(int mode) async {
    themeMode.value = mode;
    await StorageService.setValue(StorageService.kThemeMode, mode);
    _syncColors();
  }

  Future<void> setSeedColor(Color color) async {
    seedColor.value = color.toARGB32();
    await StorageService.setValue(StorageService.kSeedColor, color.toARGB32());
    _syncColors();
  }

  /// 是否为深色模式(供 GetMaterialApp 与 TvColors 使用)。
  /// mode 0(跟随系统)在 TV 场景下没有很好的"系统亮度"读取入口,
  /// 这里跟随系统亮度;否则按用户选择的 1=浅色 / 2=深色 生效。
  bool resolveIsDark(Brightness platformBrightness) {
    switch (themeMode.value) {
      case 1:
        return false;
      case 2:
        return true;
      default:
        return platformBrightness == Brightness.dark;
    }
  }

  void _syncColors() {
    TvColors.update(seedColor: Color(seedColor.value));
  }
}
