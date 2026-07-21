/// 艺术家字符串切分工具(手机端与 TV 端共用)。
///
/// 音乐库按"艺术家"分组时,一首歌可能有多个合作艺术家写在同一个字段里
/// (如 "周杰伦 / 阿信"、"A feat. B"),需要切分成多个独立的分组 key,
/// 让同一首歌出现在每个艺术家的分组下。
class ArtistSplitter {
  ArtistSplitter._();

  static List<String> split(String artist) {
    if (artist.isEmpty) return ['未知艺术家'];
    // 标准化分隔符
    var s = artist;
    for (final sep in ['feat.', 'ft.', 'vs.', 'Feat.', 'Ft.', 'Vs.']) {
      s = s.replaceAll(sep, '|');
    }
    for (final sep in ['/', ',', '&', '×', '·', '、', ';', '；']) {
      s = s.replaceAll(sep, '|');
    }
    final parts = s
        .split('|')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();
    return parts.isEmpty ? ['未知艺术家'] : parts;
  }
}
