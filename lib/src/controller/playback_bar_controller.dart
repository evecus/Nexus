import 'package:get/get.dart';

/// 底部/侧边"迷你播放栏"当前展示的媒体类型。
enum PlaybackBarKind { none, video, iptv, music }

/// 全局单例：记录"退出播放页后"应在迷你播放栏中展示的媒体信息。
///
/// 设计原则：
/// - 视频 / 音乐 / IPTV 三种媒体播放互斥：开始播放其中一种会停止另外两种，
///   所以任意时刻最多只有一种媒体真正在播放或"最近播放过"。
/// - 音乐播放器（MusicPlayerController）本身就是全局常驻单例，退出音乐播放页
///   不会停止播放，所以音乐的展示信息直接从 MusicPlayerController 的 Rx 状态读取，
///   不需要在这里存一份快照，但仍需在开始播放音乐时调用 [markMusicActive] 更新
///   [kind]，以便迷你播放栏知道"当前最近播放的是音乐"。
/// - 视频 / IPTV 播放器随播放页面创建和销毁（退出即停止），所以退出时需要把
///   "足够恢复播放"的信息（路径、标题、进度、播放列表等）快照保存在这里，
///   由迷你播放栏读取展示，并在用户点击时用这些信息重新进入播放页。
/// - [kind] 表示视频 / IPTV / 音乐三者之中，最近一次开始播放的是谁 —— 迷你
///   播放栏同一时刻只展示这一种媒体的信息（单行），而不是分别展示。
class PlaybackBarController extends GetxController {
  static PlaybackBarController get instance =>
      Get.find<PlaybackBarController>();

  final Rx<PlaybackBarKind> kind = PlaybackBarKind.none.obs;

  // ── 视频快照 ──────────────────────────────────────────────────────────────
  final RxString videoTitle = ''.obs;
  final RxString videoPath  = ''.obs;
  final Rx<Duration> videoPosition = Duration.zero.obs;
  final Rx<Duration> videoDuration = Duration.zero.obs;
  /// 完整播放列表快照，恢复播放时原样传回播放页。
  List<Map<String, String>> videoPlaylist = const [];
  int videoIndex = 0;

  // ── IPTV 快照 ─────────────────────────────────────────────────────────────
  final RxString iptvChannelName = ''.obs;
  final RxString iptvGroupName   = ''.obs;
  final RxString iptvUrl         = ''.obs;
  int iptvSourceIndex = 0;

  /// 视频播放页退出时调用：保存快照，供迷你播放栏展示 + 后续恢复播放。
  void saveVideoSnapshot({
    required String title,
    required String path,
    required Duration position,
    required Duration duration,
    required List<Map<String, String>> playlist,
    required int index,
  }) {
    videoTitle.value = title;
    videoPath.value = path;
    videoPosition.value = position;
    videoDuration.value = duration;
    videoPlaylist = playlist;
    videoIndex = index;
    kind.value = PlaybackBarKind.video;
  }

  /// IPTV 播放页退出时调用：保存快照，供迷你播放栏展示 + 后续恢复播放。
  void saveIptvSnapshot({
    required String channelName,
    required String groupName,
    required String url,
    required int sourceIndex,
  }) {
    iptvChannelName.value = channelName;
    iptvGroupName.value = groupName;
    iptvUrl.value = url;
    iptvSourceIndex = sourceIndex;
    kind.value = PlaybackBarKind.iptv;
  }

  /// 音乐开始播放时调用：标记"最近播放的是音乐"，让迷你播放栏切换展示音乐行。
  /// 音乐本身的标题/进度等信息由 MusicPlayerController 的 Rx 状态直接提供，
  /// 这里不需要存快照，只需要更新 [kind]。
  void markMusicActive() {
    kind.value = PlaybackBarKind.music;
  }

  /// 用户点击了视频/IPTV 迷你播放栏之外的入口重新开始播放新内容时，
  /// 或者主动清空迷你播放栏时调用。
  void clear() {
    kind.value = PlaybackBarKind.none;
  }

  /// 是否存在可展示的媒体信息（视频/IPTV 快照，或音乐正在播放）。
  bool get hasSnapshot => kind.value != PlaybackBarKind.none;
}
