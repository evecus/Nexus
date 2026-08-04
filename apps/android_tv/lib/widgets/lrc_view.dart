import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// 歌词行。
class _LrcLine {
  final int timeMs; // <0 表示纯文本(无时间戳)
  final String text;
  const _LrcLine(this.timeMs, this.text);
}

/// 歌词视图,照抄 NovaBox 的 `LrcView.java`,适配 TV 端大字号。
///
/// - 普通行半透明,当前行加粗高亮
/// - 当前行垂直居中,平滑滚动(每帧逼近目标偏移)
/// - 支持多时间戳行(`[00:01.00][00:30.00]lyric`)
/// - 跳过 ID3 metadata 标签行(`[ar:...]`、`[ti:...]` 等)
/// - 过滤制作信息行(词曲编混、OP/SP 等)
/// - 无时间戳时作为纯文本展示
class LrcView extends StatefulWidget {
  final String? lrcText;
  final String emptyText;
  final Color? highlightColor;
  final Color? normalColor;
  final double lineSpacing;
  final double normalFontSize;
  final double currentFontSize;

  const LrcView({
    super.key,
    this.lrcText,
    this.emptyText = '暂无歌词',
    this.highlightColor = const Color(0xFF000000),
    this.normalColor = const Color(0xAA000000),
    this.lineSpacing = 68,
    this.normalFontSize = 20,
    this.currentFontSize = 26,
  });

  @override
  State<LrcView> createState() => LrcViewState();
}

class LrcViewState extends State<LrcView> {
  final List<_LrcLine> _lines = [];
  bool _hasLrc = false;
  int _currentIndex = -1;
  double _offset = 0;
  double _targetOffset = 0;
  Timer? _scrollTimer;
  static const double _scrollFraction = 0.14;
  static const int _scrollDurationMs = 16;
  static final RegExp _tagLine = RegExp(
      r'^\[(ar|ti|al|by|offset|total|hash|sign|qq)[^\]]*\].*',
      caseSensitive: false);
  static final RegExp _timeTag = RegExp(r'\[(\d{2}):(\d{2})(?:\.(\d+))?\]');
  static final RegExp _creditLine = RegExp(
      r'.*[词曲编混录制监制作].*[：:].+|(OP|SP|Arranger|Composer|Lyricist|Producer|Vocal|Guitar|Bass|Drum|Keyboard|Strings|Mix|Mastering)[：:].+',
      caseSensitive: false);

  @override
  void initState() {
    super.initState();
    _parse(widget.lrcText);
  }

  @override
  void didUpdateWidget(covariant LrcView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.lrcText != widget.lrcText) {
      _parse(widget.lrcText);
      _offset = 0;
      _targetOffset = 0;
      _currentIndex = -1;
    }
  }

  void _parse(String? text) {
    _lines.clear();
    _hasLrc = false;
    if (text == null || text.isEmpty) {
      _hasLrc = false;
      return;
    }
    final lines = text.split(RegExp(r'\r?\n'));
    bool foundAnyTimed = false;
    for (final raw in lines) {
      if (raw.isEmpty) continue;
      if (_tagLine.hasMatch(raw)) continue;
      // 提取所有时间戳
      final matches = _timeTag.allMatches(raw).toList();
      if (matches.isEmpty) {
        if (_creditLine.hasMatch(raw)) continue;
        if (raw.trim().isEmpty) continue;
        _lines.add(_LrcLine(-1, raw.trim()));
        continue;
      }
      // 行尾剩余文本
      final lastEnd = matches.last.end;
      final lyricText = raw.substring(lastEnd).trim();
      if (lyricText.isEmpty) continue;
      if (_creditLine.hasMatch(lyricText)) continue;
      for (final m in matches) {
        final min = int.parse(m.group(1)!);
        final sec = int.parse(m.group(2)!);
        final msStr = m.group(3) ?? '';
        int ms = 0;
        if (msStr.isNotEmpty) {
          if (msStr.length == 1) {
            ms = int.parse(msStr) * 100;
          } else if (msStr.length == 2) {
            ms = int.parse(msStr) * 10;
          } else {
            ms = int.parse(msStr.substring(0, 3));
          }
        }
        final total = min * 60 * 1000 + sec * 1000 + ms;
        _lines.add(_LrcLine(total, lyricText));
        foundAnyTimed = true;
      }
    }
    if (foundAnyTimed) {
      _lines.sort((a, b) => a.timeMs.compareTo(b.timeMs));
      _hasLrc = true;
    } else {
      // 全部为纯文本
      _hasLrc = _lines.isNotEmpty;
    }
  }

  /// 根据当前播放进度(ms)更新高亮行与滚动偏移。
  void updateProgress(int positionMs) {
    if (!_hasLrc) return;
    if (_lines.isEmpty) return;
    if (_lines.first.timeMs < 0) return; // 纯文本模式不滚动
    int idx = -1;
    for (int i = _lines.length - 1; i >= 0; i--) {
      if (_lines[i].timeMs <= positionMs) {
        idx = i;
        break;
      }
    }
    if (idx == _currentIndex) return;
    _currentIndex = idx;
    if (idx < 0) return;
    _targetOffset = idx * widget.lineSpacing + widget.lineSpacing / 2;
    _startScroll();
  }

  void _startScroll() {
    _scrollTimer?.cancel();
    _scrollTimer =
        Timer.periodic(const Duration(milliseconds: _scrollDurationMs), (_) {
      final diff = _targetOffset - _offset;
      if (diff.abs() <= 0.5) {
        _offset = _targetOffset;
        _scrollTimer?.cancel();
        _scrollTimer = null;
      } else {
        _offset += diff * _scrollFraction;
      }
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _scrollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _LrcPainter(
        lines: _lines,
        hasLrc: _hasLrc,
        currentIndex: _currentIndex,
        offset: _offset,
        emptyText: widget.emptyText,
        highlightColor: widget.highlightColor ??
            Theme.of(context).colorScheme.onSurface,
        normalColor: widget.normalColor ??
            Theme.of(context).colorScheme.onSurface.withAlpha(170),
        lineSpacing: widget.lineSpacing,
        normalFontSize: widget.normalFontSize,
        currentFontSize: widget.currentFontSize,
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _LrcPainter extends CustomPainter {
  final List<_LrcLine> lines;
  final bool hasLrc;
  final int currentIndex;
  final double offset;
  final String emptyText;
  final Color highlightColor;
  final Color normalColor;
  final double lineSpacing;
  final double normalFontSize;
  final double currentFontSize;

  _LrcPainter({
    required this.lines,
    required this.hasLrc,
    required this.currentIndex,
    required this.offset,
    required this.emptyText,
    required this.highlightColor,
    required this.normalColor,
    required this.lineSpacing,
    required this.normalFontSize,
    required this.currentFontSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 裁剪到自身区域，避免歌词滚动时绘制内容超出边界，
    // 与顶部/底部的按钮、进度条等控件重叠。
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width, size.height));

    if (!hasLrc || lines.isEmpty) {
      final tp = TextPainter(
        text: TextSpan(
          text: emptyText,
          style: TextStyle(
            color: normalColor,
            fontSize: 20.sp,
          ),
        ),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      );
      tp.layout(maxWidth: size.width);
      tp.paint(
          canvas,
          Offset((size.width - tp.width) / 2,
              (size.height - tp.height) / 2));
      canvas.restore();
      return;
    }

    final slWidth = size.width * 0.92;
    final left = (size.width - slWidth) / 2;
    final h = size.height;

    for (int i = 0; i < lines.length; i++) {
      final top = h / 2 + i * lineSpacing - offset;
      if (top < -lineSpacing || top > h + lineSpacing) continue;
      final isCurrent = i == currentIndex;
      final tp = TextPainter(
        text: TextSpan(
          text: lines[i].text,
          style: TextStyle(
            color: isCurrent ? highlightColor : normalColor,
            fontSize: isCurrent ? currentFontSize : normalFontSize,
            fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
            height: 1.3,
          ),
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      );
      tp.layout(maxWidth: slWidth);
      final dy = top - tp.height / 2;
      final dx = left + (slWidth - tp.width) / 2;
      tp.paint(canvas, Offset(dx, dy));
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _LrcPainter old) {
    return old.offset != offset ||
        old.currentIndex != currentIndex ||
        old.hasLrc != hasLrc ||
        old.lines.length != lines.length;
  }
}
