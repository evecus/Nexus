import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';

import 'package:nexus_tv/app/controller/tv_settings_controller.dart';
import 'package:nexus_tv/app/routes/tv_routes.dart';
import 'package:nexus_tv/app/theme/tv_theme.dart';
import 'package:nexus_tv/app/tv_focus_node.dart';
import 'package:nexus_tv/app/tv_style.dart';
import 'package:nexus_tv/widgets/tv_highlight.dart';
import 'package:nexus_tv/widgets/tv_playback_entry.dart';

// ── Controller ────────────────────────────────────────────────────────────
class TvIptvController extends GetxController {
  /// 选择本地 m3u 文件并添加为文件源。
  /// 播放页会自行读取文件内容,这里只负责把源添加到 iptvSources。
  /// 返回是否成功添加(用户取消选择时返回 false)。
  Future<bool> loadFile() async {
    final r = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['m3u', 'm3u8', 'txt'],
    );
    if (r == null || r.files.single.path == null) return false;
    final path = r.files.single.path!;
    final name = r.files.single.name;
    TvSettingsController.instance.iptvSources
        .add({'name': name, 'url': '', 'type': 'file', 'filePath': path});
    return true;
  }
}

// ── Page ─────────────────────────────────────────────────────────────────
class TvIptvPlaylistPage extends StatelessWidget {
  const TvIptvPlaylistPage({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = Get.put(TvIptvController());
    final settings = TvSettingsController.instance;
    return Obx(() => Scaffold(
          backgroundColor: TvColors.background,
          body: Column(
            children: [
              _buildTopBar(settings, ctrl),
              Expanded(child: _buildBody(settings)),
            ],
          ),
        ));
  }

  // 顶部顶栏:返回 + 标题 + 导入源
  Widget _buildTopBar(TvSettingsController settings, TvIptvController ctrl) {
    return Container(
      padding: EdgeInsets.fromLTRB(24.w, 24.w, 24.w, 16.w),
      color: TvColors.surface,
      child: Row(
        children: [
          Text('IPTV', style: TvStyle.titleLarge),
          const Spacer(),
          const TvPlaybackEntry(),
          SizedBox(width: 16.w),
          _TopBarButton(
            icon: Icons.add,
            label: '导入源',
            autofocus: settings.iptvSources.isEmpty,
            onTap: () => _showImportDialog(settings, ctrl),
          ),
        ],
      ),
    );
  }

  // 主体:空状态或源卡片网格
  Widget _buildBody(TvSettingsController settings) {
    return Obx(() {
      final sources = settings.iptvSources;
      if (sources.isEmpty) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.live_tv_outlined,
                  size: 80.w, color: TvColors.textSecondary),
              SizedBox(height: 24.w),
              Text('暂无IPTV源', style: TvStyle.titleMedium),
              SizedBox(height: 8.w),
              Text('请点击导入', style: TvStyle.labelSmall),
            ],
          ),
        );
      }
      return SingleChildScrollView(
        padding: EdgeInsets.all(24.w),
        child: Align(
          alignment: Alignment.topLeft,
          child: Wrap(
            alignment: WrapAlignment.start,
            spacing: 24.w,
            runSpacing: 24.w,
            children: [
              for (final e in sources.asMap().entries)
                SizedBox(
                  width: 420.w,
                  child: _buildCard(settings, e.value, e.key),
                ),
            ],
          ),
        ),
      );
    });
  }

  // 单个源卡片
  Widget _buildCard(
      TvSettingsController settings, Map<String, String> src, int idx) {
    final isFile = src['type'] == 'file';
    final name = src['name'] ?? '';
    final url = isFile ? (src['filePath'] ?? '') : (src['url'] ?? '');
    return Container(
      padding: EdgeInsets.all(24.w),
      decoration: BoxDecoration(
        color: TvColors.card,
        borderRadius: TvStyle.radius12,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(
              isFile ? Icons.folder : Icons.link,
              color: TvColors.liveRed,
              size: 40.w,
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: Text(name,
                  style: TvStyle.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ),
          ]),
          SizedBox(height: 8.w),
          SizedBox(
            height: 48.w,
            child: Text(url,
                style: TvStyle.labelSmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
          ),
          SizedBox(height: 16.w),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _CardIconButton(
                icon: Icons.play_arrow,
                label: '播放',
                color: TvColors.primary,
                autofocus: idx == 0,
                onTap: () => TvNavigator.toIptvPlayer(sourceIndex: idx),
              ),
              _CardIconButton(
                icon: Icons.edit,
                label: '编辑',
                color: TvColors.accent,
                onTap: () => _editSource(settings, idx),
              ),
              _CardIconButton(
                icon: Icons.info,
                label: '信息',
                color: TvColors.textSecondary,
                onTap: () => _showInfo(settings, idx),
              ),
              _CardIconButton(
                icon: Icons.delete,
                label: '删除',
                color: TvColors.liveRed,
                onTap: () => _confirmDelete(settings, idx),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── 对话框 ──────────────────────────────────────────────────────────────

  void _showImportDialog(TvSettingsController settings, TvIptvController ctrl) {
    final nameCtrl = TextEditingController();
    final urlCtrl = TextEditingController();
    showDialog(
      context: Get.context!,
      builder: (_) => AlertDialog(
        backgroundColor: TvColors.surface,
        title: Text('导入 IPTV 源', style: TvStyle.titleMedium),
        content: SizedBox(
          width: 600.w,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: nameCtrl,
              autofocus: true,
              style: TvStyle.bodyLarge,
              decoration: InputDecoration(
                labelText: '名称',
                labelStyle: TvStyle.labelSmall,
                border: OutlineInputBorder(borderRadius: TvStyle.radius8),
              ),
            ),
            SizedBox(height: 16.w),
            TextField(
              controller: urlCtrl,
              style: TvStyle.bodyLarge,
              decoration: InputDecoration(
                labelText: 'M3U 链接',
                labelStyle: TvStyle.labelSmall,
                border: OutlineInputBorder(borderRadius: TvStyle.radius8),
              ),
            ),
            SizedBox(height: 16.w),
            _DialogButton(
              label: '选择本地 m3u 文件',
              onTap: () async {
                final ok = await ctrl.loadFile();
                if (ok) Get.back();
              },
            ),
          ]),
        ),
        actions: [
          _DialogButton(label: '取消', onTap: () => Get.back()),
          _DialogButton(
            label: '确定',
            onTap: () async {
              final n = nameCtrl.text.trim();
              final u = urlCtrl.text.trim();
              if (n.isEmpty || u.isEmpty) return;
              await settings.addIptvSource(name: n, url: u);
              Get.back();
            },
          ),
        ],
      ),
    );
  }

  void _editSource(TvSettingsController settings, int idx) {
    final src = settings.iptvSources[idx];
    final isFile = src['type'] == 'file';
    final nameCtrl = TextEditingController(text: src['name'] ?? '');
    final urlCtrl = TextEditingController(
        text: isFile ? (src['filePath'] ?? '') : (src['url'] ?? ''));
    showDialog(
      context: Get.context!,
      builder: (_) => AlertDialog(
        backgroundColor: TvColors.surface,
        title: Text('编辑源', style: TvStyle.titleMedium),
        content: SizedBox(
          width: 600.w,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: nameCtrl,
              autofocus: true,
              style: TvStyle.bodyLarge,
              decoration: InputDecoration(
                labelText: '名称',
                labelStyle: TvStyle.labelSmall,
                border: OutlineInputBorder(borderRadius: TvStyle.radius8),
              ),
            ),
            SizedBox(height: 16.w),
            TextField(
              controller: urlCtrl,
              style: TvStyle.bodyLarge,
              decoration: InputDecoration(
                labelText: isFile ? '文件路径' : 'M3U 链接',
                labelStyle: TvStyle.labelSmall,
                border: OutlineInputBorder(borderRadius: TvStyle.radius8),
              ),
            ),
          ]),
        ),
        actions: [
          _DialogButton(label: '取消', onTap: () => Get.back()),
          _DialogButton(
            label: '保存',
            onTap: () async {
              final n = nameCtrl.text.trim();
              final u = urlCtrl.text.trim();
              if (n.isEmpty) return;
              await settings.removeIptvSource(idx);
              if (isFile) {
                settings.iptvSources
                    .add({'name': n, 'url': '', 'type': 'file', 'filePath': u});
              } else {
                await settings.addIptvSource(name: n, url: u);
              }
              Get.back();
            },
          ),
        ],
      ),
    );
  }

  void _showInfo(TvSettingsController settings, int idx) {
    final src = settings.iptvSources[idx];
    final isFile = src['type'] == 'file';
    final name = src['name'] ?? '';
    final url = isFile ? (src['filePath'] ?? '') : (src['url'] ?? '');
    showDialog(
      context: Get.context!,
      builder: (_) => AlertDialog(
        backgroundColor: TvColors.surface,
        title: Text('源信息', style: TvStyle.titleMedium),
        content: SizedBox(
          width: 600.w,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('名称: $name', style: TvStyle.bodyLarge),
              SizedBox(height: 12.w),
              Text('类型: ${isFile ? '本地文件' : '网络源'}',
                  style: TvStyle.bodyLarge),
              SizedBox(height: 12.w),
              Text(isFile ? '路径:' : '链接:', style: TvStyle.bodyLarge),
              SizedBox(height: 4.w),
              Text(url,
                  style: TvStyle.labelSmall
                      .copyWith(color: TvColors.textPrimary),
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
        actions: [
          _DialogButton(label: '关闭', onTap: () => Get.back(), autofocus: true),
        ],
      ),
    );
  }

  void _confirmDelete(TvSettingsController settings, int idx) {
    final name = settings.iptvSources[idx]['name'] ?? '';
    showDialog(
      context: Get.context!,
      builder: (_) => AlertDialog(
        backgroundColor: TvColors.surface,
        title: Text('确认删除', style: TvStyle.titleMedium),
        content: Text('确定要删除源 "$name" 吗?', style: TvStyle.bodyLarge),
        actions: [
          _DialogButton(label: '取消', onTap: () => Get.back(), autofocus: true),
          _DialogButton(
            label: '删除',
            color: TvColors.liveRed,
            onTap: () {
              settings.removeIptvSource(idx);
              Get.back();
            },
          ),
        ],
      ),
    );
  }
}

// ── 顶栏按钮(横向 图标+文字) ─────────────────────────────────────────────
class _TopBarButton extends StatefulWidget {
  final IconData icon;
  final String? label;
  final VoidCallback onTap;
  final bool autofocus;
  const _TopBarButton({
    required this.icon,
    required this.onTap,
    this.label,
    this.autofocus = false,
  });
  @override
  State<_TopBarButton> createState() => _TopBarButtonState();
}

class _TopBarButtonState extends State<_TopBarButton> {
  final _focus = TvFocusNode();
  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TvHighlight(
        focusNode: _focus,
        autofocus: widget.autofocus,
        onTap: widget.onTap,
        borderRadius: TvStyle.radius8,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 12.w),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(widget.icon, color: TvColors.primary, size: 32.w),
            if (widget.label != null) ...[
              SizedBox(width: 8.w),
              Text(widget.label!, style: TvStyle.bodyMedium),
            ],
          ]),
        ),
      );
}

// ── 卡片操作按钮(纵向 图标+文字) ─────────────────────────────────────────
class _CardIconButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool autofocus;
  const _CardIconButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.autofocus = false,
  });
  @override
  State<_CardIconButton> createState() => _CardIconButtonState();
}

class _CardIconButtonState extends State<_CardIconButton> {
  final _focus = TvFocusNode();
  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TvHighlight(
        focusNode: _focus,
        autofocus: widget.autofocus,
        onTap: widget.onTap,
        borderRadius: TvStyle.radius8,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.w),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, color: widget.color, size: 36.w),
              SizedBox(height: 4.w),
              Text(widget.label,
                  style: TvStyle.labelSmall.copyWith(color: widget.color)),
            ],
          ),
        ),
      );
}

// ── 对话框按钮(文字) ─────────────────────────────────────────────────────
class _DialogButton extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  final bool autofocus;
  final Color? color;
  const _DialogButton({
    required this.label,
    required this.onTap,
    this.autofocus = false,
    this.color,
  });
  @override
  State<_DialogButton> createState() => _DialogButtonState();
}

class _DialogButtonState extends State<_DialogButton> {
  final _focus = TvFocusNode();
  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TvHighlight(
        focusNode: _focus,
        autofocus: widget.autofocus,
        onTap: widget.onTap,
        borderRadius: TvStyle.radius8,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 12.w),
          child: Text(widget.label,
              style: TvStyle.bodyMedium
                  .copyWith(color: widget.color ?? TvColors.textPrimary)),
        ),
      );
}
