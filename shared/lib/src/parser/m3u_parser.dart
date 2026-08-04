/// Simple M3U/M3U8 parser.
/// Handles both extended (#EXTM3U / #EXTINF) and plain URL-per-line formats.
class M3uChannel {
  final String name;
  final String url;
  final String group;
  final String logo;
  final String id;

  const M3uChannel({
    required this.name,
    required this.url,
    this.group = '未分组',
    this.logo = '',
    this.id = '',
  });
}

class M3uParser {
  static List<M3uChannel> parse(String content) {
    final lines = content.split(RegExp(r'\r?\n'));
    final channels = <M3uChannel>[];

    String name = '', group = '未分组', logo = '', id = '';

    for (final raw in lines) {
      final line = raw.trim();
      if (line.isEmpty || line == '#EXTM3U') continue;

      if (line.startsWith('#EXTINF:')) {
        name  = _attr(line, 'tvg-name') ?? _attr(line, 'title') ?? _commaName(line);
        group = _attr(line, 'group-title') ?? '未分组';
        logo  = _attr(line, 'tvg-logo') ?? '';
        id    = _attr(line, 'tvg-id') ?? '';
      } else if (!line.startsWith('#')) {
        channels.add(M3uChannel(
          name:  name.isEmpty ? _guessName(line) : name,
          url:   line,
          group: group,
          logo:  logo,
          id:    id,
        ));
        name = ''; group = '未分组'; logo = ''; id = '';
      }
    }
    return channels;
  }

  static String? _attr(String line, String key) {
    final m = RegExp('$key="([^"]*)"', caseSensitive: false).firstMatch(line);
    return m?.group(1)?.trim();
  }

  static String _commaName(String line) {
    final idx = line.lastIndexOf(',');
    return idx < 0 ? '' : line.substring(idx + 1).trim();
  }

  static String _guessName(String url) {
    try {
      return Uri.parse(url).pathSegments.last.split('.').first;
    } catch (_) {
      return url;
    }
  }

  /// Group channels by group-title, preserving insertion order.
  static Map<String, List<M3uChannel>> groupBy(List<M3uChannel> channels) {
    final map = <String, List<M3uChannel>>{};
    for (final ch in channels) {
      map.putIfAbsent(ch.group, () => []).add(ch);
    }
    return map;
  }
}
