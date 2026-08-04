import 'dart:typed_data';

import 'package:path/path.dart' as p;

/// 歌曲项(手机端与 TV 端共用)。
///
/// 初始扫描只填充文件信息;元数据(标题/歌手/专辑/歌词)由后台异步
/// 加载,加载完成后与文件列表一起序列化进本地缓存(各 app 在
/// `StorageService` 里各自的音乐库缓存 key),下次进入音乐页时可以直接从
/// 缓存恢复,不需要重新扫描磁盘、重新解析 ID3 标签。
class SongEntry {
  final String path;
  final String name;
  final String folder;
  final int size;
  final int modified;
  String title;
  String artist;
  String album;
  bool metadataLoaded;

  /// 封面图片在磁盘缓存目录中的文件路径。
  ///
  /// 历史字段：早期版本会把 ID3/FLAC/OGG 解析出的封面写入磁盘文件、
  /// 只存路径。现在手机端、Android TV 端、Windows 端已统一改为"只在
  /// 内存里持有封面字节，不落盘"的策略(见下面的 [coverBytes] 和
  /// `AudioCoverMemoryCache`)，扫描/展示时不再写入这个字段。
  /// 保留这个字段只是为了兼容旧版本写入的 Hive 缓存数据格式，
  /// 避免升级后读取旧缓存时因为字段缺失而崩溃；新写入的缓存里这个
  /// 字段恒为空字符串。
  String coverPath;

  /// 歌词文本(LRC 格式,来自内嵌 USLT 帧或同名外部 .lrc 文件);
  /// 空字符串表示没有歌词,或还未加载。
  String lyrics;

  /// 封面图片的原始字节(仅内存,不会被 [toJson] 序列化进 Hive 缓存)。
  ///
  /// 手机端 / Android TV 端音乐库列表、分组详情页、播放页展示封面时
  /// 都使用这个字段：按"当前展示列表"分批增量读取(默认每批 200 首，
  /// 见 `AudioCoverMemoryCache`)，只留在内存里；App 重启或者列表页被
  /// 销毁重建后这个字段会丢失，下次显示时会按同样的分批策略重新读取
  /// ——这正是预期行为，用极小的重复解析开销换取不占用任何本地存储
  /// 空间。Windows 端使用同名机制，但由独立的 `RichMusicFile` 承载
  /// (见 rich_music_file.dart)。
  Uint8List? coverBytes;

  SongEntry({
    required this.path,
    required this.name,
    required this.folder,
    required this.size,
    required this.modified,
    this.title = '',
    this.artist = '',
    this.album = '',
    this.metadataLoaded = false,
    this.coverPath = '',
    this.lyrics = '',
    this.coverBytes,
  });

  Map<String, String> toMap() => {
        'path': path,
        'name': name,
        'coverPath': coverPath,
        'lyrics': lyrics,
      };

  /// 序列化为可存入 Hive 的纯 Map。
  ///
  /// 注意：故意不包含 [coverBytes]——封面原始字节体积较大，写进 Hive
  /// 缓存会让扫描结果缓存膨胀到几十甚至上百 MB，读写都会变慢，也完全
  /// 违背"不占用本地存储"的初衷。[coverBytes] 只在当前运行时的内存里
  /// 有效，App 重启后会在下次显示时重新从文件读取。
  Map<String, dynamic> toJson() => {
        'path': path,
        'name': name,
        'folder': folder,
        'size': size,
        'modified': modified,
        'title': title,
        'artist': artist,
        'album': album,
        'coverPath': coverPath,
        'lyrics': lyrics,
      };

  /// 从缓存的 Map 还原。字段缺失时给出安全默认值,避免旧缓存格式导致崩溃。
  factory SongEntry.fromJson(Map<dynamic, dynamic> json) {
    return SongEntry(
      path: (json['path'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      folder: (json['folder'] as String?) ?? '',
      size: (json['size'] as num?)?.toInt() ?? 0,
      modified: (json['modified'] as num?)?.toInt() ?? 0,
      title: (json['title'] as String?) ?? '',
      artist: (json['artist'] as String?) ?? '',
      album: (json['album'] as String?) ?? '',
      metadataLoaded: true,
      coverPath: (json['coverPath'] as String?) ?? '',
      lyrics: (json['lyrics'] as String?) ?? '',
    );
  }

  /// 从扫描结果构建初始条目(标题先用文件名去扩展名,元数据待后台加载)。
  factory SongEntry.fromScan({
    required String path,
    required String name,
    required String folder,
    required int size,
    required int modified,
  }) {
    return SongEntry(
      path: path,
      name: name,
      folder: folder,
      size: size,
      modified: modified,
      title: p.withoutExtension(name),
    );
  }
}
