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
/// （assets/icons/app_icon.ico）。macOS 的菜单栏图标（NSStatusItem）不认
/// .ico，tray_manager 在 macOS 上需要 .png（内部通过 NSImage 加载），
/// 因此这里改用 assets/icons/app_icon.png（与应用图标同一份文件，pubspec
/// assets 里已声明 assets/icons/ 整个目录，无需额外新增资源）。
///
/// 【风险点】macOS 菜单栏图标默认按原图着色显示，与系统深色/浅色菜单栏
/// 背景可能对比度不佳；如需完全贴合 macOS 原生观感（自动适配深色模式的
/// 单色"模板图标"），可在 [init] 里改用
/// `trayManager.setIcon(path, isTemplate: true)` 并把 app_icon.png 换成
/// 单色透明背景的模板图（tray_manager 的 setIcon 支持 isTemplate 参数，
/// 仅在 macOS 上生效）。当前实现保持与 Windows/Linux 端完全一致的彩色
/// 图标，不启用 isTemplate，界面/操作逻辑三端统一。
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
      'assets/icons/app_icon.png',
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
