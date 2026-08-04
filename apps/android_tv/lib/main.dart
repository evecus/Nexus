import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:media_kit/media_kit.dart';
import 'package:player_shared/player_shared.dart';

import 'app/controller/tv_settings_controller.dart';
import 'app/routes/tv_routes.dart';
import 'app/theme/tv_theme.dart';
import 'modules/music/player/tv_music_player_page.dart' show TvMusicPlayerController;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  // Use shared StorageService with a TV-specific box name
  await Hive.initFlutter();
  await StorageService.init(boxName: 'nexus');

  // Force landscape for TV
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  Get.put(TvSettingsController(), permanent: true);
  // 顶部播放入口状态：记录视频/IPTV 退出播放页后的快照，供顶部播放入口展示。
  Get.put(PlaybackBarController(), permanent: true);
  // 音乐播放器：App 级常驻单例。退出音乐播放页不会停止播放，只有开始播放
  // 视频/IPTV 或退出 App 才会停止（见各播放器 controller 的 onInit/onClose）。
  Get.put(TvMusicPlayerController(), permanent: true);

  runApp(const NexusTvApp());
}

class NexusTvApp extends StatelessWidget {
  const NexusTvApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = Get.find<TvSettingsController>();
    return ScreenUtilInit(
      designSize: const Size(1920, 1080),
      minTextAdapt: true,
      splitScreenMode: false,
      builder: (context, child) => Obx(() {
        final seedColor = Color(settings.seedColor.value);
        final platformBrightness =
            MediaQuery.platformBrightnessOf(context);
        final isDark = settings.resolveIsDark(platformBrightness);
        // 保持 TvColors(供各页面静态读取)与当前设置同步。
        TvColors.update(seedColor: seedColor, isDark: isDark);

        return GetMaterialApp(
          title: 'Nexus TV',
          debugShowCheckedModeBanner: false,
          theme: TvTheme.themeFor(seedColor: seedColor, isDark: false),
          darkTheme: TvTheme.themeFor(seedColor: seedColor, isDark: true),
          themeMode: switch (settings.themeMode.value) {
            1 => ThemeMode.light,
            2 => ThemeMode.dark,
            _ => ThemeMode.system,
          },
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [
            Locale('zh', 'CN'),
            Locale('en', 'US'),
          ],
          locale: const Locale('zh', 'CN'),
          initialRoute: TvRoutes.home,
          getPages: TvRoutes.pages,
          navigatorObservers: [FlutterSmartDialog.observer],
          builder: FlutterSmartDialog.init(),
        );
      }),
    );
  }
}
