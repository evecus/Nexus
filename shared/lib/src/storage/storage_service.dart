import 'package:hive_flutter/hive_flutter.dart';

/// Thin Hive wrapper used by all three apps.
/// Each app opens its own box so settings are isolated.
class StorageService {
  static late Box _box;

  static Future<void> init({String boxName = 'player_settings'}) async {
    _box = await Hive.openBox(boxName);
  }

  static T getValue<T>(String key, T defaultValue) =>
      _box.get(key, defaultValue: defaultValue) as T;

  static Future<void> setValue<T>(String key, T value) =>
      _box.put(key, value);

  static Future<void> deleteValue(String key) => _box.delete(key);

  // ── Key constants (shared across all apps) ──────────────────────────────
  static const kHardwareDecode  = 'hw_decode';
  static const kMpvProfile      = 'mpv_profile';
  static const kCompatMode      = 'compat_mode';
  static const kIptvSources     = 'iptv_sources';
  static const kVideoScanPaths  = 'video_scan_paths';
  static const kMusicScanPaths  = 'music_scan_paths';
  static const kRecentFiles     = 'recent_files';
  static const kPlayerVolume    = 'player_volume';

  // 播放器后端选择（本地视频）: 'auto' | 'exo' | 'mpv' | 'vlc'
  // auto = 本地视频用 exo（Android）/ mpv（Windows 回退）
  static const kPlayerBackend   = 'player_backend';

  // IPTV 专用后端选择: 'auto' | 'exo' | 'mpv' | 'vlc'
  // 独立于本地视频后端，允许 IPTV 用 vlc 而本地视频用 mpv。
  // Windows 端默认 vlc（在 AppSettingsController.onInit 里迁移）。
  static const kIptvBackend     = 'iptv_backend';

  // VLC 专属硬解开关（独立于 MPV 的 kHardwareDecode）
  static const kVlcHardwareDecode = 'vlc_hw_decode';

  // Mobile / Windows only
  static const kThemeMode       = 'theme_mode';
  static const kSeedColor       = 'seed_color';

  // ── Mobile only: 全屏播放方向 ─────────────────────────────────────────────
  // 值为 FullScreenOrientationMode.name（枚举名字符串），如
  // 'auto' / 'portrait' / 'landscape' / 'sensor'
  static const kFullScreenOrientation = 'fullscreen_orientation';

  // ── Windows: 视频库排序 ──────────────────────────────────────────────────
  // 值为 SortMode.name（枚举名字符串），如 'name' / 'size' / 'ext'
  static const kVideoSortMode   = 'video_sort_mode';

  // ── Windows: 视频缩略图路径缓存 ──────────────────────────────────────────
  // { videoFilePath: thumbnailFilePath }，避免每次启动都重新截图生成。
  static const kVideoThumbCache = 'video_thumb_cache';

  // ── Windows: 音乐库分类 / 排序 ───────────────────────────────────────────
  // category: MusicCategory 枚举名，如 'song' / 'album' / 'artist'
  static const kMusicCategory   = 'music_category';
  // songSort: SongSortMode 枚举名
  static const kMusicSongSort   = 'music_song_sort';
  // groupSort: GroupSortMode 枚举名
  static const kMusicGroupSort  = 'music_group_sort';

  // ── Windows: 音乐库扫描结果缓存 ──────────────────────────────────────────
  // 序列化后的 { path: [ {title, artist, album, path, name, size, modifiedMs}, ... ] }
  // 用于避免每次启动/进入音乐页都重新扫描磁盘和重新解析 ID3 标签。
  static const kMusicLibraryCache = 'music_library_cache';

  // ── Android: 视频库分类 / 文件夹排序 ──────────────────────────────────────
  // Android 端固定扫描设备存储根目录(无多路径概念),分类/排序 key 与
  // Windows 的 kVideoSortMode(平铺排序)区分开，避免混用导致语义错乱。
  static const kVideoCategory      = 'video_category';   // VideoCategory 索引(int)
  static const kVideoSortAndroid   = 'video_sort_android'; // VideoSort 索引(int)。
  // 注意:不复用 Windows 的 kVideoSortMode —— 那边存的是 SortMode 的枚举名
  // 字符串(如 'name'/'size'/'ext'),这里 Android 端存的是 int 索引，
  // 语义和类型都不同，用独立 key 避免混淆(各平台 Hive box 本身也是隔离的，
  // 但独立 key 更清晰、也更安全)。
  static const kVideoFolderSort    = 'video_folder_sort'; // VideoFolderSort 索引(int)

  // ── Android: 视频库扫描结果缓存 ───────────────────────────────────────────
  // 序列化后的 List<{path, name, folder, size, modifiedMs, thumbPath}>。
  // 用于"进入视频页时,若已有缓存则直接展示,不再自动重新扫描"。
  static const kVideoLibraryCache  = 'video_library_cache_android';

  // ── Android: 音乐库扫描结果缓存 ───────────────────────────────────────────
  // 与 Windows 的 kMusicLibraryCache 结构不同(Android 无多路径分组),
  // 单独用一个 key 存 List<{path, name, folder, size, modifiedMs,
  // title, artist, album, coverPath, lyrics}>。
  static const kMusicLibraryCacheAndroid = 'music_library_cache_android';

  // ── Android TV: 视频库扫描结果缓存 / 排序 ─────────────────────────────────
  // 结构/语义与 Android 手机端相同(kVideoSortAndroid/kVideoLibraryCache),
  // 但 TV 是独立 App(独立 Hive box),用独立 key 便于区分调试。
  static const kVideoSortTv          = 'video_sort_tv';
  static const kVideoLibraryCacheTv  = 'video_library_cache_tv';

  // ── Android TV: 音乐库扫描结果缓存 ────────────────────────────────────────
  // 结构与 kMusicLibraryCacheAndroid 相同,但 TV 是独立的 App(独立 Hive
  // box),这里仍然用独立 key 是为了让两个平台各自的缓存内容在代码里
  // 一目了然地区分开,便于以后分别调试/清理。
  static const kMusicLibraryCacheTv = 'music_library_cache_tv';
}
