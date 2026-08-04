import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:player_shared/player_shared.dart';

import '../theme/app_theme.dart';

/// App-specific settings (theme color, theme mode) layered on top of
/// the shared base.
class AppSettingsController extends BaseSettingsController {
  static AppSettingsController get instance =>
      Get.find<AppSettingsController>();

  var themeMode = 0.obs; // 0=system 1=light 2=dark
  var seedColor  = AppColors.defaultSeed.toARGB32().obs;

  @override
  void onInit() {
    // 重要：这里必须在 super.onInit() 之前，用 Rx 的构造初值直接赋值，
    // 不能等 controller 注册完、被最外层 Obx（main.dart 中包裹整个
    // GetMaterialApp 的那个）订阅之后再连续两次修改 .value。
    //
    // 之前的写法是先 super.onInit()（此时 controller 已经 Get.put 完成，
    // main.dart 的 Obx 在首帧 build 时会订阅这两个字段），然后再连续
    // set themeMode.value 和 seedColor.value：这两次赋值各自触发一次
    // 通知，导致包裹整个 App 的 Obx 在首帧渲染附近被连续重建两次。
    // 由于该 Obx 之下是整个 GetMaterialApp（含 Navigator/路由树），
    // 重建会级联到当前显示的所有页面（视频/音乐库页面），与这些页面
    // StatelessWidget 的重复 build 时机重叠，触发 GetX 的
    // "improper use of a GetX" 检测，表现为列表内容重复渲染一份。
    //
    // 改为：先同步读取好本地存储的值，一次性赋值，且赋值发生在
    // controller 尚未被任何 Obx/GetX 订阅之前（onInit 阶段，
    // Get.put() 调用尚未返回，main.dart 里的 Obx 还没有机会 build），
    // 从而只产生一次（且是无观察者的）变更，不会造成连续重建。
    final savedThemeMode = StorageService.getValue(StorageService.kThemeMode, 0);
    final savedSeedColor = StorageService.getValue(
        StorageService.kSeedColor, AppColors.defaultSeed.toARGB32());
    themeMode = savedThemeMode.obs;
    seedColor = savedSeedColor.obs;
    loadBase();

    // Android 端设置页只展示 Exo / MPV 两个后端选项（与 Windows 端保持
    // 一致的"视频后端 + IPTV 后端"双独立下拉）。把存储里残留的 auto/vlc
    // 一次性迁移为具体值：
    //   - 视频播放后端：默认 ExoPlayer（本地视频硬解兼容性最好）
    //   - IPTV 播放后端：默认 MPV（对 HLS/TS 直播流兼容性更好）
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
  }

  Future<void> setSeedColor(Color color) async {
    seedColor.value = color.toARGB32();
    await StorageService.setValue(StorageService.kSeedColor, color.toARGB32());
  }
}
