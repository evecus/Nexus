import 'package:get/get.dart';
import 'package:nexus_tv/modules/home/tv_home_page.dart';
import 'package:nexus_tv/modules/video/tv_video_page.dart';
import 'package:nexus_tv/modules/video/player/tv_video_player_page.dart';
import 'package:nexus_tv/modules/iptv/playlist/tv_iptv_playlist_page.dart';
import 'package:nexus_tv/modules/iptv/player/tv_iptv_player_page.dart';
import 'package:nexus_tv/modules/music/library/tv_music_library_page.dart';
import 'package:nexus_tv/modules/music/player/tv_music_player_page.dart';
import 'package:nexus_tv/modules/settings/tv_settings_page.dart';

abstract class TvRoutes {
  static const home         = '/';
  static const video        = '/video';
  static const videoPlayer  = '/video/player';
  static const iptv         = '/iptv';
  static const iptvPlayer   = '/iptv/player';
  static const music        = '/music';
  static const musicPlayer  = '/music/player';
  static const settings     = '/settings';

  static final pages = [
    GetPage(name: home,         page: () => const TvHomePage()),
    GetPage(name: video,        page: () => const TvVideoPage()),
    GetPage(name: videoPlayer,  page: () => const TvVideoPlayerPage()),
    GetPage(name: iptv,         page: () => const TvIptvPlaylistPage()),
    GetPage(name: iptvPlayer,   page: () => const TvIptvPlayerPage()),
    GetPage(name: music,        page: () => const TvMusicLibraryPage()),
    GetPage(name: musicPlayer,  page: () => const TvMusicPlayerPage()),
    GetPage(name: settings,     page: () => const TvSettingsPage()),
  ];
}

class TvNavigator {
  /// 进入视频全屏播放页。
  /// [playlist] 为待播放列表,每个元素 {'path':..., 'name':...};
  /// [index] 为初始播放项索引。
  /// [resumePosition] 可选：从顶部播放入口恢复播放时携带的初始跳转位置。
  static void toVideoPlayer({
    required List<Map<String, String>> playlist,
    required int index,
    Duration? resumePosition,
  }) {
    Get.toNamed(TvRoutes.videoPlayer, arguments: {
      'playlist': playlist,
      'index': index,
      if (resumePosition != null) 'resumePosition': resumePosition,
    });
  }

  /// 进入 IPTV 全屏播放页。
  /// [sourceIndex] 为要加载的 IPTV 源在 `iptvSources` 中的索引,
  /// 播放页会自行加载该源的全部频道,并默认播放第一个频道的第一个线路。
  /// [channelName]/[groupName] 可选：从顶部播放入口恢复播放时携带，
  /// 若提供则加载源后直接定位播放该频道，而非默认的第一个频道。
  static void toIptvPlayer({
    required int sourceIndex,
    String? channelName,
    String? groupName,
  }) {
    Get.toNamed(TvRoutes.iptvPlayer, arguments: {
      'sourceIndex': sourceIndex,
      if (channelName != null) 'channelName': channelName,
      if (groupName != null) 'groupName': groupName,
    });
  }

  static void toMusicPlayer(
      {required List<Map<String, String>> playlist, required int index}) {
    Get.toNamed(TvRoutes.musicPlayer,
        arguments: {'playlist': playlist, 'index': index});
  }

  /// 从顶部播放入口进入音乐播放页，继续展示当前播放中的内容（不携带新歌单）。
  static void toMusicPlayerResume() {
    Get.toNamed(TvRoutes.musicPlayer);
  }
}
