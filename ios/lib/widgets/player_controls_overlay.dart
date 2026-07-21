import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import 'package:player_shared/player_shared.dart';

class PlayerControlsOverlay extends StatefulWidget {
  final PlayerStateMixin controller;
  final String title;
  final bool isLive;
  final VoidCallback? onTogglePlay;

  const PlayerControlsOverlay({
    super.key,
    required this.controller,
    this.title = '',
    this.isLive = false,
    this.onTogglePlay,
  });

  @override
  State<PlayerControlsOverlay> createState() => _PlayerControlsOverlayState();
}

class _PlayerControlsOverlayState extends State<PlayerControlsOverlay> {
  PlayerStateMixin get ctrl => widget.controller;

  Offset? _gestureStart;
  String _gestureType = '';

  void _onTap() => ctrl.toggleControls();

  void _onPanStart(DragStartDetails d) {
    _gestureStart = d.localPosition;
    _gestureType = '';
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (_gestureStart == null) return;
    final dx = d.localPosition.dx - _gestureStart!.dx;
    final dy = d.localPosition.dy - _gestureStart!.dy;

    if (_gestureType.isEmpty && (dx.abs() + dy.abs()) > 10) {
      final w = context.size?.width ?? 400;
      if (dx.abs() > dy.abs()) {
        _gestureType = 'seek';
        ctrl.onSeekGestureStart();
      } else {
        _gestureType = _gestureStart!.dx < w / 2 ? 'brightness' : 'volume';
        if (_gestureType == 'brightness') {
          ctrl.onBrightnessGestureStart();
        } else {
          ctrl.onVolumeGestureStart();
        }
      }
    }

    final h = context.size?.height ?? 600;
    final w = context.size?.width ?? 400;

    if (_gestureType == 'seek') {
      final delta = dx / w * 120;
      ctrl.onSeekGestureUpdate(delta);
    } else if (_gestureType == 'brightness') {
      ctrl.onBrightnessGestureUpdate(-dy / h);
    } else if (_gestureType == 'volume') {
      ctrl.onVolumeGestureUpdate(-dy / h);
    }
  }

  void _onPanEnd(DragEndDetails d) {
    if (_gestureType == 'seek') {
      // commit the seek based on last known delta
      // already shown tip, just finalize
      ctrl.onSeekGestureEnd(0);
    }
    _gestureType = '';
    _gestureStart = null;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _onTap,
      onPanStart: _onPanStart,
      onPanUpdate: _onPanUpdate,
      onPanEnd: _onPanEnd,
      behavior: HitTestBehavior.translucent,
      child: Obx(() => Stack(
            children: [
              // Gesture tip bubble
              if (ctrl.showGestureTip.value)
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      ctrl.gestureTipText.value,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 16),
                    ),
                  ),
                ),

              if (ctrl.showControls.value) ...[
                _buildTopBar(),
                if (widget.isLive) _buildLiveBottomBar() else _buildVodBottomBar(),
              ],
            ],
          )),
    );
  }

  Widget _buildTopBar() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black54, Colors.transparent],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Get.back(),
              ),
              Expanded(
                child: Text(
                  widget.title,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w500),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (!widget.isLive) _buildSpeedButton(),
              _buildFullScreenButton(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLiveBottomBar() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [Colors.black54, Colors.transparent],
          ),
        ),
        child: SafeArea(
          top: false,
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.play_arrow, color: Colors.white),
                onPressed: widget.onTogglePlay,
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Text('LIVE',
                    style: TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.bold,
                        fontSize: 13)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVodBottomBar() {
    final c = ctrl as dynamic;
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [Color(0xB3000000), Colors.transparent],
          ),
        ),
        child: SafeArea(
          top: false,
          child: Obx(() {
            final pos = c.position.value as Duration;
            final dur = c.duration.value as Duration;
            final totalMs =
                dur.inMilliseconds > 0 ? dur.inMilliseconds.toDouble() : 1.0;
            return Row(
              children: [
                const SizedBox(width: 4),
                IconButton(
                  icon: Icon(
                    (c.isPlaying.value as bool)
                        ? Icons.pause
                        : Icons.play_arrow,
                    color: Colors.white,
                  ),
                  onPressed: () => c.togglePlay(),
                ),
                Text(_fmt(pos),
                    style: const TextStyle(color: Colors.white, fontSize: 12)),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 2,
                      thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 6),
                      overlayShape:
                          const RoundSliderOverlayShape(overlayRadius: 12),
                      activeTrackColor: Colors.white,
                      inactiveTrackColor: Colors.white30,
                      thumbColor: Colors.white,
                    ),
                    child: Slider(
                      value: pos.inMilliseconds
                          .toDouble()
                          .clamp(0.0, totalMs),
                      max: totalMs,
                      onChanged: (v) =>
                          c.seekTo(Duration(milliseconds: v.round())),
                    ),
                  ),
                ),
                Text(_fmt(dur),
                    style: const TextStyle(color: Colors.white, fontSize: 12)),
                const SizedBox(width: 8),
              ],
            );
          }),
        ),
      ),
    );
  }

  Widget _buildSpeedButton() {
    final c = ctrl as dynamic;
    return PopupMenuButton<double>(
      icon: const Icon(Icons.speed, color: Colors.white),
      tooltip: '播放速度',
      onSelected: (v) => c.setSpeed(v),
      itemBuilder: (_) => [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
          .map((s) => PopupMenuItem(value: s, child: Text('${s}x')))
          .toList(),
    );
  }

  Widget _buildFullScreenButton() {
    return Obx(() => IconButton(
          icon: Icon(
            ctrl.isFullScreen.value
                ? Icons.fullscreen_exit
                : Icons.fullscreen,
            color: Colors.white,
          ),
          onPressed: _toggleFullScreen,
        ));
  }

  void _toggleFullScreen() {
    final isFs = !ctrl.isFullScreen.value;
    ctrl.isFullScreen.value = isFs;
    if (Platform.isAndroid || Platform.isIOS) {
      if (isFs) {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
      } else {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
      }
    }
    ctrl.autoHideControls();
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }
}
