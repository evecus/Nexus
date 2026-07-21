import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as p;
import 'package:player_shared/player_shared.dart';

import 'tv_video_player_controller.dart';
import 'package:nexus_tv/app/theme/tv_theme.dart';
import 'package:nexus_tv/app/tv_focus_node.dart';
import 'package:nexus_tv/app/tv_style.dart';
import 'package:nexus_tv/widgets/tv_highlight.dart';

/// TV 视频全屏播放页。
///
/// 按键交互:
/// - **方向下键**: 显示底部控制条,焦点落到播放按钮
/// - **确认键**: 控制条隐藏时显示控制条;控制条显示时触发当前焦点按钮(播放按钮=播放/暂停)
/// - **菜单键**: 唤出左侧播放列表弹窗,焦点落到弹窗内
/// - **方向左右键**: 控制条隐藏时 seek ±10s;控制条显示时在按钮间移动焦点
/// - **返回键**: 弹窗显示时关闭弹窗;控制条显示时隐藏控制条;都隐藏时退出页面
class TvVideoPlayerPage extends StatefulWidget {
  const TvVideoPlayerPage({super.key});
  @override
  State<TvVideoPlayerPage> createState() => _TvVideoPlayerPageState();
}

class _TvVideoPlayerPageState extends State<TvVideoPlayerPage> {
  late final TvVideoPlayerController ctrl;

  // 根级焦点(全局按键拦截)
  late final FocusNode _rootFocus;

  // 控制按钮焦点节点(有序遍历)
  final _backFocus    = TvFocusNode();
  final _prevFocus    = TvFocusNode();
  final _seekBackFocus = TvFocusNode();
  final _playFocus    = TvFocusNode(autofocus: true);
  final _seekFwdFocus = TvFocusNode();
  final _nextFocus    = TvFocusNode();
  final _listFocus    = TvFocusNode();

  @override
  void initState() {
    super.initState();
    ctrl = Get.put(TvVideoPlayerController());
    _rootFocus = FocusNode();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    _rootFocus.dispose();
    _backFocus.dispose();
    _prevFocus.dispose();
    _seekBackFocus.dispose();
    _playFocus.dispose();
    _seekFwdFocus.dispose();
    _nextFocus.dispose();
    _listFocus.dispose();
    Get.delete<TvVideoPlayerController>();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  /// 全局按键处理(根 Focus)。
  /// 优先级:弹窗 > 控制条 > 基础操作。
  KeyEventResult _onRootKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final isBack = key == LogicalKeyboardKey.goBack ||
        key == LogicalKeyboardKey.escape;
    final isOk = key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.space;
    final isMenu = key == LogicalKeyboardKey.contextMenu;
    final isDown = key == LogicalKeyboardKey.arrowDown;
    final isUp = key == LogicalKeyboardKey.arrowUp;
    final isLeft = key == LogicalKeyboardKey.arrowLeft;
    final isRight = key == LogicalKeyboardKey.arrowRight;

    // 1. 播放列表弹窗显示中
    if (ctrl.showPlaylist.value) {
      if (isBack) {
        ctrl.showPlaylist.value = false;
        return KeyEventResult.handled;
      }
      // 其它键交给弹窗内 TvHighlight 处理
      return KeyEventResult.ignored;
    }

    // 2. 控制条显示中
    if (ctrl.showControls.value) {
      if (isBack) {
        ctrl.showControls.value = false;
        _rootFocus.requestFocus();
        return KeyEventResult.handled;
      }
      if (isMenu) {
        ctrl.showPlaylist.value = true;
        return KeyEventResult.handled;
      }
      // 上下/左右/确认键交给控制按钮的 TvHighlight 处理(默认遍历 / onTap)
      return KeyEventResult.ignored;
    }

    // 3. 控制条隐藏时
    if (isBack) {
      Get.back();
      return KeyEventResult.handled;
    }
    if (isMenu) {
      ctrl.showPlaylist.value = true;
      return KeyEventResult.handled;
    }
    if (isOk || isDown) {
      // 显示控制条 + 焦点到播放按钮
      ctrl.showControls.value = true;
      ctrl.autoHideControls();
      _playFocus.requestFocus();
      return KeyEventResult.handled;
    }
    if (isLeft) {
      ctrl.seekRelative(-10);
      return KeyEventResult.handled;
    }
    if (isRight) {
      ctrl.seekRelative(10);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        focusNode: _rootFocus,
        autofocus: true,
        onKeyEvent: _onRootKey,
        child: Stack(
          children: [
            // 视频画面 — 通过 backend 统一构建（MPV/ExoPlayer 均适用）
            ctrl.backend.buildView(
              key: ctrl.playerKey,
              fill: Colors.black,
            ),
            // 缓冲中
            Obx(() => ctrl.isBuffering.value
                ? const Center(
                    child: CircularProgressIndicator(color: Colors.white))
                : const SizedBox()),
            // 控制层
            Obx(() => ctrl.showControls.value
                ? _buildControls(context)
                : const SizedBox()),
            // 播放列表弹窗(菜单键唤出)
            Obx(() => ctrl.showPlaylist.value
                ? _buildPlaylistPanel(context)
                : const SizedBox()),
          ],
        ),
      ),
    );
  }

  // ── 控制层 ──────────────────────────────────────────────

  Widget _buildControls(BuildContext context) {
    return Stack(
      children: [
        // 顶部栏
        _buildTopBar(context),
        // 底部控制按钮
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
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
                _buildProgressBar(context),
                SizedBox(height: 16.w),
                _buildButtons(context),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
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
            _CtrlButton(
              focusNode: _backFocus,
              onTap: () => Get.back(),
              icon: Icons.arrow_back,
              size: 40.w,
            ),
            SizedBox(width: 16.w),
            Expanded(
              child: Obx(() => Text(
                    ctrl.title,
                    style: TvStyle.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  )),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressBar(BuildContext context) {
    return Obx(() {
      final pos = ctrl.position.value;
      final dur = ctrl.duration.value;
      final pct = dur.inMilliseconds > 0
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
    });
  }

  /// 底部控制按钮组(有序焦点遍历: 上一首/后退10s/播放暂停/前进10s/下一首/播放列表)。
  Widget _buildButtons(BuildContext context) {
    return FocusTraversalGroup(
      policy: OrderedTraversalPolicy(),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _CtrlButton(
            focusNode: _prevFocus,
            onTap: ctrl.prev,
            icon: Icons.skip_previous_rounded,
            size: 48.w,
            order: 1,
          ),
          SizedBox(width: 32.w),
          _CtrlButton(
            focusNode: _seekBackFocus,
            onTap: () => ctrl.seekRelative(-10),
            icon: Icons.fast_rewind_rounded,
            size: 48.w,
            order: 2,
          ),
          SizedBox(width: 32.w),
          _CtrlButton(
            focusNode: _playFocus,
            onTap: ctrl.togglePlay,
            icon: null,
            order: 3,
            size: 72.w,
            child: Obx(() => Icon(
                  ctrl.isPlaying.value
                      ? Icons.pause_circle_filled
                      : Icons.play_circle_filled,
                  color: TvColors.primary,
                  size: 72.w,
                )),
          ),
          SizedBox(width: 32.w),
          _CtrlButton(
            focusNode: _seekFwdFocus,
            onTap: () => ctrl.seekRelative(10),
            icon: Icons.fast_forward_rounded,
            size: 48.w,
            order: 4,
          ),
          SizedBox(width: 32.w),
          _CtrlButton(
            focusNode: _nextFocus,
            onTap: ctrl.next,
            icon: Icons.skip_next_rounded,
            size: 48.w,
            order: 5,
          ),
          SizedBox(width: 32.w),
          _CtrlButton(
            focusNode: _listFocus,
            onTap: () => ctrl.showPlaylist.value = true,
            icon: Icons.video_library,
            size: 48.w,
            order: 6,
          ),
        ],
      ),
    );
  }

  // ── 播放列表弹窗(菜单键唤出,屏幕左侧) ─────────────────

  Widget _buildPlaylistPanel(BuildContext context) {
    return Positioned.fill(
      child: Container(
        color: Colors.black54,
        alignment: Alignment.centerLeft,
        child: Container(
          margin: EdgeInsets.only(left: 48.w),
          width: 560.w,
          height: 800.w,
          decoration: BoxDecoration(
            color: TvColors.surface,
            borderRadius: TvStyle.radius12,
            border: Border.all(color: TvColors.primary, width: 2.w),
          ),
          child: Column(
            children: [
              // 头部
              Container(
                height: 80.w,
                padding: EdgeInsets.symmetric(horizontal: 32.w),
                alignment: Alignment.centerLeft,
                decoration: BoxDecoration(
                  border: Border(
                      bottom: BorderSide(
                          color: TvColors.divider, width: 1)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.video_library,
                        color: TvColors.primary, size: 36.w),
                    SizedBox(width: 12.w),
                    Text('播放列表', style: TvStyle.titleMedium),
                    const Spacer(),
                    Obx(() => Text('${ctrl.playlist.length} 个',
                        style: TvStyle.labelSmall)),
                  ],
                ),
              ),
              // 列表
              Expanded(
                child: Obx(() => ListView.builder(
                      padding: EdgeInsets.symmetric(vertical: 8.w),
                      itemCount: ctrl.playlist.length,
                      itemBuilder: (_, i) {
                        final name = p.withoutExtension(
                            ctrl.playlist[i]['name'] ?? '');
                        final isActive = ctrl.currentIdx.value == i;
                        return _PlaylistItem(
                          text: name,
                          highlighted: isActive,
                          autofocus: i == ctrl.currentIdx.value ||
                              (ctrl.currentIdx.value < 0 && i == 0),
                          onTap: () {
                            ctrl.playAt(i);
                            ctrl.showPlaylist.value = false;
                          },
                        );
                      },
                    )),
              ),
              // 底部提示
              Container(
                height: 64.w,
                padding: EdgeInsets.symmetric(horizontal: 32.w),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  border: Border(
                      top: BorderSide(
                          color: TvColors.divider, width: 1)),
                ),
                child: Text('↑↓ 切换  OK 播放  返回键关闭',
                    style: TvStyle.labelSmall),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }
}

/// 控制按钮(TvHighlight + 有序焦点遍历)。
class _CtrlButton extends StatelessWidget {
  final TvFocusNode focusNode;
  final VoidCallback? onTap;
  final IconData? icon;
  final Widget? child;
  final double size;
  final int? order;

  const _CtrlButton({
    required this.focusNode,
    this.onTap,
    this.icon,
    this.child,
    required this.size,
    this.order,
  });

  @override
  Widget build(BuildContext context) {
    final w = TvHighlight(
      focusNode: focusNode,
      onTap: onTap,
      borderRadius: BorderRadius.circular(50),
      child: SizedBox(
        width: size,
        height: size,
        child: Center(
          child: child ??
              Icon(icon, color: Colors.white, size: size),
        ),
      ),
    );
    if (order == null) return w;
    return FocusTraversalOrder(
      order: NumericFocusOrder(order!.toDouble()),
      child: w,
    );
  }
}

/// 播放列表项(TvHighlight 包裹,遥控器可聚焦)。
class _PlaylistItem extends StatefulWidget {
  final String text;
  final bool highlighted;
  final bool autofocus;
  final VoidCallback onTap;

  const _PlaylistItem({
    required this.text,
    required this.onTap,
    this.highlighted = false,
    this.autofocus = false,
  });

  @override
  State<_PlaylistItem> createState() => _PlaylistItemState();
}

class _PlaylistItemState extends State<_PlaylistItem> {
  late final TvFocusNode _focus;

  @override
  void initState() {
    super.initState();
    _focus = TvFocusNode();
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TvHighlight(
      focusNode: _focus,
      autofocus: widget.autofocus,
      onTap: widget.onTap,
      borderRadius: TvStyle.radius8,
      color: widget.highlighted
          ? TvColors.primary.withAlpha(40)
          : Colors.transparent,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 32.w, vertical: 16.w),
        child: Row(
          children: [
            if (widget.highlighted) ...[
              Icon(Icons.play_arrow,
                  color: TvColors.primary, size: 28.w),
              SizedBox(width: 12.w),
            ],
            Expanded(
              child: Text(
                widget.text,
                style: TvStyle.bodyMedium.copyWith(
                  color: widget.highlighted
                      ? TvColors.primary
                      : TvColors.textPrimary,
                  fontWeight: widget.highlighted
                      ? FontWeight.bold
                      : FontWeight.normal,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
