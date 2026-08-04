import 'dart:async';

import '../music/audio_metadata.dart';

/// 音乐封面的"内存态、分批增量加载"策略(手机 / TV / Windows 三端共用)。
///
/// 背景：封面数据本身就直接嵌在音乐文件的 ID3/FLAC/OGG 标签里，读取成本
/// 很低，没有必要落盘缓存占用本地存储空间——三端统一改为只在内存里持有
/// 封面字节，App 重启或列表重建后这份内存数据会丢失，下次展示时按需
/// 重新读取文件即可，代价很小。
///
/// 加载节奏：不是"先读前 200 首、后面全部懒加载"，而是分批读取——
/// 第一批读取当前列表的前 [batchSize](默认 200)首；用户往下滚动，看到了
/// 还没读取封面的位置时，再读取下一批 [batchSize] 首(即 200~400，
/// 400~600……)，每次都是整批增量，不是逐条懒加载。
///
/// 切换分类 / 排序方式后，"前 200"的定义会跟着变化(比如按标题排序的
/// 前 200 首，和按艺术家排序的前 200 首通常是不同的歌)，因此每次分类
/// 或排序变化都需要调用 [reset] 并重新从当前列表顺序的开头开始计算。
class AudioCoverMemoryCache<T> {
  AudioCoverMemoryCache({
    this.batchSize = 200,
    required this.pathOf,
    required this.hasCover,
    required this.applyCover,
  });

  /// 每批增量加载的数量。
  final int batchSize;

  /// 从列表项取出音频文件路径,用于调用 [AudioMetadataReader.readFile]。
  final String Function(T item) pathOf;

  /// 判断该项是否已经有内存态封面(避免重复读取同一首歌)。
  final bool Function(T item) hasCover;

  /// 把读取到的封面字节写回列表项(内存态字段,不落盘)。
  final void Function(T item, AudioMetadata meta) applyCover;

  /// 当前已经"确保加载过"的批次数(已加载到第几个 200)。
  int _loadedBatches = 0;

  bool _loading = false;
  bool _disposed = false;

  void dispose() => _disposed = true;

  /// 切换分类 / 排序方式，或重新扫描后调用：清零批次计数，让"前 200"
  /// 按新的列表顺序重新计算，而不是延续旧顺序下已加载的位置。
  void reset() {
    _loadedBatches = 0;
  }

  /// 确保 [orderedList] 的前 [batchSize] 首封面已加载(或正在加载)。
  /// 用于列表首次展示 / 分类排序切换后的初始加载。
  Future<void> ensureFirstBatch(
    List<T> orderedList, {
    FutureOr<void> Function()? onProgress,
  }) =>
      ensureBatchesUpTo(1, orderedList, onProgress: onProgress);

  /// 根据滚动位置增量加载：当用户看到了索引 [visibleIndex] 但该位置
  /// 还没有封面数据时调用。内部按 [batchSize] 取整,换算出需要覆盖到
  /// 第几批，只在还没加载到那一批时才触发新的加载(200 → 400 → 600…)。
  Future<void> ensureVisible(
    int visibleIndex,
    List<T> orderedList, {
    FutureOr<void> Function()? onProgress,
  }) {
    final neededBatch = (visibleIndex ~/ batchSize) + 1;
    return ensureBatchesUpTo(neededBatch, orderedList, onProgress: onProgress);
  }

  /// 确保已加载到第 [targetBatch] 批(每批 [batchSize] 首)。
  /// 例如 targetBatch=1 → 加载前 200 首；targetBatch=2 → 加载 200~400
  /// 范围内还没加载的部分(累计前 400 首)，以此类推。
  Future<void> ensureBatchesUpTo(
    int targetBatch,
    List<T> orderedList, {
    FutureOr<void> Function()? onProgress,
  }) async {
    if (_disposed || orderedList.isEmpty) return;
    if (targetBatch <= _loadedBatches) return;
    if (_loading) return;
    _loading = true;
    try {
      // 可能有多批排队(比如快速连续滚动),用 while 循环追上目标批次。
      while (!_disposed && _loadedBatches < targetBatch) {
        final start = _loadedBatches * batchSize;
        final end = ((_loadedBatches + 1) * batchSize).clamp(0, orderedList.length);
        if (start >= orderedList.length) {
          // 列表本身比目标批次短,直接视为已加载完。
          _loadedBatches = targetBatch;
          break;
        }
        for (int i = start; i < end; i++) {
          if (_disposed) break;
          final item = orderedList[i];
          if (hasCover(item)) continue;
          try {
            final meta = await AudioMetadataReader.readFile(pathOf(item));
            if (_disposed) break;
            applyCover(item, meta);
            if (onProgress != null) await onProgress();
          } catch (_) {
            // 单首读取失败不影响其余歌曲继续加载。
          }
          // 让出事件循环,避免阻塞 UI。
          await Future.delayed(Duration.zero);
        }
        _loadedBatches++;
      }
    } finally {
      _loading = false;
    }
  }
}
