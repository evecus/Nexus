import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:player_shared/player_shared.dart';

import '../theme/app_theme.dart';

/// Linux-specific settings: theme mode + seed color on top of shared base.
///
/// 【与 Windows/macOS 端的差异】Linux 端统一使用纯 MPV 单一后端（本地视频
/// 与 IPTV 直播共用同一套 mpv 播放核心 + [applyMpvOptions] 调优），不提供
/// VLC 选项，也不依赖 vlc_player 包。
///
/// 原因：vlc_player 在 Linux 上依赖系统的 libvlc5 / vlc-plugin-base，而这
/// 两个包在不同 Linux 发行版（以及同一发行版的不同版本）上的包名、版本号、
/// 甚至是否存在都可能不一致，是本项目在非 Ubuntu 系统上出现依赖冲突/安装
/// 失败的主要来源之一。media_kit（mpv）在这方面依赖面小很多，只需要
/// libmpv2，绝大多数发行版官方仓库都有且命名稳定。
/// 参考 dart_simple_live 项目的 Linux 端做法：全平台统一只用 media_kit，
/// 不引入 VLC 后端。
///
/// 因此这里不管存储里读到的历史值是 auto / exo / vlc 中的哪一个，一律
/// 迁移为 mpv；UI（settings_page.dart）也相应不再展示 VLC 相关选项。
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

    // IPTV 播放后端：Linux 端只有 mpv 一个选项，把历史存储值（auto/vlc/exo，
    // 老用户或从其他平台同步配置带来的残留值）统一迁移为 mpv。
    if (iptvBackend.value != PlayerBackendChoice.mpv) {
      iptvBackend.value = PlayerBackendChoice.mpv;
      StorageService.setValue(StorageService.kIptvBackend, 'mpv');
    }

    // 本地视频播放后端：同上，Linux 端只有 mpv 一个选项。
    if (playerBackend.value != PlayerBackendChoice.mpv) {
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
