import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // 本 App 自带的原生桥接(目录书签管理，见 NexusDirectoryBookmark.swift)
    // 不是 pub.dev 插件，不会被 GeneratedPluginRegistrant 自动注册，
    // 需要手动注册一次。对应 Dart 侧 lib/bookmarks/ios_directory_bookmark.dart。
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "NexusDirectoryBookmark") {
      NexusDirectoryBookmark.register(with: registrar)
    }
  }
}
