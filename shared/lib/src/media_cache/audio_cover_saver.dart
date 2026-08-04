import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'app_data_dir.dart';

/// 把从 ID3 APIC 帧解析出来的封面图片字节落盘缓存(手机端与 TV 端共用)。
///
/// 用音频文件自身的绝对路径做稳定 hash 作为文件名,同一首歌重复扫描时
/// 直接覆盖旧封面文件,不会无限堆积。封面数据体积较大,不适合直接存进
/// Hive 缓存,只存这里返回的文件路径字符串。
class AudioCoverSaver {
  AudioCoverSaver._();

  static Future<String> save(String audioPath, Uint8List bytes) async {
    try {
      await AppDataDir.ensureCreated();
      final coversDir = await AppDataDir.coversDir;
      final ext = _sniffImageExt(bytes);
      final hash = _stableHash(audioPath);
      final file = File(p.join(coversDir.path, '$hash$ext'));
      await file.writeAsBytes(bytes, flush: true);
      return file.path;
    } catch (_) {
      return '';
    }
  }

  /// 通过文件头 magic number 判断图片格式,默认按 jpg 处理。
  static String _sniffImageExt(Uint8List bytes) {
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return '.png';
    }
    return '.jpg';
  }

  /// 简单稳定的字符串哈希(FNV-1a),用于生成封面文件名。
  static String _stableHash(String input) {
    const int fnvPrime = 0x01000193;
    int hash = 0x811c9dc5;
    for (final codeUnit in input.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * fnvPrime) & 0xFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }
}
