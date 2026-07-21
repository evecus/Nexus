import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

import 'package:nexus_android/app/controller/app_settings_controller.dart';
import 'package:nexus_android/app/routes.dart';
import 'package:player_shared/player_shared.dart';

/// IPTV 源管理控制器,完全照抄 Windows 端 `IptvSourcesController` 逻辑。
///
/// - 源数据以 `Map<String,String>` 形式持久化到 Hive(key: `kIptvSources`)
/// - 字段: name / type('network'|'file') / autoUpdate / url / filePath / fileName
/// - 添加 / 编辑 / 删除 / 刷新源
class IptvSourcesController extends GetxController {
  static IptvSourcesController get instance =>
      Get.find<IptvSourcesController>(tag: 'iptv_sources');

  final RxMap<int, bool> isRefreshing = <int, bool>{}.obs;

  AppSettingsController get settings => AppSettingsController.instance;

  Future<void> _persist() => StorageService.setValue(
        StorageService.kIptvSources,
        settings.iptvSources.map((e) => Map<String, String>.from(e)).toList(),
      );

  Future<void> addSource(Map<String, String> source) async {
    settings.iptvSources.add(source);
    await _persist();
  }

  Future<void> updateSource(int index, Map<String, String> source) async {
    settings.iptvSources[index] = source;
    await _persist();
  }

  Future<void> removeSource(int index) async {
    settings.iptvSources.removeAt(index);
    await _persist();
  }

  /// 刷新远程源(仅触发一次 GET,实际加载在播放页 `loadSource` 中完成)。
  Future<void> refreshSource(int index) async {
    final src = settings.iptvSources[index];
    final url = src['url'] ?? '';
    if (url.isEmpty) return;
    isRefreshing[index] = true;
    try {
      await Dio().get<String>(url,
          options: Options(responseType: ResponseType.plain));
      SmartDialog.showToast('已刷新:${src['name']}');
    } catch (e) {
      SmartDialog.showToast('刷新失败: $e');
    } finally {
      isRefreshing[index] = false;
    }
  }
}

/// IPTV 源管理页(底部导航第二个 Tab),完全照抄 Windows 端 `IptvTabPage` 逻辑。
///
/// - 顶部右上角"导入"按钮,点击弹出编辑对话框(新建模式)
/// - 已导入源以卡片网格展示(手机 1 列,平板 2~3 列自适应)
/// - 每张卡片显示: 图标 + 名称 + 类型/自动更新徽章 + 刷新/编辑/删除按钮
/// - 点击卡片进入 IPTV 播放页(传 sourceIndex)
class IptvTabPage extends StatelessWidget {
  const IptvTabPage({super.key});

  @override
  Widget build(BuildContext context) {
    // 说明同 VideoLibraryPage：已注册则直接复用，避免祖先 widget 树重建时
    // 反复创建新 controller 实例覆盖旧实例。
    final ctrl = Get.isRegistered<IptvSourcesController>(tag: 'iptv_sources')
        ? Get.find<IptvSourcesController>(tag: 'iptv_sources')
        : Get.put(IptvSourcesController(), tag: 'iptv_sources');
    final settings = AppSettingsController.instance;

    return Scaffold(
      body: SafeArea(
        child: Obx(() {
          if (settings.iptvSources.isEmpty) {
            return _buildEmpty(context, ctrl);
          }
          return _buildGrid(context, ctrl, settings);
        }),
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('导入'),
        onPressed: () => _showEditDialog(context: context, ctrl: ctrl),
      ),
    );
  }

  Widget _buildEmpty(BuildContext context, IptvSourcesController ctrl) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.live_tv_outlined,
              size: 80,
              color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(height: 16),
          Text('暂无 IPTV 源',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text('点击右下角「导入」按钮添加源',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  )),
          const SizedBox(height: 24),
          FilledButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('导入 IPTV 源'),
            onPressed: () => _showEditDialog(context: context, ctrl: ctrl),
          ),
        ],
      ),
    );
  }

  Widget _buildGrid(BuildContext context, IptvSourcesController ctrl,
      AppSettingsController settings) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const minCardWidth = 300.0;
        const spacing = 12.0;
        final cols = ((constraints.maxWidth + spacing) /
                (minCardWidth + spacing))
            .floor()
            .clamp(1, 3);
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            crossAxisSpacing: spacing,
            mainAxisSpacing: spacing,
            childAspectRatio: 3.4,
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
                  onDelete: () => _confirmDelete(context, ctrl, i, src['name'] ?? ''),
                  onRefresh: () => ctrl.refreshSource(i),
                ));
          },
        );
      },
    );
  }

  Future<void> _confirmDelete(BuildContext context, IptvSourcesController ctrl,
      int index, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('删除源'),
        content: Text('确定要删除「$name」吗?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ctrl.removeSource(index);
    }
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

/// 源卡片,照抄 Windows 端 `_SourceCard`。
class _SourceCard extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final isNetwork = source['type'] == 'network';
    final autoUpdate = source['autoUpdate'] == 'true';
    final name = source['name'] ?? '';

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              // 图标
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isNetwork
                      ? Theme.of(context)
                          .colorScheme
                          .primaryContainer
                          .withAlpha(120)
                      : Theme.of(context)
                          .colorScheme
                          .secondaryContainer
                          .withAlpha(120),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  isNetwork ? Icons.wifi_tethering : Icons.folder_open,
                  color: isNetwork
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.secondary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              // 信息列
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        _Badge(
                          label: isNetwork ? '远程' : '文件',
                          color: isNetwork
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.secondary,
                        ),
                        if (autoUpdate && isNetwork)
                          _Badge(
                            label: '自动更新',
                            color: Theme.of(context).colorScheme.tertiary,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // 操作按钮
              if (isNetwork)
                _ActionBtn(
                  icon: Icons.refresh,
                  tooltip: '刷新源',
                  loading: isRefreshing,
                  onPressed: onRefresh,
                ),
              _ActionBtn(
                icon: Icons.edit_outlined,
                tooltip: '编辑',
                onPressed: onEdit,
              ),
              _ActionBtn(
                icon: Icons.delete_outline,
                tooltip: '删除',
                onPressed: onDelete,
                color: Theme.of(context).colorScheme.error,
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
  const _Badge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withAlpha(80), width: 0.8),
      ),
      child: Text(label,
          style: Theme.of(context)
              .textTheme
              .labelSmall
              ?.copyWith(color: color, fontSize: 10)),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool loading;
  final Color? color;

  const _ActionBtn({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.loading = false,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 8),
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    return IconButton(
      icon: Icon(icon, size: 20),
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      padding: EdgeInsets.zero,
      color: color,
      onPressed: onPressed,
    );
  }
}

/// 源编辑/导入对话框,照抄 Windows 端 `_SourceEditDialog`。
class _SourceEditDialog extends StatefulWidget {
  final Map<String, String>? existing;
  final Future<void> Function(Map<String, String> src) onSave;

  const _SourceEditDialog({this.existing, required this.onSave});

  @override
  State<_SourceEditDialog> createState() => _SourceEditDialogState();
}

class _SourceEditDialogState extends State<_SourceEditDialog> {
  final _nameCtrl = TextEditingController();
  final _urlCtrl = TextEditingController();
  String _importType = 'network'; // 'network' | 'file'
  bool _autoUpdate = false;
  String? _filePath;
  String? _fileName;
  bool _saving = false;
  String? _nameError;

  bool get isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      final e = widget.existing!;
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
    return Dialog(
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.9,
          minWidth: 300,
        ),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  isEdit ? '编辑 IPTV 源' : '导入 IPTV 源',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 20),
                // 名称
                TextField(
                  controller: _nameCtrl,
                  decoration: InputDecoration(
                    labelText: '名称',
                    border: const OutlineInputBorder(),
                    errorText: _nameError,
                  ),
                ),
                const SizedBox(height: 16),
                // 导入方式切换
                Text('导入方式',
                    style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _TypeToggle(
                        label: '远程导入',
                        icon: Icons.wifi_tethering,
                        selected: _importType == 'network',
                        onTap: () =>
                            setState(() => _importType = 'network'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _TypeToggle(
                        label: '文件导入',
                        icon: Icons.folder_open,
                        selected: _importType == 'file',
                        onTap: () => setState(() => _importType = 'file'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // URL 输入 / 文件选择
                if (_importType == 'network')
                  TextField(
                    controller: _urlCtrl,
                    decoration: const InputDecoration(
                      labelText: 'M3U 链接',
                      hintText: 'http://example.com/playlist.m3u',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.url,
                  )
                else
                  InkWell(
                    onTap: _pickFile,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 16),
                      decoration: BoxDecoration(
                        border: Border.all(
                            color: Theme.of(context)
                                .colorScheme
                                .outlineVariant),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.attach_file,
                              size: 20,
                              color:
                                  Theme.of(context).colorScheme.primary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _fileName ?? '点击选择本地 m3u/m3u8/txt 文件',
                              style: TextStyle(
                                color: _fileName == null
                                    ? Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant
                                    : null,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                // 自动更新(仅 network)
                if (_importType == 'network')
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('启动时自动更新'),
                    value: _autoUpdate,
                    onChanged: (v) => setState(() => _autoUpdate = v),
                  ),
                const SizedBox(height: 20),
                // 操作按钮
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _saving
                          ? null
                          : () => Navigator.of(context).pop(),
                      child: const Text('取消'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : Text(isEdit ? '保存' : '导入'),
                    ),
                  ],
                ),
              ],
            ),
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
    final color = selected
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.onSurfaceVariant;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? Theme.of(context).colorScheme.primary.withAlpha(30)
              : null,
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.outlineVariant,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 4),
            Text(label,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: color, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
