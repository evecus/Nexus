import 'package:get/get.dart';

import '../modules/video/player/video_player_page.dart';
import '../modules/video/local/video_folder_page.dart';
import '../modules/iptv/player/iptv_player_page.dart';
import '../modules/music/player/music_player_page.dart';
import '../modules/music/library/music_group_page.dart';
import '../modules/settings/directory_manager_page.dart';

abstract class AppRoutes {
  static const videoPlayer = '/video/player';
  static const videoFolder = '/video/folder';
  static const iptvPlayer = '/iptv/player';
  static const musicPlayer = '/music/player';
  static const musicGroup = '/music/group';
  // iOS 专属:管理"已导入目录"的页面(见 directory_manager_page.dart 顶部
  // 注释,对应 Android 端"自动扫描整个设备存储"在 iOS 沙盒下的替代方案)。
  static const directoryManager = '/settings/directories';

  static final pages = [
    GetPage(name: videoPlayer, page: () => const VideoPlayerPage()),
    GetPage(name: videoFolder, page: () => const VideoFolderPage()),
    GetPage(name: iptvPlayer, page: () => const IptvPlayerPage()),
    GetPage(name: musicPlayer, page: () => const MusicPlayerPage()),
    GetPage(name: musicGroup, page: () => const MusicGroupPage()),
    GetPage(name: directoryManager, page: () => const DirectoryManagerPage()),
  ];
}

class AppNavigator {
  /// 进入视频播放页。
  ///
  /// [playlist] 是 `{'path': String, 'name': String}` 的列表,可表示单个文件、
  /// 一个文件夹内的多个视频,或单个 URL。
  static void toVideoPlayer({
    required List<Map<String, String>> playlist,
    required int index,
    Duration? resumePosition,
  }) =>
      Get.toNamed(AppRoutes.videoPlayer, arguments: {
        'playlist': playlist,
        'index': index,
        if (resumePosition != null) 'resumePosition': resumePosition,
      });

  /// 进入视频文件夹详情页(展示某文件夹内的视频列表)。
  static void toVideoFolder({
    required String folderPath,
    required String folderName,
    required int sort,
    required List<Map<String, String>> videos,
  }) =>
      Get.toNamed(AppRoutes.videoFolder, arguments: {
        'folderPath': folderPath,
        'folderName': folderName,
        'sort': sort,
        'videos': videos,
      });

  static void toIptvPlayer({
    required String url,
    required String channelName,
    String groupName = '',
    int sourceIndex = 0,
  }) =>
      Get.toNamed(AppRoutes.iptvPlayer, arguments: {
        'url': url,
        'channelName': channelName,
        'groupName': groupName,
        'sourceIndex': sourceIndex,
      });

  /// 进入音乐播放页。
  static void toMusicPlayer({
    required List<Map<String, String>> playlist,
    required int index,
  }) =>
      Get.toNamed(AppRoutes.musicPlayer,
          arguments: {'playlist': playlist, 'index': index});

  /// 进入音乐分组详情页(展示某专辑/艺术家/文件夹下的歌曲列表)。
  static void toMusicGroup({
    required String title,
    required List<Map<String, String>> songs,
    int sort = 0,
  }) =>
      Get.toNamed(AppRoutes.musicGroup,
          arguments: {'title': title, 'songs': songs, 'sort': sort});
}
