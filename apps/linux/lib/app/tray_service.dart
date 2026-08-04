import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

/// 系统托盘服务：
/// - 把程序图标显示在任务栏通知区域（系统托盘）
/// - 点击托盘图标 → 还原/显示主窗口
/// - 关闭窗口按钮 → 隐藏到托盘而不是直接退出进程（后台可继续播放音乐）
/// - 托盘右键菜单提供"显示主窗口"和"退出"选项
///
/// 需要在 [WindowOptions] 里设置 windowManager.setPreventClose(true)，
/// 否则点击窗口关闭按钮会直接杀掉进程，不会走到 onWindowClose 回调。
///
/// 【与 Windows 端的差异】Windows 端托盘图标用 .ico 格式
/// （assets/icons/app_icon.ico）。Linux 下系统托盘（大多数桌面环境走
/// StatusNotifierItem/AppIndicator 协议）不认 .ico，tray_manager 在
/// Linux 上需要 .png（或 .svg，视具体桌面环境的图标主题引擎而定），
/// 因此这里改用 assets/icons/app_icon.png（与应用图标同一份文件，pubspec
/// assets 里已声明 assets/icons/ 整个目录，无需额外新增资源）。
///
/// 【风险点】不同 Linux 桌面环境（GNOME/KDE/XFCE 等）对系统托盘的支持
/// 程度不一致——尤其纯 GNOME（未装 AppIndicator/KStatusNotifierItem 扩展）
/// 可能根本不显示任何托盘图标。这不是本应用代码的 bug，是 tray_manager
/// 依赖的底层协议在该环境下不可用；托盘不可用时"关闭窗口隐藏而非退出"的
/// 行为仍然生效，只是没有图标可点击唤起窗口，此时可通过任务栏/Alt+Tab
/// 或重新启动程序来恢复窗口。
class TrayService with TrayListener, WindowListener {
  static final TrayService instance = TrayService._();
  TrayService._();

  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    trayManager.addListener(this);
    windowManager.addListener(this);

    // 阻止默认关闭行为（直接退出进程），改为在 onWindowClose 里隐藏到托盘。
    await windowManager.setPreventClose(true);

    // 【风险点】tray_manager 依赖平台原生实现（Linux 下通过
    // libayatana-appindicator / StatusNotifierItem 协议）。如果构建产物里
    // 插件注册表缺失该插件的原生端（例如打包时未正确执行
    // `flutter build linux`、或该发行版/桌面环境不支持系统托盘协议），
    // 这里的调用会抛出 MissingPluginException。
    // main() 中这段代码执行在 runApp() 之前，任何未捕获异常都会直接
    // 终止 Dart 主 isolate，导致 Flutter 引擎从未开始渲染——表现为窗口
    // 已创建但内容全黑。因此托盘初始化必须整体 try/catch，任何失败都
    // 只降级为"没有托盘图标"，不能阻塞应用启动。
    try {
      await trayManager.setIcon(
        'assets/icons/app_icon.png',
      );
      await trayManager.setToolTip('Nexus');

      final menu = Menu(items: [
        MenuItem(key: 'show_window', label: '显示主窗口'),
        MenuItem.separator(),
        MenuItem(key: 'exit_app', label: '退出'),
      ]);
      await trayManager.setContextMenu(menu);
    } catch (e, st) {
      // 托盘不可用时，"关闭窗口隐藏而非退出"的行为仍然生效（见类注释），
      // 只是没有图标可点击唤起窗口。打印日志方便定位，但绝不能让异常
      // 冒泡到 main()。
      // ignore: avoid_print
      print('TrayService.init: 系统托盘初始化失败，已降级为不显示托盘图标。原因: $e\n$st');
    }
  }

  void dispose() {
    trayManager.removeListener(this);
    windowManager.removeListener(this);
  }

  // ── TrayListener ─────────────────────────────────────────────────────────

  @override
  void onTrayIconMouseDown() {
    // 单击托盘图标：还原并聚焦主窗口（类似截图中"点击任务栏图标显示窗口"）。
    _showWindow();
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show_window':
        _showWindow();
        break;
      case 'exit_app':
        _exitApp();
        break;
    }
  }

  // ── WindowListener ───────────────────────────────────────────────────────

  @override
  void onWindowClose() async {
    // 用户点击了窗口的关闭按钮：隐藏窗口而不是退出进程，
    // 这样音乐可以继续在后台播放，任务栏/托盘图标仍然可点击唤起窗口。
    final isPreventClose = await windowManager.isPreventClose();
    if (isPreventClose) {
      await windowManager.hide();
    }
  }

  Future<void> _showWindow() async {
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> _exitApp() async {
    await trayManager.destroy();
    await windowManager.setPreventClose(false);
    await windowManager.close();
  }
}
