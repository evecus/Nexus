import 'dart:io';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

import 'package:nexus_android/app/controller/app_settings_controller.dart';
import 'package:nexus_android/app/routes.dart';
import 'package:player_shared/player_shared.dart';

class IptvPlaylistController extends GetxController {
  final RxList<M3uChannel> channels = <M3uChannel>[].obs;
  final RxMap<String, List<M3uChannel>> grouped =
      <String, List<M3uChannel>>{}.obs;
  final RxBool isLoading = false.obs;
  final RxString currentSourceName = ''.obs;
  final RxString searchQuery = ''.obs;
  final RxString selectedGroup = '全部'.obs;

  List<M3uChannel> get filteredChannels {
    var list = channels.toList();
    if (selectedGroup.value != '全部') {
      list = list.where((c) => c.group == selectedGroup.value).toList();
    }
    if (searchQuery.value.isNotEmpty) {
      final q = searchQuery.value.toLowerCase();
      list = list
          .where((c) =>
              c.name.toLowerCase().contains(q) ||
              c.group.toLowerCase().contains(q))
          .toList();
    }
    return list;
  }

  List<String> get groups => ['全部', ...grouped.keys.toList()];

  Future<void> loadFromUrl(String url, String name) async {
    isLoading.value = true;
    currentSourceName.value = name;
    try {
      final resp = await Dio().get<String>(url,
          options: Options(responseType: ResponseType.plain));
      _parse(resp.data ?? '');
    } catch (e) {
      SmartDialog.showToast('加载失败: $e');
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> loadFromFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['m3u', 'm3u8', 'txt'],
    );
    if (result == null) return;
    final path = result.files.single.path;
    if (path == null) return;
    isLoading.value = true;
    currentSourceName.value = result.files.single.name;
    try {
      final content = await File(path).readAsString();
      _parse(content);
    } catch (e) {
      SmartDialog.showToast('读取文件失败: $e');
    } finally {
      isLoading.value = false;
    }
  }

  void _parse(String content) {
    final parsed = M3uParser.parse(content);
    channels.value = parsed;
    grouped.value = M3uParser.groupBy(parsed);
    selectedGroup.value = '全部';
  }

  void playChannel(M3uChannel ch) {
    AppNavigator.toIptvPlayer(
      url: ch.url,
      channelName: ch.name,
      groupName: ch.group,
    );
  }
}

class IptvPlaylistPage extends StatelessWidget {
  const IptvPlaylistPage({super.key});

  @override
  Widget build(BuildContext context) {
    // 说明同 VideoLibraryPage：已注册则直接复用，避免祖先 widget 树重建时
    // 反复创建新 controller 实例覆盖旧实例。
    final ctrl = Get.isRegistered<IptvPlaylistController>(tag: 'iptv_playlist')
        ? Get.find<IptvPlaylistController>(tag: 'iptv_playlist')
        : Get.put(IptvPlaylistController(), tag: 'iptv_playlist');
    final settings = AppSettingsController.instance;
    final searchCtrl = TextEditingController();

    return Scaffold(
      appBar: AppBar(
        title: const Text('IPTV'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '重新加载',
            onPressed: () {
              if (settings.iptvSources.isNotEmpty) {
                final s = settings.iptvSources.first;
                ctrl.loadFromUrl(s['url']!, s['name']!);
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Source selector + add buttons
          _buildSourceBar(context, ctrl, settings),

          // Search
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: TextField(
              controller: searchCtrl,
              decoration: const InputDecoration(
                hintText: '搜索频道...',
                prefixIcon: Icon(Icons.search, size: 20),
                isDense: true,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => ctrl.searchQuery.value = v,
            ),
          ),

          // Group chips
          Obx(() {
            if (ctrl.channels.isEmpty) return const SizedBox();
            return SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: ctrl.groups.length,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (_, i) {
                  final g = ctrl.groups[i];
                  return Obx(() => ChoiceChip(
                        label: Text(g, style: const TextStyle(fontSize: 12)),
                        selected: ctrl.selectedGroup.value == g,
                        onSelected: (_) => ctrl.selectedGroup.value = g,
                        visualDensity: VisualDensity.compact,
                      ));
                },
              ),
            );
          }),

          const SizedBox(height: 4),

          // Channel list
          Expanded(
            child: Obx(() {
              if (ctrl.isLoading.value) {
                return const Center(child: CircularProgressIndicator());
              }
              if (ctrl.channels.isEmpty) {
                return _buildEmpty(context, ctrl, settings);
              }
              final list = ctrl.filteredChannels;
              if (list.isEmpty) {
                return const Center(child: Text('没有匹配的频道'));
              }
              return ListView.builder(
                itemCount: list.length,
                itemBuilder: (_, i) => _channelTile(context, list[i], ctrl),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildSourceBar(BuildContext context, IptvPlaylistController ctrl,
      AppSettingsController settings) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Row(
        children: [
          Expanded(
            child: Obx(() {
              if (settings.iptvSources.isEmpty) {
                return const Text('未加载播放源',
                    style: TextStyle(fontSize: 13));
              }
              return DropdownButton<int>(
                isExpanded: true,
                underline: const SizedBox(),
                value: 0,
                items: settings.iptvSources
                    .asMap()
                    .entries
                    .map((e) => DropdownMenuItem(
                          value: e.key,
                          child: Text(
                            e.value['name'] ?? '',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ))
                    .toList(),
                onChanged: (i) {
                  if (i == null) return;
                  final s = settings.iptvSources[i];
                  ctrl.loadFromUrl(s['url']!, s['name']!);
                },
              );
            }),
          ),
          const SizedBox(width: 8),
          _addButton(context, ctrl, settings),
          IconButton(
            icon: const Icon(Icons.folder_open),
            tooltip: '从本地文件加载',
            onPressed: ctrl.loadFromFile,
          ),
        ],
      ),
    );
  }

  Widget _addButton(BuildContext context, IptvPlaylistController ctrl,
      AppSettingsController settings) {
    return IconButton(
      icon: const Icon(Icons.add_link),
      tooltip: '添加网络源',
      onPressed: () => _showAddSourceDialog(context, settings, ctrl),
    );
  }

  Future<void> _showAddSourceDialog(
    BuildContext context,
    AppSettingsController settings,
    IptvPlaylistController ctrl,
  ) async {
    final nameCtrl = TextEditingController();
    final urlCtrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('添加 IPTV 源'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: '名称'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: urlCtrl,
              decoration:
                  const InputDecoration(labelText: 'M3U 链接（http://...）'),
              keyboardType: TextInputType.url,
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消')),
          FilledButton(
            onPressed: () async {
              final name = nameCtrl.text.trim();
              final url = urlCtrl.text.trim();
              if (name.isEmpty || url.isEmpty) return;
              await settings.addIptvSource(
                  name: name, url: url, type: 'network');
              Navigator.pop(context);
              await ctrl.loadFromUrl(url, name);
            },
            child: const Text('添加并加载'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty(BuildContext context, IptvPlaylistController ctrl,
      AppSettingsController settings) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.live_tv_outlined,
              size: 80,
              color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(height: 16),
          Text('没有 IPTV 频道',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          const Text('添加网络 M3U 源 或 加载本地 m3u 文件'),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FilledButton.icon(
                icon: const Icon(Icons.add_link),
                label: const Text('添加网络源'),
                onPressed: () =>
                    _showAddSourceDialog(context, settings, ctrl),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.folder_open),
                label: const Text('本地文件'),
                onPressed: ctrl.loadFromFile,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _channelTile(
      BuildContext context, M3uChannel ch, IptvPlaylistController ctrl) {
    return ListTile(
      leading: ch.logo.isNotEmpty
          ? ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Image.network(
                ch.logo,
                width: 40,
                height: 40,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => _defaultChannelIcon(context),
              ),
            )
          : _defaultChannelIcon(context),
      title: Text(ch.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(ch.group,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              )),
      trailing: const Icon(Icons.play_arrow_rounded),
      onTap: () => ctrl.playChannel(ch),
    );
  }

  Widget _defaultChannelIcon(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color:
            Theme.of(context).colorScheme.primaryContainer.withAlpha(80),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Icon(Icons.live_tv,
          size: 22, color: Theme.of(context).colorScheme.primary),
    );
  }
}
