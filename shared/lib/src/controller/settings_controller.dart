import 'package:get/get.dart';
import '../player/player_backend.dart';
import '../storage/storage_service.dart';

/// 播放器后端选择。
/// - auto: 本地视频用 ExoPlayer，IPTV 用 MPV（按场景区分）
/// - exo: 全部使用 ExoPlayer
/// - mpv: 全部使用 MPV
/// - vlc: 全部使用 libVLC（Windows 上对 IPTV 直播流兼容性最好）
enum PlayerBackendChoice { auto, exo, mpv, vlc }

/// 手机端全屏播放时的屏幕旋转策略（平板端不使用此设置）。
/// - auto: 根据视频本身的宽高比决定——横屏视频旋转到横屏，竖屏视频保持竖屏
/// - portrait: 始终保持竖屏（不旋转），所有视频都以竖屏全屏播放
/// - landscape: 始终旋转到横屏（当前默认行为），所有视频都旋转到横屏播放
/// - sensor: 跟随传感器——手机实际朝向决定方向，允许四个方向自由旋转
enum FullScreenOrientationMode { auto, portrait, landscape, sensor }

/// Base settings that are common to ALL three apps.
/// Each app subclass adds its own platform-specific settings on top.
abstract class BaseSettingsController extends GetxController {
  // ── Playback ─────────────────────────────────────────────────────────────
  /// MPV 后端硬解开关（仅对 MPV 后端生效）。
  final hardwareDecode = true.obs;
  final mpvProfile     = 'balanced'.obs; // performance / balanced / quality
  final compatMode     = false.obs;      // Android MediaCodec compat

  /// VLC 后端硬解开关（仅对 VLC 后端生效，独立于 MPV 的 hardwareDecode）。
  final vlcHardwareDecode = true.obs;

  /// 本地视频播放后端选择（auto / exo / mpv / vlc），默认 auto。
  final playerBackend = PlayerBackendChoice.auto.obs;

  /// IPTV 专用后端选择（auto / exo / mpv / vlc），独立于本地视频后端。
  /// Windows 端默认 vlc（在 AppSettingsController.onInit 里迁移 auto→vlc）。
  final iptvBackend = PlayerBackendChoice.auto.obs;

  // ── Mobile: 全屏播放方向 ──────────────────────────────────────────────────
  /// 手机端全屏播放时的屏幕旋转策略。默认 auto（根据视频宽高比自动决定）。
  /// 平板端不读取此设置（始终保持当前宽屏布局，不旋转）。
  final fullScreenOrientation = FullScreenOrientationMode.auto.obs;

  // ── Media scan paths ─────────────────────────────────────────────────────
  final RxList<String> videoScanPaths = <String>[].obs;
  final RxList<String> musicScanPaths = <String>[].obs;

  // ── IPTV sources: [{name, url, type}] ────────────────────────────────────
  final RxList<Map<String, String>> iptvSources = <Map<String, String>>[].obs;

  // ── Recent files ─────────────────────────────────────────────────────────
  final RxList<String> recentFiles = <String>[].obs;

  // Sub-classes call this after StorageService.init()
  void loadBase() {
    hardwareDecode.value =
        StorageService.getValue(StorageService.kHardwareDecode, true);
    mpvProfile.value =
        StorageService.getValue(StorageService.kMpvProfile, 'balanced');
    compatMode.value =
        StorageService.getValue(StorageService.kCompatMode, false);

    // 播放器后端选择，老用户未设置则默认 auto
    final backendStr =
        StorageService.getValue(StorageService.kPlayerBackend, 'auto');
    playerBackend.value = _parseBackendChoice(backendStr);

    // IPTV 专用后端，默认 auto（Windows 端在子类 onInit 里迁移为 vlc）
    final iptvBackendStr =
        StorageService.getValue(StorageService.kIptvBackend, 'auto');
    iptvBackend.value = _parseBackendChoice(iptvBackendStr);

    // VLC 硬解开关
    vlcHardwareDecode.value =
        StorageService.getValue(StorageService.kVlcHardwareDecode, true);

    // 全屏播放方向（仅手机端生效）
    final orientStr = StorageService.getValue(
        StorageService.kFullScreenOrientation, 'auto');
    fullScreenOrientation.value = _parseOrientationMode(orientStr);

    videoScanPaths.value =
        StorageService.getValue<List>(StorageService.kVideoScanPaths, [])
            .cast<String>();
    musicScanPaths.value =
        StorageService.getValue<List>(StorageService.kMusicScanPaths, [])
            .cast<String>();

    iptvSources.value =
        StorageService.getValue<List>(StorageService.kIptvSources, [])
            .map((e) => Map<String, String>.from(e as Map))
            .toList();

    recentFiles.value =
        StorageService.getValue<List>(StorageService.kRecentFiles, [])
            .cast<String>();
  }

  // ── Playback setters ─────────────────────────────────────────────────────
  Future<void> setHardwareDecode(bool v) async {
    hardwareDecode.value = v;
    await StorageService.setValue(StorageService.kHardwareDecode, v);
  }

  Future<void> setMpvProfile(String v) async {
    mpvProfile.value = v;
    await StorageService.setValue(StorageService.kMpvProfile, v);
  }

  Future<void> setCompatMode(bool v) async {
    compatMode.value = v;
    await StorageService.setValue(StorageService.kCompatMode, v);
  }

  Future<void> setPlayerBackend(PlayerBackendChoice v) async {
    playerBackend.value = v;
    await StorageService.setValue(StorageService.kPlayerBackend, v.name);
  }

  Future<void> setIptvBackend(PlayerBackendChoice v) async {
    iptvBackend.value = v;
    await StorageService.setValue(StorageService.kIptvBackend, v.name);
  }

  Future<void> setVlcHardwareDecode(bool v) async {
    vlcHardwareDecode.value = v;
    await StorageService.setValue(StorageService.kVlcHardwareDecode, v);
  }

  /// 根据场景返回是否使用 ExoPlayer。
  /// - [isIptv] true 表示当前是 IPTV 直播场景，false 表示本地视频。
  /// - 若用户选了 exo/mpv/vlc，则全局生效；
  /// - 若选了 auto，则本地视频用 exo，IPTV 用 mpv。
  bool shouldUseExo({required bool isIptv}) {
    return resolveBackendType(isIptv: isIptv) == PlayerBackendType.exo;
  }

  /// 按场景解析最终应使用的后端类型。
  /// - 本地视频（isIptv=false）：看 [playerBackend]
  /// - IPTV（isIptv=true）：看 [iptvBackend]（独立于本地视频后端）
  /// - auto：本地视频用 exo，IPTV 用 mpv
  PlayerBackendType resolveBackendType({required bool isIptv}) {
    final choice = isIptv ? iptvBackend.value : playerBackend.value;
    switch (choice) {
      case PlayerBackendChoice.exo:
        return PlayerBackendType.exo;
      case PlayerBackendChoice.mpv:
        return PlayerBackendType.mpv;
      case PlayerBackendChoice.vlc:
        return PlayerBackendType.vlc;
      case PlayerBackendChoice.auto:
        return isIptv ? PlayerBackendType.mpv : PlayerBackendType.exo;
    }
  }

  Future<void> setFullScreenOrientation(FullScreenOrientationMode v) async {
    fullScreenOrientation.value = v;
    await StorageService.setValue(
        StorageService.kFullScreenOrientation, v.name);
  }

  FullScreenOrientationMode _parseOrientationMode(String s) {
    switch (s) {
      case 'portrait':
        return FullScreenOrientationMode.portrait;
      case 'landscape':
        return FullScreenOrientationMode.landscape;
      case 'sensor':
        return FullScreenOrientationMode.sensor;
      default:
        return FullScreenOrientationMode.auto;
    }
  }

  PlayerBackendChoice _parseBackendChoice(String s) {
    switch (s) {
      case 'exo':
        return PlayerBackendChoice.exo;
      case 'mpv':
        return PlayerBackendChoice.mpv;
      case 'vlc':
        return PlayerBackendChoice.vlc;
      default:
        return PlayerBackendChoice.auto;
    }
  }

  // ── Video scan paths ─────────────────────────────────────────────────────
  Future<void> addVideoScanPath(String path) async {
    if (!videoScanPaths.contains(path)) {
      videoScanPaths.add(path);
      await _saveVideoScanPaths();
    }
  }

  Future<void> removeVideoScanPath(String path) async {
    videoScanPaths.remove(path);
    await _saveVideoScanPaths();
  }

  Future<void> _saveVideoScanPaths() =>
      StorageService.setValue(StorageService.kVideoScanPaths, videoScanPaths.toList());

  // ── Music scan paths ─────────────────────────────────────────────────────
  Future<void> addMusicScanPath(String path) async {
    if (!musicScanPaths.contains(path)) {
      musicScanPaths.add(path);
      await _saveMusicScanPaths();
    }
  }

  Future<void> removeMusicScanPath(String path) async {
    musicScanPaths.remove(path);
    await _saveMusicScanPaths();
  }

  Future<void> _saveMusicScanPaths() =>
      StorageService.setValue(StorageService.kMusicScanPaths, musicScanPaths.toList());

  // ── IPTV sources ─────────────────────────────────────────────────────────
  Future<void> addIptvSource({
    required String name,
    required String url,
    String type = 'network',
  }) async {
    iptvSources.add({'name': name, 'url': url, 'type': type});
    await _saveIptvSources();
  }

  Future<void> removeIptvSource(int index) async {
    iptvSources.removeAt(index);
    await _saveIptvSources();
  }

  Future<void> _saveIptvSources() => StorageService.setValue(
      StorageService.kIptvSources,
      iptvSources.map((e) => Map<String, String>.from(e)).toList());

  // ── Recent files ─────────────────────────────────────────────────────────
  Future<void> addRecentFile(String path) async {
    recentFiles.remove(path);
    recentFiles.insert(0, path);
    if (recentFiles.length > 50) recentFiles.removeLast();
    await StorageService.setValue(StorageService.kRecentFiles, recentFiles.toList());
  }
}
