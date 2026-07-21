import 'package:flutter/material.dart';

/// 通用单选对话框,对应 NovaBox 的 `dialog_local_audio_option`。
///
/// 展示一个标题和一组选项,用户点击任意选项后立即返回所选索引并关闭对话框。
Future<int?> showOptionDialog(
  BuildContext context,
  String title,
  List<String> options, {
  int selected = 0,
}) {
  return showDialog<int>(
    context: context,
    builder: (ctx) {
      return Dialog(
        backgroundColor: Theme.of(ctx).colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(ctx).size.width * 0.8,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 8),
                ...List.generate(options.length, (i) {
                  final isSelected = i == selected;
                  return InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => Navigator.of(ctx).pop(i),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 14),
                      child: Row(
                        children: [
                          Icon(
                            isSelected
                                ? Icons.radio_button_checked
                                : Icons.radio_button_unchecked,
                            size: 20,
                            color: isSelected
                                ? Theme.of(ctx).colorScheme.primary
                                : Theme.of(ctx).colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              options[i],
                              style: Theme.of(ctx).textTheme.bodyLarge?.copyWith(
                                    color: isSelected
                                        ? Theme.of(ctx).colorScheme.primary
                                        : null,
                                    fontWeight: isSelected
                                        ? FontWeight.w600
                                        : null,
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 4),
              ],
            ),
          ),
        ),
      );
    },
  );
}
