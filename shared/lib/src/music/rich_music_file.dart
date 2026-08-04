/// 扩展的本地音乐文件模型。
///
/// 封装 [MusicFile] 并补充从 ID3 标签读取的
/// title / artist / album 以及文件修改时间，
/// 供音乐库分类/排序和播放器页面共同使用。

import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:player_shared/player_shared.dart';

class RichMusicFile {
  final MusicFile base;

  /// 歌曲名（ID3 TIT2，若无则为文件名去扩展名）
  final String title;

  /// 艺术家（ID3 TPE1，若无则为空字符串）
  final String artist;

  /// 专辑（ID3 TALB，若无则为空字符串）
  final String album;

  /// 文件最后修改时间（毫秒时间戳），用于时间排序
  final int modifiedMs;

  /// 封面图片在磁盘缓存目录中的文件路径。
  ///
  /// 历史字段：早期版本会把封面写入磁盘文件、只存路径。现在 Windows
  /// 端已经和手机端/TV 端统一改为"只在内存里持有封面字节，不落盘"的
  /// 策略（见下面的 [coverBytes]），扫描逻辑不再写入这个字段。保留它
  /// 只是为了兼容旧版本写入的 Hive 缓存数据格式，避免升级后读取旧
  /// 缓存时因为字段缺失而崩溃；新写入的缓存里这个字段恒为空字符串。
  final String coverPath;

  /// 封面图片的原始字节（仅内存，不会被 [toJson] 序列化进 Hive 缓存）。
  ///
  /// Windows 端音乐库列表展示封面时使用这个字段：按"当前展示列表"
  /// 分批增量读取（默认每批 200 首，见 `AudioCoverMemoryCache`），只
  /// 留在内存里；应用重启或者列表被重新扫描后这个字段会丢失，下次
  /// 显示时会按同样的分批策略重新读取——这是预期行为，用很小的重复
  /// 解析开销换取不占用任何本地存储空间。
  ///
  /// 注意：[RichMusicFile] 的其余字段都是 `final`（值对象风格），但
  /// [coverBytes] 需要在对象创建后由封面分批加载器异步回填，因此特意
  /// 设计成可写的可变字段，而不是要求每次都整体替换对象。
  Uint8List? coverBytes;

  RichMusicFile({
    required this.base,
    required this.title,
    required this.artist,
    required this.album,
    required this.modifiedMs,
    this.coverPath = '',
    this.coverBytes,
  });

  String get path       => base.path;
  String get name       => base.name;
  int    get size       => base.size;
  bool   get hasCover   => coverBytes != null && coverBytes!.isNotEmpty;

  /// 转为播放器所需的 Map 格式
  Map<String, String> toPlayMap() => {'path': path, 'name': name};

  /// 从已读取的 ID3 元数据构建（由扫描逻辑调用）。
  /// 注意：不在这里传入封面字节——封面改为按"当前展示列表"分批增量
  /// 加载，扫描阶段只负责文本元数据（标题/歌手/专辑）。
  factory RichMusicFile.fromMetadata({
    required MusicFile   base,
    required String?     metaTitle,
    required String?     metaArtist,
    required String?     metaAlbum,
    required int         modifiedMs,
  }) {
    final nameNoExt = p.withoutExtension(base.name);

    final title  = (metaTitle  != null && metaTitle.isNotEmpty)  ? metaTitle  : nameNoExt;
    final artist = (metaArtist != null && metaArtist.isNotEmpty) ? metaArtist : '';
    final album  = (metaAlbum  != null && metaAlbum.isNotEmpty)  ? metaAlbum  : '';

    return RichMusicFile(
      base:       base,
      title:      title,
      artist:     artist,
      album:      album,
      modifiedMs: modifiedMs,
    );
  }

  /// 序列化为可存入 Hive 的纯 Map（用于音乐库扫描结果缓存）。
  /// 注意：故意不包含 [coverBytes]——原因同 SongEntry.toJson：封面
  /// 体积大，不适合塞进 Hive 缓存。
  Map<String, dynamic> toJson() => {
        'path':       path,
        'name':       name,
        'size':       size,
        'title':      title,
        'artist':     artist,
        'album':      album,
        'modifiedMs': modifiedMs,
      };

  /// 从缓存的 Map 还原。字段缺失时给出安全默认值，避免旧缓存格式导致崩溃。
  /// 兼容旧版本缓存里可能存在的 'coverPath' 字段：读出来但只存进
  /// 兼容字段 [coverPath]，不会据此去读磁盘文件；封面统一走内存分批
  /// 加载。
  factory RichMusicFile.fromJson(Map<dynamic, dynamic> json) {
    return RichMusicFile(
      base: MusicFile(
        (json['path'] as String?) ?? '',
        (json['name'] as String?) ?? '',
        (json['size'] as num?)?.toInt() ?? 0,
      ),
      title:      (json['title']  as String?) ?? '',
      artist:     (json['artist'] as String?) ?? '',
      album:      (json['album']  as String?) ?? '',
      modifiedMs: (json['modifiedMs'] as num?)?.toInt() ?? 0,
      coverPath:  (json['coverPath'] as String?) ?? '',
    );
  }
}
