import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:media_kit/media_kit.dart';
import 'package:player_shared/player_shared.dart' hide AppDataDir;
import 'package:window_manager/window_manager.dart';

import 'app/controller/app_settings_controller.dart';
import 'app/controller/global_player_controller.dart';
import 'app/data_dir.dart';
import 'app/routes.dart';
import 'app/theme/app_theme.dart';
import 'app/tray_service.dart';
import 'modules/home/home_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  await AppDataDir.ensureCreated();

  // 用 Hive.init（而非 Hive.initFlutter）以显式指定存储目录为程序同级的
  // appdata 文件夹，不依赖 path_provider 默认的用户 Documents 目录，也不
  // 跟 Flutter 打包自带的 data 文件夹（flutter_assets 等）混在一起。
  Hive.init(AppDataDir.root.path);
  await StorageService.init(boxName: 'nexus_windows');

  await windowManager.ensureInitialized();
  await windowManager.waitUntilReadyToShow(
    const WindowOptions(
      title: 'Nexus',
      size: Size(1280, 800),
      minimumSize: Size(900, 600),
      center: true,
      backgroundColor: Colors.transparent,
      titleBarStyle: TitleBarStyle.normal,
    ),
    () async {
      await windowManager.show();
      await windowManager.focus();
    },
  );

  Get.put(AppSettingsController(), permanent: true);
  Get.put(GlobalPlayerController(), permanent: true);

  await TrayService.instance.init();

  runApp(const NexusWindowsApp());
}

class NexusWindowsApp extends StatelessWidget {
  const NexusWindowsApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = Get.find<AppSettingsController>();
    return Obx(
      () => GetMaterialApp(
        title: 'Nexus',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(settings.seedColor.value),
        darkTheme: AppTheme.dark(settings.seedColor.value),
        themeMode: ThemeMode.values[settings.themeMode.value],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
        locale: const Locale('zh', 'CN'),
        home: const HomePage(),
        navigatorObservers: [FlutterSmartDialog.observer],
        builder: FlutterSmartDialog.init(),
        getPages: AppRoutes.pages,
      ),
    );
  }
}
