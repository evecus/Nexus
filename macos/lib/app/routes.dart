import 'package:get/get.dart';

import '../modules/video/player/video_player_page.dart';
import '../modules/iptv/player/iptv_player_page.dart';
import '../modules/music/player/music_player_page.dart';

abstract class AppRoutes {
  static const videoPlayer = '/video/player';
  static const iptvPlayer  = '/iptv/player';
  static const musicPlayer = '/music/player';

  static final pages = [
    GetPage(name: videoPlayer, page: () => const VideoPlayerPage()),
    GetPage(name: iptvPlayer,  page: () => const IptvPlayerPage()),
    GetPage(name: musicPlayer, page: () => const MusicPlayerPage()),
  ];
}

class AppNavigator {
  static void toVideoPlayer({
    required String url,
    String title = '',
    bool isLocal = false,
  }) =>
      Get.toNamed(AppRoutes.videoPlayer,
          arguments: {'url': url, 'title': title, 'isLocal': isLocal});

  static void toIptvPlayer({
    required String url,
    required String channelName,
    String groupName = '',
    int sourceIndex = 0,
  }) =>
      Get.toNamed(AppRoutes.iptvPlayer,
          arguments: {
            'url': url,
            'channelName': channelName,
            'groupName': groupName,
            'sourceIndex': sourceIndex,
          });

  /// 由底部播放栏调用：使用上次保存的频道参数重新进入 IPTV 播放页续播。
  static void resumeIptvPlayer(Map<String, dynamic> resumeArgs) =>
      Get.toNamed(AppRoutes.iptvPlayer, arguments: resumeArgs);

  static void toMusicPlayer({
    required List<Map<String, String>> playlist,
    required int index,
  }) =>
      Get.toNamed(AppRoutes.musicPlayer,
          arguments: {'playlist': playlist, 'index': index});
}
