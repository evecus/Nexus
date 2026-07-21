import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';

import 'package:nexus_tv/app/tv_focus_node.dart';
import 'package:nexus_tv/app/theme/tv_theme.dart';
import 'package:nexus_tv/app/tv_style.dart';
import 'package:player_shared/player_shared.dart';

class TvPlayerControls extends StatefulWidget {
  final TvPlayerStateMixin controller;
  final String title;
  final bool isLive;
  final VoidCallback? onTogglePlay;

  const TvPlayerControls({
    super.key,
    required this.controller,
    this.title = '',
    this.isLive = false,
    this.onTogglePlay,
  });

  @override
  State<TvPlayerControls> createState() => _TvPlayerControlsState();
}

class _TvPlayerControlsState extends State<TvPlayerControls> {
  TvPlayerStateMixin get ctrl => widget.controller;

  // D-pad focus nodes for the bottom control bar
  final _playFocus    = TvFocusNode(autofocus: true);
  final _seekBackFocus  = TvFocusNode();
  final _seekFwdFocus   = TvFocusNode();
  final _backFocus    = TvFocusNode();

  @override
  void initState() {
    super.initState();
    ctrl.autoHideControls();
  }

  @override
  void dispose() {
    _playFocus.dispose();
    _seekBackFocus.dispose();
    _seekFwdFocus.dispose();
    _backFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: FocusNode(),
      autofocus: false,
      onKeyEvent: _handleKey,
      child: Obx(() => Stack(
            children: [
              // Tap anywhere to toggle controls
              Positioned.fill(
                child: GestureDetector(
                  onTap: ctrl.toggleControls,
                  behavior: HitTestBehavior.translucent,
                  child: const SizedBox.expand(),
                ),
              ),

              if (ctrl.showControls.value) ...[
                _buildTopBar(),
                if (!widget.isLive) _buildVodBottomBar(),
                if (widget.isLive) _buildLiveBottomBar(),
              ],

              // Buffering spinner
              if (_isBuffering())
                Center(
                  child: SizedBox(
                    width: 64.w,
                    height: 64.w,
                    child: CircularProgressIndicator(
                      strokeWidth: 6.w,
                      color: Colors.white,
                    ),
                  ),
                ),
            ],
          )),
    );
  }

  bool _isBuffering() {
    try {
      return ctrl.player.state.buffering;
    } catch (_) {
      return false;
    }
  }

  void _handleKey(KeyEvent e) {
    if (e is! KeyDownEvent) return;
    final key = e.logicalKey;
    if (!ctrl.showControls.value) {
      ctrl.autoHideControls();
      return;
    }
    // Seek on left/right when controls are visible
    if (key == LogicalKeyboardKey.arrowLeft) {
      _seekRelative(-10);
    } else if (key == LogicalKeyboardKey.arrowRight) {
      _seekRelative(10);
    } else if (key == LogicalKeyboardKey.goBack ||
        key == LogicalKeyboardKey.escape) {
      Get.back();
    }
    ctrl.autoHideControls();
  }

  void _seekRelative(int seconds) {
    final p = ctrl.player;
    final newPos = p.state.position + Duration(seconds: seconds);
    final clamped = newPos.isNegative
        ? Duration.zero
        : (newPos > p.state.duration ? p.state.duration : newPos);
    p.seek(clamped);
  }

  Widget _buildTopBar() {
    return Positioned(
      top: 0, left: 0, right: 0,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black87, Colors.transparent],
          ),
        ),
        padding: EdgeInsets.fromLTRB(48.w, 32.w, 48.w, 32.w),
        child: Row(
          children: [
            IconButton(
              icon: Icon(Icons.arrow_back, color: Colors.white, size: 40.w),
              onPressed: () => Get.back(),
            ),
            SizedBox(width: 16.w),
            Expanded(
              child: Text(
                widget.title,
                style: TvStyle.titleMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (widget.isLive)
              Container(
                padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 6.w),
                decoration: BoxDecoration(
                  color: TvColors.liveRed,
                  borderRadius: TvStyle.radius8,
                ),
                child: Text('LIVE',
                    style: TvStyle.bodyMedium
                        .copyWith(fontWeight: FontWeight.bold)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLiveBottomBar() {
    return Positioned(
      bottom: 0, left: 0, right: 0,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [Colors.black87, Colors.transparent],
          ),
        ),
        padding: EdgeInsets.fromLTRB(48.w, 24.w, 48.w, 32.w),
        child: Row(
          children: [
            Icon(Icons.live_tv, color: TvColors.liveRed, size: 36.w),
            SizedBox(width: 16.w),
            Text('正在直播', style: TvStyle.bodyMedium),
            const Spacer(),
            Text('← → 换台  OK 暂停  返回键 退出',
                style: TvStyle.labelSmall),
          ],
        ),
      ),
    );
  }

  Widget _buildVodBottomBar() {
    final c = ctrl as dynamic;
    return Positioned(
      bottom: 0, left: 0, right: 0,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [Colors.black87, Colors.transparent],
          ),
        ),
        padding: EdgeInsets.fromLTRB(48.w, 16.w, 48.w, 32.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Progress bar (display only on TV — seek via d-pad)
            Obx(() {
              final pos  = (c.position?.value ?? Duration.zero) as Duration;
              final dur  = (c.duration?.value ?? Duration.zero) as Duration;
              final pct  = dur.inMilliseconds > 0
                  ? pos.inMilliseconds / dur.inMilliseconds
                  : 0.0;
              return Column(
                children: [
                  ClipRRect(
                    borderRadius: TvStyle.radius8,
                    child: LinearProgressIndicator(
                      value: pct.clamp(0.0, 1.0),
                      backgroundColor: Colors.white24,
                      valueColor:
                          AlwaysStoppedAnimation(TvColors.primary),
                      minHeight: 6.w,
                    ),
                  ),
                  SizedBox(height: 12.w),
                  Row(
                    children: [
                      Text(_fmt(pos), style: TvStyle.bodyMedium),
                      const Spacer(),
                      Text(_fmt(dur), style: TvStyle.bodyMedium),
                    ],
                  ),
                ],
              );
            }),
            SizedBox(height: 8.w),
            // Control hint
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _hintIcon(Icons.replay_10, '← -10s'),
                SizedBox(width: 32.w),
                Obx(() {
                  final playing = (c.isPlaying?.value ?? false) as bool;
                  return _hintIcon(
                    playing ? Icons.pause : Icons.play_arrow,
                    'OK 播放/暂停',
                  );
                }),
                SizedBox(width: 32.w),
                _hintIcon(Icons.forward_10, '→ +10s'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _hintIcon(IconData icon, String label) {
    return Row(
      children: [
        Icon(icon, color: Colors.white70, size: 28.w),
        SizedBox(width: 8.w),
        Text(label, style: TvStyle.labelSmall),
      ],
    );
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }
}
