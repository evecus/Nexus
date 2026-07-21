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

    await trayManager.setIcon(
      'assets/icons/app_icon.ico',
    );
    await trayManager.setToolTip('Nexus');

    final menu = Menu(items: [
      MenuItem(key: 'show_window', label: '显示主窗口'),
      MenuItem.separator(),
      MenuItem(key: 'exit_app', label: '退出'),
    ]);
    await trayManager.setContextMenu(menu);
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
