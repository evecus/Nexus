import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:media_kit/media_kit.dart';
import 'package:player_shared/player_shared.dart';

import 'app/controller/app_settings_controller.dart';
import 'app/routes.dart';
import 'app/theme/app_theme.dart';
import 'modules/home/home_page.dart';
import 'modules/music/player/music_player_page.dart' show MusicPlayerController;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  await Hive.initFlutter();
  await StorageService.init(boxName: 'nexus');

  // Edge-to-edge on Android
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  // 在首帧渲染前就设置好透明状态栏样式，避免某些机型/Android 15 edge-to-edge
  // 场景下出现短暂的系统默认灰色状态栏背景（与页面 AppBar 顶栏颜色不一致，
  // 表现为顶部一条灰色条遮挡状态栏文字/图标）。
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.dark,
  ));

  Get.put(AppSettingsController(), permanent: true);
  // 迷你播放栏状态：记录视频/IPTV 退出播放页后的快照，供首页底部/顶部播放条展示。
  Get.put(PlaybackBarController(), permanent: true);
  // 音乐播放器：App 级常驻单例。退出音乐播放页不会停止播放，只有开始播放
  // 视频/IPTV 或退出 App 才会停止（见各播放器 controller 的 onInit/onClose）。
  Get.put(MusicPlayerController(), permanent: true);

  // 自定义错误占位:Flutter release 包默认会把构建期异常渲染成一块不带任何
  // 文字/图标的纯灰色区域(与页面主题无关),很容易被误认为是"顶部灰色遮挡"
  // 之类的样式 bug,难以定位。这里替换为明显可辨识的红色占位 + 简要提示,
  // 方便后续一眼看出是渲染异常而不是样式问题。
  //
  // 同时把完整异常堆栈打印到 debugPrint(可通过 adb logcat 或
  // `flutter run` 控制台看到),否则红色占位只显示固定文案,无法定位到底是
  // 哪个 widget、哪一行代码抛出的异常。
  ErrorWidget.builder = (FlutterErrorDetails details) {
    debugPrint('=== 组件渲染异常 ===');
    debugPrint(details.exceptionAsString());
    debugPrint(details.stack?.toString() ?? '(no stack)');
    if (details.context != null) {
      debugPrint('context: ${details.context}');
    }
    debugPrint('====================');
    return Container(
      alignment: Alignment.center,
      color: const Color(0xFFB00020),
      padding: const EdgeInsets.all(8),
      child: Text(
        '组件渲染异常\n${details.exceptionAsString()}',
        textAlign: TextAlign.center,
        maxLines: 4,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: Colors.white, fontSize: 11),
      ),
    );
  };

  runApp(const NexusAndroidApp());
}

class NexusAndroidApp extends StatelessWidget {
  const NexusAndroidApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const _ThemedApp();
  }
}

/// 用普通 StatefulWidget + GetX 的 `ever` worker 来驱动主题变化，
/// 而不是用 Obx/GetX 包裹 GetMaterialApp。
///
/// 原因：GetX 官方文档与已知 issue（jonataslaw/getx#1763、#1175）明确
/// 指出，Obx/GetX 的响应式依赖追踪只在其 builder 回调"直接"读取
/// `.value` 时才能正确识别订阅关系；一旦 builder 返回的是像
/// GetMaterialApp 这样内部自己再构建一整棵很深的路由/页面树的"重"
/// widget（issue 中称为 `GetX => HeavyWidget => variableObservable`
/// 模式），GetX 会认为这个 GetX/Obx 没有被"安全"地限定在它应该更新的
/// 具体 widget 范围内，从而抛出
/// "the improper use of a GetX has been detected"。
/// 这正是本 App 之前不管用 Obx 还是 GetX 包裹整个 GetMaterialApp
/// 都会报错的根本原因（与列表重复渲染是两个独立问题，此错误本身并不
/// 会破坏功能，但控制台/红色错误占位会一直显示）。
///
/// 改为：不把 GetMaterialApp 放进任何 Obx/GetX，而是用一个普通
/// StatefulWidget 订阅 AppSettingsController 的 seedColor / themeMode，
/// 通过 GetX 的 `ever` worker 在这两个字段变化时调用 setState()
/// 触发重建。这是 GetX 官方推荐的、用于"响应式变量在重 widget 树中
/// 更新"场景的替代方案，不会触发上述检测。
class _ThemedApp extends StatefulWidget {
  const _ThemedApp();

  @override
  State<_ThemedApp> createState() => _ThemedAppState();
}

class _ThemedAppState extends State<_ThemedApp> {
  late final AppSettingsController _settings;
  Worker? _themeModeWorker;
  Worker? _seedColorWorker;

  @override
  void initState() {
    super.initState();
    _settings = Get.find<AppSettingsController>();
    _themeModeWorker = ever(_settings.themeMode, (_) {
      if (mounted) setState(() {});
    });
    _seedColorWorker = ever(_settings.seedColor, (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _themeModeWorker?.dispose();
    _seedColorWorker?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
        title: 'Nexus',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(_settings.seedColor.value),
        darkTheme: AppTheme.dark(_settings.seedColor.value),
        themeMode: ThemeMode.values[_settings.themeMode.value],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
        locale: const Locale('zh', 'CN'),
        home: const HomePage(),
        navigatorObservers: [FlutterSmartDialog.observer],
        builder: (context, child) {
          child = FlutterSmartDialog.init()(context, child);
          // 全局兜底：无论当前路由/页面是否已经构建出自己的 AppBar，
          // 都强制保证状态栏透明、不出现系统默认灰色遮挡条。
          final brightness = Theme.of(context).brightness;
          return AnnotatedRegion<SystemUiOverlayStyle>(
            value: SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              statusBarIconBrightness:
                  brightness == Brightness.dark ? Brightness.light : Brightness.dark,
              statusBarBrightness:
                  brightness == Brightness.dark ? Brightness.dark : Brightness.light,
              systemNavigationBarColor: Colors.transparent,
              systemNavigationBarIconBrightness:
                  brightness == Brightness.dark ? Brightness.light : Brightness.dark,
            ),
            child: child,
          );
        },
        getPages: AppRoutes.pages,
    );
  }
}
