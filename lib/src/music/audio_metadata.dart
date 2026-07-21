/// 纯 Dart 音频元数据解析器，支持 MP3(ID3v2) / FLAC / OGG(Vorbis)。
///
/// 读取文件头部魔数判断实际格式(不依赖扩展名)，分别解析：
/// - MP3 (ID3v2.3 / ID3v2.4)
///   TIT2 → 歌名   TPE1 → 歌手   TALB → 专辑
///   APIC → 封面图（返回原始字节，由调用方解码为 Image）
///   USLT → 非同步嵌入歌词（LRC 文本）
/// - FLAC (METADATA_BLOCK)
///   VORBIS_COMMENT 块的 TITLE/ARTIST/ALBUM → 歌名/歌手/专辑
///   PICTURE 块 → 封面图原始字节
/// - OGG (Vorbis Comment Header，格式与 FLAC 的 VORBIS_COMMENT 一致)
///   TITLE/ARTIST/ALBUM → 歌名/歌手/专辑（暂不解析内嵌封面，较少见）
///
/// FLAC/OGG 均不含类似 ID3 USLT 的标准同步歌词字段，统一走"查找同名
/// .lrc / .LRC 外部文件"兜底。
///
/// 全程只读取文件前 256KB，不依赖任何三方包，可同时在
/// Windows / Android / iOS / macOS 使用，三端解析结果完全一致。

library audio_metadata;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

class AudioMetadata {
  final String? title;
  final String? artist;
  final String? album;
  /// APIC 帧原始图片字节（JPEG / PNG）；null 表示无封面
  final Uint8List? coverBytes;
  /// LRC 格式歌词文本；null 表示无歌词
  final String? lyrics;

  const AudioMetadata({
    this.title,
    this.artist,
    this.album,
    this.coverBytes,
    this.lyrics,
  });

  AudioMetadata copyWith({
    String? title,
    String? artist,
    String? album,
    Uint8List? coverBytes,
    String? lyrics,
  }) =>
      AudioMetadata(
        title:      title      ?? this.title,
        artist:     artist     ?? this.artist,
        album:      album      ?? this.album,
        coverBytes: coverBytes ?? this.coverBytes,
        lyrics:     lyrics     ?? this.lyrics,
      );
}

class AudioMetadataReader {
  static const int _kFetchBytes = 256 * 1024; // 256 KB

  /// 异步读取本地文件元数据，在调用方开启的 isolate / compute 中使用。
  ///
  /// 不依赖文件扩展名，而是读取文件头部魔数(magic number)判断实际格式，
  /// 扩展名被改错/缺失时依然能正确解析：
  /// - `ID3`            → MP3 (ID3v2)
  /// - `fLaC`           → FLAC
  /// - `OggS`           → OGG (Vorbis / Opus)
  /// 都不匹配时返回空元数据，调用方按"这首歌读不到信息"处理，不会崩溃。
  static Future<AudioMetadata> readFile(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) return const AudioMetadata();

    final fileLen = await file.length();
    final readLen = fileLen < _kFetchBytes ? fileLen : _kFetchBytes;

    final raf  = await file.open();
    final data = Uint8List(readLen);
    try {
      await raf.readInto(data);
    } finally {
      await raf.close();
    }

    AudioMetadata meta;
    if (_isId3(data)) {
      meta = _parseId3(data);
    } else if (_isFlac(data)) {
      meta = _parseFlac(data);
    } else if (_isOgg(data)) {
      meta = _parseOgg(data);
    } else {
      meta = const AudioMetadata();
    }

    // 若无内嵌歌词，查找外部 .lrc 文件(FLAC/OGG 走 Vorbis Comment 规范，
    // 没有类似 ID3 USLT 的标准同步歌词字段，因此统一都靠这条兜底路径)。
    if (meta.lyrics == null || meta.lyrics!.isEmpty) {
      final lrc = await _readSidecarLrc(filePath);
      if (lrc != null) {
        return meta.copyWith(lyrics: lrc);
      }
    }
    return meta;
  }

  // ── 格式嗅探 ───────────────────────────────────────────────────────────

  static bool _isId3(Uint8List data) =>
      data.length >= 3 && data[0] == 0x49 && data[1] == 0x44 && data[2] == 0x33; // "ID3"

  static bool _isFlac(Uint8List data) =>
      data.length >= 4 &&
      data[0] == 0x66 && data[1] == 0x4C && data[2] == 0x61 && data[3] == 0x43; // "fLaC"

  static bool _isOgg(Uint8List data) =>
      data.length >= 4 &&
      data[0] == 0x4F && data[1] == 0x67 && data[2] == 0x67 && data[3] == 0x53; // "OggS"

  // ── ID3v2 解析 ─────────────────────────────────────────────────────────

  static AudioMetadata _parseId3(Uint8List data) {
    if (data.length < 10) return const AudioMetadata();
    // 魔数 "ID3"
    if (data[0] != 0x49 || data[1] != 0x44 || data[2] != 0x33) {
      return const AudioMetadata();
    }

    final version = data[3]; // 3 = ID3v2.3, 4 = ID3v2.4
    final flags   = data[5];

    // Tag size (syncsafe)
    final tagSize = _syncsafeInt(data, 6) + 10;
    final limit   = tagSize < data.length ? tagSize : data.length;

    int pos = 10;

    // 跳过扩展头（flags bit 6）
    if ((flags & 0x40) != 0) {
      if (pos + 4 > limit) return const AudioMetadata();
      final extSize = version == 4
          ? _syncsafeInt(data, pos)
          : _readInt(data, pos);
      pos += extSize;
    }

    String?    title;
    String?    artist;
    String?    album;
    Uint8List? coverBytes;
    String?    lyrics;

    while (pos + 10 <= limit) {
      // Frame ID: 4 ASCII uppercase chars
      final b0 = data[pos];
      if (b0 < 0x41 || b0 > 0x5A) break; // padding area

      final frameId = String.fromCharCodes(data.sublist(pos, pos + 4));
      final frameSize = version == 4
          ? _syncsafeInt(data, pos + 4)
          : _readInt(data, pos + 4);
      pos += 10;

      if (frameSize <= 0 || pos + frameSize > data.length) break;

      final payload = data.sublist(pos, pos + frameSize);
      pos += frameSize;

      switch (frameId) {
        case 'TIT2':
          title  = _decodeText(payload);
          break;
        case 'TPE1':
          artist = _decodeText(payload);
          break;
        case 'TALB':
          album  = _decodeText(payload);
          break;
        case 'APIC':
          coverBytes = _decodePicture(payload);
          break;
        case 'USLT':
          final lrc = _decodeLyrics(payload);
          if (lrc != null && lrc.isNotEmpty) lyrics = lrc;
          break;
      }
    }

    return AudioMetadata(
      title:      title,
      artist:     artist,
      album:      album,
      coverBytes: coverBytes,
      lyrics:     lyrics,
    );
  }

  // ── 文本帧解码 ─────────────────────────────────────────────────────────

  static String? _decodeText(Uint8List payload) {
    if (payload.isEmpty) return null;
    final enc = payload[0];
    final raw = payload.sublist(1);
    try {
      String s;
      switch (enc) {
        case 1: // UTF-16 with BOM
          s = _decodeUtf16(raw);
          break;
        case 2: // UTF-16BE without BOM
          s = _decodeUtf16Be(raw);
          break;
        case 3: // UTF-8
          s = utf8.decode(raw, allowMalformed: true);
          break;
        default: // ISO-8859-1 / Latin-1
          s = latin1.decode(raw);
          break;
      }
      // 去掉 null terminator
      final nullIdx = s.indexOf('\x00');
      if (nullIdx >= 0) s = s.substring(0, nullIdx);
      final trimmed = s.trim();
      return trimmed.isEmpty ? null : trimmed;
    } catch (_) {
      return null;
    }
  }

  // ── APIC 封面解码 ──────────────────────────────────────────────────────

  static Uint8List? _decodePicture(Uint8List payload) {
    if (payload.length < 4) return null;
    final enc = payload[0];
    int pos = 1;

    // MIME type（null 结尾）
    while (pos < payload.length && payload[pos] != 0) pos++;
    pos++; // skip null
    if (pos >= payload.length) return null;

    // Picture type (1 byte)
    pos++;
    if (pos >= payload.length) return null;

    // Description（null 或 double-null 结尾）
    if (enc == 0 || enc == 3) {
      while (pos < payload.length && payload[pos] != 0) pos++;
      pos++;
    } else {
      // UTF-16: 双字节 null
      while (pos + 1 < payload.length &&
          !(payload[pos] == 0 && payload[pos + 1] == 0)) {
        pos += 2;
      }
      pos += 2;
    }
    if (pos >= payload.length) return null;
    return payload.sublist(pos);
  }

  // ── USLT 歌词解码 ──────────────────────────────────────────────────────

  static String? _decodeLyrics(Uint8List payload) {
    if (payload.length < 5) return null;
    final enc = payload[0];
    // lang: [1..3], desc starts at 4
    int pos = 4;
    if (enc == 0 || enc == 3) {
      while (pos < payload.length && payload[pos] != 0) pos++;
      pos++;
    } else {
      while (pos + 1 < payload.length &&
          !(payload[pos] == 0 && payload[pos + 1] == 0)) {
        pos += 2;
      }
      pos += 2;
    }
    if (pos >= payload.length) return null;
    final raw = payload.sublist(pos);
    try {
      String s;
      switch (enc) {
        case 1:
          s = _decodeUtf16(raw);
          break;
        case 2:
          s = _decodeUtf16Be(raw);
          break;
        case 3:
          s = utf8.decode(raw, allowMalformed: true);
          break;
        default:
          s = latin1.decode(raw);
          break;
      }
      s = s.replaceAll('\x00', '').trim();
      return s.isEmpty ? null : s;
    } catch (_) {
      return null;
    }
  }

  // ── FLAC 解析 ──────────────────────────────────────────────────────────
  //
  // FLAC 文件结构: 4 字节魔数 "fLaC" + 一串 METADATA_BLOCK。
  // 每个 block 的头是 4 字节:
  //   第 1 字节最高位(bit 7) = 是否是最后一个 block
  //   第 1 字节低 7 位       = block 类型(4 = VORBIS_COMMENT, 6 = PICTURE)
  //   接下来 3 字节(大端)     = block 数据长度
  // 只关心 VORBIS_COMMENT 和 PICTURE 这两种类型，其余类型(STREAMINFO、
  // SEEKTABLE、CUESHEET 等)按长度跳过，不解析内容。

  static AudioMetadata _parseFlac(Uint8List data) {
    if (data.length < 4) return const AudioMetadata();

    Map<String, String>? tags;
    Uint8List? coverBytes;
    int pos = 4; // 跳过 "fLaC" 魔数

    while (pos + 4 <= data.length) {
      final header = data[pos];
      final isLast = (header & 0x80) != 0;
      final blockType = header & 0x7F;
      final blockLen = (data[pos + 1] << 16) | (data[pos + 2] << 8) | data[pos + 3];
      pos += 4;

      if (pos + blockLen > data.length) {
        // 数据被截断(通常是 PICTURE 块太大、超出了我们读取的 256KB 范围)。
        // 已解析到的字段仍然有效，直接结束扫描，不当成解析失败。
        break;
      }

      final block = data.sublist(pos, pos + blockLen);

      if (blockType == 4) {
        tags = _parseVorbisComment(block, offset: 0);
      } else if (blockType == 6) {
        coverBytes = _parseFlacPicture(block);
      }

      pos += blockLen;
      if (isLast) break;
    }

    if (tags == null && coverBytes == null) return const AudioMetadata();
    return AudioMetadata(
      title:  tags?['TITLE'],
      artist: tags?['ARTIST'],
      album:  tags?['ALBUM'],
      coverBytes: coverBytes,
    );
  }

  /// 解析 FLAC PICTURE 元数据块，返回内嵌图片的原始字节。
  ///
  /// 结构(全部大端，固定顺序): picture type(4B) → MIME 长度(4B) + MIME →
  /// 描述长度(4B) + 描述 → 宽(4B) → 高(4B) → 色深(4B) → 索引色数(4B) →
  /// 图片数据长度(4B) → 图片数据。
  static Uint8List? _parseFlacPicture(Uint8List block) {
    int pos = 0;
    if (pos + 4 > block.length) return null;
    pos += 4; // picture type，不关心具体类型(封面/艺术家照片等)，一律当封面用

    if (pos + 4 > block.length) return null;
    final mimeLen = _readInt(block, pos);
    pos += 4 + mimeLen;

    if (pos + 4 > block.length) return null;
    final descLen = _readInt(block, pos);
    pos += 4 + descLen;

    // 宽、高、色深、索引色数：各 4 字节，共 16 字节，这里不需要具体数值
    pos += 16;

    if (pos + 4 > block.length) return null;
    final picLen = _readInt(block, pos);
    pos += 4;

    if (pos + picLen > block.length || picLen <= 0) return null;
    return block.sublist(pos, pos + picLen);
  }

  // ── OGG (Vorbis) 解析 ──────────────────────────────────────────────────
  //
  // Ogg 是分页(page)容器格式，每页以 "OggS" 开头。Vorbis 音频流的第 2 个
  // 逻辑包固定是 Comment Header，其内容格式跟 FLAC 的 VORBIS_COMMENT 完全
  // 一致(两者共用同一套标签规范)，只是外面多包了一层 Ogg 分页结构需要先
  // 拆出来。
  //
  // 简化处理：只扫描文件开头的头几个 page(标签通常在最前面几页内)，
  // 拼出每页的 segment 数据，定位到 Comment Header 包("\x03vorbis" 开头)
  // 后解析，不追求完整重建整个 Ogg 逻辑流（对元数据读取来说没有必要）。

  static AudioMetadata _parseOgg(Uint8List data) {
    int pos = 0;
    int pagesScanned = 0;
    const maxPagesToScan = 8; // 标签通常在前几页，扫描过多页没有意义

    while (pos + 27 <= data.length && pagesScanned < maxPagesToScan) {
      // Ogg page header 至少 27 字节，含 "OggS" 魔数
      if (!(data[pos] == 0x4F && data[pos + 1] == 0x67 &&
            data[pos + 2] == 0x67 && data[pos + 3] == 0x53)) {
        break; // 不是合法的 page 起始，停止扫描
      }
      pagesScanned++;

      final segCount = data[pos + 26];
      final segTableStart = pos + 27;
      if (segTableStart + segCount > data.length) break;

      // 累加所有 segment 长度，得出这一页的 payload 总长度
      int payloadLen = 0;
      for (int i = 0; i < segCount; i++) {
        payloadLen += data[segTableStart + i];
      }
      final payloadStart = segTableStart + segCount;
      if (payloadStart + payloadLen > data.length) break;

      final payload = data.sublist(payloadStart, payloadStart + payloadLen);

      // Comment Header packet type = 3，紧跟 6 字节 "vorbis" 标识
      if (payload.length > 7 &&
          payload[0] == 0x03 &&
          payload[1] == 0x76 && payload[2] == 0x6F && payload[3] == 0x72 &&
          payload[4] == 0x62 && payload[5] == 0x69 && payload[6] == 0x73) {
        final tags = _parseVorbisComment(payload, offset: 7);
        if (tags != null) {
          return AudioMetadata(
            title:  tags['TITLE'],
            artist: tags['ARTIST'],
            album:  tags['ALBUM'],
          );
          // 注: Ogg/Vorbis 的内嵌封面(METADATA_BLOCK_PICTURE，用 base64 存在
          // 一条 Vorbis Comment 里)属于少数场景，这里暂不处理，只覆盖最常见
          // 的文本标签；封面缺失时列表 UI 会展示占位图标，不影响其他信息。
        }
      }

      pos = payloadStart + payloadLen;
    }

    return const AudioMetadata();
  }

  // ── Vorbis Comment 解析(FLAC 与 OGG 共用) ───────────────────────────────
  //
  // 格式: vendor 字符串长度(4B 小端) + vendor 字符串
  //       + comment 数量(4B 小端)
  //       + 每条 comment: 长度(4B 小端) + "KEY=VALUE" 格式的 UTF-8 文本
  // key 大小写不敏感，这里统一转大写存进返回的 Map，方便调用方按
  // 'TITLE'/'ARTIST'/'ALBUM' 这样固定的大写 key 取值。

  static Map<String, String>? _parseVorbisComment(Uint8List block, {required int offset}) {
    int pos = offset;
    if (pos + 4 > block.length) return null;

    final vendorLen = _readIntLe(block, pos);
    pos += 4 + vendorLen;
    if (pos + 4 > block.length) return null;

    final commentCount = _readIntLe(block, pos);
    pos += 4;

    final tags = <String, String>{};
    for (int i = 0; i < commentCount; i++) {
      if (pos + 4 > block.length) break;
      final len = _readIntLe(block, pos);
      pos += 4;
      if (len < 0 || pos + len > block.length) break;

      final raw = block.sublist(pos, pos + len);
      pos += len;

      String text;
      try {
        text = utf8.decode(raw, allowMalformed: true);
      } catch (_) {
        continue;
      }

      final eqIdx = text.indexOf('=');
      if (eqIdx <= 0) continue; // 没有 '=' 或 key 为空，跳过这条非法 comment

      final key = text.substring(0, eqIdx).toUpperCase();
      final value = text.substring(eqIdx + 1);
      if (value.isEmpty) continue;
      // 同名 key 出现多次(比如多个 ARTIST)时保留第一条即可，够用即可，
      // 不需要为一个封面/标题场景实现完整的多值列表支持。
      tags.putIfAbsent(key, () => value);
    }
    return tags;
  }

  // ── 外部 .lrc 文件 ─────────────────────────────────────────────────────

  static Future<String?> _readSidecarLrc(String audioPath) async {
    final base = audioPath.substring(0, audioPath.lastIndexOf('.'));
    for (final ext in ['.lrc', '.LRC']) {
      final f = File('$base$ext');
      if (await f.exists()) {
        // 先尝试 UTF-8，再尝试 GBK（通过 latin1 兼容）
        try {
          return await f.readAsString(encoding: utf8);
        } catch (_) {
          try {
            // latin1 可无损读取任何单字节编码
            return await f.readAsString(encoding: latin1);
          } catch (_) {}
        }
      }
    }
    return null;
  }

  // ── 工具函数 ───────────────────────────────────────────────────────────

  static int _syncsafeInt(Uint8List d, int off) =>
      ((d[off] & 0x7f) << 21) |
      ((d[off + 1] & 0x7f) << 14) |
      ((d[off + 2] & 0x7f) << 7) |
      (d[off + 3] & 0x7f);

  static int _readInt(Uint8List d, int off) =>
      ((d[off] & 0xff) << 24) |
      ((d[off + 1] & 0xff) << 16) |
      ((d[off + 2] & 0xff) << 8) |
      (d[off + 3] & 0xff);

  /// 小端序 4 字节整数，Vorbis Comment(FLAC/OGG)的长度字段用的是小端，
  /// 跟 ID3 的大端字段不同，故单独提供。
  static int _readIntLe(Uint8List d, int off) =>
      (d[off] & 0xff) |
      ((d[off + 1] & 0xff) << 8) |
      ((d[off + 2] & 0xff) << 16) |
      ((d[off + 3] & 0xff) << 24);

  /// UTF-16 with auto-detect BOM
  static String _decodeUtf16(Uint8List raw) {
    if (raw.length >= 2) {
      if (raw[0] == 0xFF && raw[1] == 0xFE) {
        // Little-endian BOM
        return _utf16LeToString(raw.sublist(2));
      } else if (raw[0] == 0xFE && raw[1] == 0xFF) {
        // Big-endian BOM
        return _utf16BeToString(raw.sublist(2));
      }
    }
    return _utf16LeToString(raw); // default LE
  }

  static String _decodeUtf16Be(Uint8List raw) => _utf16BeToString(raw);

  static String _utf16LeToString(Uint8List raw) {
    final codeUnits = <int>[];
    for (int i = 0; i + 1 < raw.length; i += 2) {
      codeUnits.add(raw[i] | (raw[i + 1] << 8));
    }
    return String.fromCharCodes(codeUnits);
  }

  static String _utf16BeToString(Uint8List raw) {
    final codeUnits = <int>[];
    for (int i = 0; i + 1 < raw.length; i += 2) {
      codeUnits.add((raw[i] << 8) | raw[i + 1]);
    }
    return String.fromCharCodes(codeUnits);
  }
}

// ── LRC 解析 ────────────────────────────────────────────────────────────────

/// 一行 LRC 歌词
class LrcLine {
  final Duration time;
  final String text;
  const LrcLine({required this.time, required this.text});
}

/// 将 LRC 文本解析为时间轴列表（按时间升序排列）
List<LrcLine> parseLrc(String lrcText) {
  final lines  = <LrcLine>[];
  final regex  = RegExp(r'\[(\d{2}):(\d{2})\.(\d{2,3})\](.*)');

  for (final rawLine in lrcText.split('\n')) {
    final line = rawLine.trim();
    for (final match in regex.allMatches(line)) {
      final min  = int.parse(match.group(1)!);
      final sec  = int.parse(match.group(2)!);
      final msRaw = match.group(3)!;
      final ms   = msRaw.length == 2
          ? int.parse(msRaw) * 10
          : int.parse(msRaw);
      final text = match.group(4)?.trim() ?? '';
      lines.add(LrcLine(
        time: Duration(minutes: min, seconds: sec, milliseconds: ms),
        text: text,
      ));
    }
  }

  lines.sort((a, b) => a.time.compareTo(b.time));
  return lines;
}
