import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:nexus/bookmarks/ios_directory_bookmark.dart';

/// "管理目录"页:iOS 端本地视频/音乐的"导入"入口。
///
/// 这是 iOS 与 Android 端在本地媒体获取方式上唯一的界面差异来源——
/// Android 端启动 App 时自动扫描整个设备存储,不需要用户手动选择;
/// iOS 沙盒无法做到这一点,只能由用户通过系统文件夹选择器明确"添加"
/// 一个目录(通常是"文件" App 里"我的 iPhone/iPad"下的某个文件夹,或
/// iCloud Drive、第三方云盘 App 提供的目录),App 记住这个目录的访问权限,
/// 之后每次进入视频/音乐库都会自动重新枚举这些已添加目录下的文件,
/// 效果上等价于 Android 端"扫描"这几个目录。
///
/// 视觉风格与 IPTV 源管理页(`iptv_tab_page.dart`)保持一致:空状态居中
/// 提示 + FAB 添加、列表项支持滑动/点击删除、AlertDialog 二次确认。
class DirectoryManagerController extends GetxController {
  final RxList<Map<String, dynamic>> directories =
      <Map<String, dynamic>>[].obs;
  final RxBool loading = true.obs;

  @override
  void onInit() {
    super.onInit();
    refresh_();
  }

  Future<void> refresh_() async {
    loading.value = true;
    try {
      final list = await IosDirectoryBookmark.listDirectories();
      directories.assignAll(list);
    } finally {
      loading.value = false;
    }
  }

  Future<void> addDirectory() async {
    final name = await IosDirectoryBookmark.pickAndAddDirectory();
    if (name != null) await refresh_();
  }

  Future<void> removeDirectory(String id) async {
    await IosDirectoryBookmark.removeDirectory(id);
    await refresh_();
  }
}

class DirectoryManagerPage extends StatelessWidget {
  const DirectoryManagerPage({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = Get.isRegistered<DirectoryManagerController>()
        ? Get.find<DirectoryManagerController>()
        : Get.put(DirectoryManagerController());

    return Scaffold(
      appBar: AppBar(title: const Text('管理目录')),
      body: SafeArea(
        child: Obx(() {
          if (ctrl.loading.value) {
            return const Center(child: CircularProgressIndicator());
          }
          if (ctrl.directories.isEmpty) {
            return _buildEmpty(context, ctrl);
          }
          return _buildList(context, ctrl);
        }),
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.create_new_folder_outlined),
        label: const Text('添加目录'),
        onPressed: ctrl.addDirectory,
      ),
    );
  }

  Widget _buildEmpty(BuildContext context, DirectoryManagerController ctrl) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.folder_off_outlined,
                size: 80,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text('还没有添加任何目录',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'iOS 系统不允许 App 自动扫描整个设备存储，\n请手动添加存放视频/音乐的文件夹，\n添加后每次打开会自动重新读取该文件夹内容。',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              icon: const Icon(Icons.create_new_folder_outlined),
              label: const Text('添加目录'),
              onPressed: ctrl.addDirectory,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList(BuildContext context, DirectoryManagerController ctrl) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 88),
      itemCount: ctrl.directories.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final dir = ctrl.directories[i];
        final id = dir['id'] as String? ?? '';
        final name = dir['displayName'] as String? ?? '未命名目录';
        final accessible = dir['accessible'] as bool? ?? false;
        return ListTile(
          leading: Icon(
            accessible ? Icons.folder : Icons.folder_off_outlined,
            color: accessible
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.error,
          ),
          title: Text(name),
          subtitle: accessible
              ? null
              : const Text('授权已失效，请移除后重新添加',
                  style: TextStyle(color: Colors.red)),
          trailing: IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: '移除',
            onPressed: () => _confirmRemove(context, ctrl, id, name),
          ),
        );
      },
    );
  }

  Future<void> _confirmRemove(BuildContext context,
      DirectoryManagerController ctrl, String id, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('移除目录'),
        content: Text('确定要移除「$name」吗？不会删除文件本身，只是 App 不再读取这个目录。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('移除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ctrl.removeDirectory(id);
    }
  }
}
