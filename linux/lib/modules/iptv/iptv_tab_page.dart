import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:player_shared/player_shared.dart';

import 'package:nexus_linux/app/controller/app_settings_controller.dart';
import 'package:nexus_linux/app/routes.dart';

// ── Controller ────────────────────────────────────────────────────────────────

class IptvSourcesController extends GetxController {
  final isRefreshing = <int, bool>{}.obs;

  AppSettingsController get settings => AppSettingsController.instance;

  /// Save the list to persistent storage directly.
  Future<void> _persist() => StorageService.setValue(
        StorageService.kIptvSources,
        settings.iptvSources
            .map((e) => Map<String, String>.from(e))
            .toList(),
      );

  Future<void> addSource(Map<String, String> source) async {
    settings.iptvSources.add(source);
    await _persist();
    // Fire-and-forget initial fetch for remote+autoUpdate sources
    if (source['type'] == 'network' &&
        source['autoUpdate'] == 'true' &&
        (source['url'] ?? '').isNotEmpty) {
      _fetchRemote(source['url']!);
    }
  }

  Future<void> updateSource(int index, Map<String, String> source) async {
    settings.iptvSources[index] = source;
    await _persist();
    if (source['type'] == 'network' &&
        (source['url'] ?? '').isNotEmpty) {
      _fetchRemote(source['url']!);
    }
  }

  Future<void> removeSource(int index) async {
    settings.iptvSources.removeAt(index);
    await _persist();
  }

  Future<void> refreshSource(int index) async {
    final src = settings.iptvSources[index];
    if (src['type'] != 'network') return;
    final url = src['url'] ?? '';
    if (url.isEmpty) return;
    isRefreshing[index] = true;
    try {
      await _fetchRemote(url);
      SmartDialog.showToast('已刷新: ${src['name']}');
    } catch (e) {
      SmartDialog.showToast('刷新失败: $e');
    } finally {
      isRefreshing[index] = false;
    }
  }

  Future<void> _fetchRemote(String url) async {
    await Dio().get<String>(url,
        options: Options(responseType: ResponseType.plain));
  }
}

// ── UI ────────────────────────────────────────────────────────────────────────

class IptvTabPage extends StatelessWidget {
  const IptvTabPage({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = Get.put(IptvSourcesController(), tag: 'iptv_sources');
    final settings = AppSettingsController.instance;
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Top bar ──────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
          child: Row(
            children: [
              Text(
                'IPTV 源管理',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              FilledButton.icon(
                icon: const Icon(Icons.add, size: 18),
                label: const Text('导入'),
                onPressed: () => _showEditDialog(
                  context: context,
                  ctrl: ctrl,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 24),
          child: Divider(height: 1),
        ),
        const SizedBox(height: 16),

        // ── Source grid ───────────────────────────────────────────────────
        Expanded(
          child: Obx(() {
            if (settings.iptvSources.isEmpty) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.live_tv_outlined,
                      size: 72,
                      color: scheme.onSurfaceVariant.withAlpha(100),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '暂无 IPTV 源',
                      style: TextStyle(
                        fontSize: 16,
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '点击右上角「导入」按钮添加源',
                      style: TextStyle(
                        fontSize: 13,
                        color: scheme.onSurfaceVariant.withAlpha(160),
                      ),
                    ),
                  ],
                ),
              );
            }

            return Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  const minCardWidth = 280.0;
                  const spacing = 16.0;
                  final cols = ((constraints.maxWidth + spacing) /
                          (minCardWidth + spacing))
                      .floor()
                      .clamp(1, 3);

                  return GridView.builder(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: cols,
                      crossAxisSpacing: spacing,
                      mainAxisSpacing: spacing,
                      childAspectRatio: 3.2,
                    ),
                    itemCount: settings.iptvSources.length,
                    itemBuilder: (_, i) {
                      final src = settings.iptvSources[i];
                      return Obx(() => _SourceCard(
                            source: src,
                            isRefreshing: ctrl.isRefreshing[i] == true,
                            onTap: () => AppNavigator.toIptvPlayer(
                              url: '',
                              channelName: src['name'] ?? 'IPTV',
                              groupName: '',
                              sourceIndex: i,
                            ),
                            onEdit: () => _showEditDialog(
                              context: context,
                              ctrl: ctrl,
                              index: i,
                              existing: src,
                            ),
                            onDelete: () => ctrl.removeSource(i),
                            onRefresh: () => ctrl.refreshSource(i),
                          ));
                    },
                  );
                },
              ),
            );
          }),
        ),
      ],
    );
  }

  Future<void> _showEditDialog({
    required BuildContext context,
    required IptvSourcesController ctrl,
    int? index,
    Map<String, String>? existing,
  }) async {
    await showDialog(
      context: context,
      builder: (_) => _SourceEditDialog(
        existing: existing,
        onSave: (src) async {
          if (index != null) {
            await ctrl.updateSource(index, src);
          } else {
            await ctrl.addSource(src);
          }
        },
      ),
    );
  }
}

// ── Source Card ───────────────────────────────────────────────────────────────

class _SourceCard extends StatefulWidget {
  final Map<String, String> source;
  final bool isRefreshing;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onRefresh;

  const _SourceCard({
    required this.source,
    required this.isRefreshing,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
    required this.onRefresh,
  });

  @override
  State<_SourceCard> createState() => _SourceCardState();
}

class _SourceCardState extends State<_SourceCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isNetwork = widget.source['type'] == 'network';
    final autoUpdate = widget.source['autoUpdate'] == 'true';
    final name = widget.source['name'] ?? '';

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: _hovered
              ? scheme.surfaceContainerHighest
              : scheme.surfaceContainer,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _hovered
                ? scheme.primary.withAlpha(80)
                : scheme.outlineVariant.withAlpha(60),
          ),
          boxShadow: _hovered
              ? [
                  BoxShadow(
                    color: scheme.shadow.withAlpha(20),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  )
                ]
              : null,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // Icon
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isNetwork
                    ? scheme.primaryContainer.withAlpha(120)
                    : scheme.secondaryContainer.withAlpha(120),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                isNetwork ? Icons.wifi_tethering : Icons.folder_open,
                size: 20,
                color: isNetwork ? scheme.primary : scheme.secondary,
              ),
            ),
            const SizedBox(width: 12),

            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      _Badge(
                        label: isNetwork ? '远程' : '文件',
                        color: isNetwork ? scheme.primary : scheme.secondary,
                        bg: isNetwork
                            ? scheme.primaryContainer.withAlpha(80)
                            : scheme.secondaryContainer.withAlpha(80),
                      ),
                      if (autoUpdate && isNetwork) ...[
                        const SizedBox(width: 4),
                        _Badge(
                          label: '自动更新',
                          color: Colors.green,
                          bg: Colors.green.withAlpha(30),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),

            // Action buttons
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isNetwork)
                  _ActionBtn(
                    icon: Icons.refresh,
                    tooltip: '刷新源',
                    color: scheme.primary,
                    loading: widget.isRefreshing,
                    onPressed: widget.onRefresh,
                  ),
                _ActionBtn(
                  icon: Icons.edit_outlined,
                  tooltip: '编辑',
                  color: scheme.onSurfaceVariant,
                  onPressed: widget.onEdit,
                ),
                _ActionBtn(
                  icon: Icons.delete_outline,
                  tooltip: '删除',
                  color: scheme.error.withAlpha(180),
                  onPressed: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: const Text('确认删除'),
                        content: Text('确定要删除「$name」吗？'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('取消'),
                          ),
                          FilledButton(
                            style: FilledButton.styleFrom(
                                backgroundColor: scheme.error),
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('删除'),
                          ),
                        ],
                      ),
                    );
                    if (confirmed == true) widget.onDelete();
                  },
                ),
              ],
            ),
          ],
        ),
      ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  final Color bg;
  const _Badge({required this.label, required this.color, required this.bg});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(label, style: TextStyle(fontSize: 10, color: color)),
      );
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color color;
  final bool loading;
  final VoidCallback onPressed;

  const _ActionBtn({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onPressed,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 32,
        height: 32,
        child: loading
            ? Padding(
                padding: const EdgeInsets.all(6),
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: color),
              )
            : IconButton(
                padding: EdgeInsets.zero,
                icon: Icon(icon, size: 18, color: color),
                tooltip: tooltip,
                onPressed: onPressed,
              ),
      );
}

// ── Edit Dialog ───────────────────────────────────────────────────────────────

class _SourceEditDialog extends StatefulWidget {
  final Map<String, String>? existing;
  final Future<void> Function(Map<String, String>) onSave;

  const _SourceEditDialog({this.existing, required this.onSave});

  @override
  State<_SourceEditDialog> createState() => _SourceEditDialogState();
}

class _SourceEditDialogState extends State<_SourceEditDialog> {
  final _nameCtrl = TextEditingController();
  final _urlCtrl = TextEditingController();
  String _importType = 'network';
  bool _autoUpdate = false;
  String? _filePath;
  String? _fileName;
  bool _saving = false;
  String? _nameError;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _nameCtrl.text = e['name'] ?? '';
      _urlCtrl.text = e['url'] ?? '';
      _importType = e['type'] ?? 'network';
      _autoUpdate = e['autoUpdate'] == 'true';
      _filePath = e['filePath'];
      _fileName = e['fileName'];
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _urlCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['m3u', 'm3u8', 'txt'],
    );
    if (result == null || result.files.single.path == null) return;
    setState(() {
      _filePath = result.files.single.path;
      _fileName = result.files.single.name;
    });
  }

  Future<void> _save() async {
    setState(() => _nameError = null);
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = '名称不能为空');
      return;
    }
    if (_importType == 'network' && _urlCtrl.text.trim().isEmpty) {
      SmartDialog.showToast('请输入 M3U 链接');
      return;
    }
    if (_importType == 'file' && _filePath == null) {
      SmartDialog.showToast('请选择本地文件');
      return;
    }

    setState(() => _saving = true);
    try {
      final src = <String, String>{
        'name': name,
        'type': _importType,
        'autoUpdate': _autoUpdate.toString(),
        if (_importType == 'network') 'url': _urlCtrl.text.trim(),
        if (_importType == 'file' && _filePath != null) 'filePath': _filePath!,
        if (_importType == 'file' && _fileName != null) 'fileName': _fileName!,
      };
      await widget.onSave(src);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      SmartDialog.showToast('保存失败: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isEdit = widget.existing != null;
    final isNetwork = _importType == 'network';

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, minWidth: 380),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Title ──────────────────────────────────────────────────
              Text(
                isEdit ? '编辑 IPTV 源' : '导入 IPTV 源',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 20),

              // ── Name ───────────────────────────────────────────────────
              TextField(
                controller: _nameCtrl,
                decoration: InputDecoration(
                  labelText: '名称 *',
                  hintText: '给这个源起个名字',
                  errorText: _nameError,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 16),

              // ── Import type ────────────────────────────────────────────
              Text(
                '导入方式',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: scheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _TypeToggle(
                      label: '远程导入',
                      icon: Icons.wifi_tethering,
                      selected: isNetwork,
                      onTap: () => setState(() => _importType = 'network'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _TypeToggle(
                      label: '文件导入',
                      icon: Icons.folder_open,
                      selected: !isNetwork,
                      onTap: () => setState(() => _importType = 'file'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // ── URL (network) ──────────────────────────────────────────
              Opacity(
                opacity: isNetwork ? 1.0 : 0.38,
                child: TextField(
                  controller: _urlCtrl,
                  enabled: isNetwork,
                  keyboardType: TextInputType.url,
                  decoration: InputDecoration(
                    labelText: '链接',
                    hintText: 'http://example.com/playlist.m3u',
                    prefixIcon: const Icon(Icons.link, size: 18),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8)),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // ── File picker (file) ─────────────────────────────────────
              Opacity(
                opacity: isNetwork ? 0.38 : 1.0,
                child: Row(
                  children: [
                    OutlinedButton.icon(
                      icon: const Icon(Icons.upload_file, size: 16),
                      label: const Text('选择文件'),
                      onPressed: isNetwork ? null : _pickFile,
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _fileName ?? '未选择文件',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: _fileName != null
                              ? scheme.onSurface
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // ── Auto-update ────────────────────────────────────────────
              Opacity(
                opacity: isNetwork ? 1.0 : 0.38,
                child: Row(
                  children: [
                    Checkbox(
                      value: _autoUpdate,
                      onChanged: isNetwork
                          ? (v) => setState(() => _autoUpdate = v ?? false)
                          : null,
                    ),
                    const SizedBox(width: 4),
                    GestureDetector(
                      onTap: isNetwork
                          ? () => setState(() => _autoUpdate = !_autoUpdate)
                          : null,
                      child: const Text(
                        '启动时自动更新',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),
              const Divider(height: 1),
              const SizedBox(height: 16),

              // ── Actions ────────────────────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed:
                        _saving ? null : () => Navigator.of(context).pop(),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(isEdit ? '保存' : '导入'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TypeToggle extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _TypeToggle({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: selected ? scheme.primaryContainer : scheme.surfaceContainerHighest,
          border: Border.all(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 1.5 : 1,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 16,
              color: selected ? scheme.primary : scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: selected
                    ? scheme.onPrimaryContainer
                    : scheme.onSurfaceVariant,
                fontWeight:
                    selected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
