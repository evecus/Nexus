import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:nexus_ios/app/controller/app_settings_controller.dart';
import 'package:nexus_ios/app/routes.dart';

class NetworkVideoPage extends StatelessWidget {
  const NetworkVideoPage({super.key});

  @override
  Widget build(BuildContext context) {
    final urlCtrl = TextEditingController();
    final settings = AppSettingsController.instance;

    void play(String url) {
      final trimmed = url.trim();
      if (trimmed.isEmpty) return;
      AppNavigator.toVideoPlayer(
        playlist: [
          {'path': trimmed, 'name': trimmed}
        ],
        index: 0,
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // URL input
          TextField(
            controller: urlCtrl,
            decoration: InputDecoration(
              hintText: '输入视频链接（http/rtmp/rtsp/...）',
              prefixIcon: const Icon(Icons.link),
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: const Icon(Icons.play_circle_outline),
                tooltip: '播放',
                onPressed: () => play(urlCtrl.text),
              ),
            ),
            onSubmitted: play,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.go,
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              icon: const Icon(Icons.play_arrow),
              label: const Text('播放'),
              onPressed: () => play(urlCtrl.text),
            ),
          ),

          const SizedBox(height: 24),

          // Recent files
          Text('最近播放',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),

          Expanded(
            child: Obx(() {
              final recent = settings.recentFiles
                  .where((u) =>
                      u.startsWith('http') ||
                      u.startsWith('rtmp') ||
                      u.startsWith('rtsp'))
                  .toList();
              if (recent.isEmpty) {
                return Center(
                  child: Text('暂无最近播放记录',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          )),
                );
              }
              return ListView.separated(
                itemCount: recent.length,
                separatorBuilder: (_, __) => Divider(
                  height: 1,
                  color: Theme.of(context)
                      .colorScheme
                      .outlineVariant
                      .withAlpha(40),
                ),
                itemBuilder: (_, i) => ListTile(
                  leading: const Icon(Icons.history),
                  title: Text(
                    recent[i],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13),
                  ),
                  onTap: () {
                    urlCtrl.text = recent[i];
                    play(recent[i]);
                  },
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}
