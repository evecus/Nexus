import 'package:flutter/material.dart';

/// 显示一个轻量的搜索输入弹窗，输入内容会实时通过 [onChanged] 回调出去，
/// 由调用方据此过滤当前页面列表（不在弹窗内部展示结果，弹窗只负责输入）。
///
/// - 弹窗保持打开状态直到用户点击"关闭"或返回键，方便边看列表边继续改词
///   （列表在弹窗之下的页面里实时刷新）。
/// - [initialText] 用于弹窗重新打开时回显上次的搜索词。
/// - 用户点击"清空"会把词清零并同步回调一次空字符串。
Future<void> showSearchDialog(
  BuildContext context, {
  required String title,
  required String hintText,
  required ValueChanged<String> onChanged,
  String initialText = '',
}) {
  final controller = TextEditingController(text: initialText);
  return showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.9,
          minWidth: 300,
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: hintText,
                  prefixIcon: const Icon(Icons.search, size: 20),
                  isDense: true,
                  border: const OutlineInputBorder(),
                  suffixIcon: ValueListenableBuilder<TextEditingValue>(
                    valueListenable: controller,
                    builder: (context, value, _) {
                      if (value.text.isEmpty) return const SizedBox.shrink();
                      return IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () {
                          controller.clear();
                          onChanged('');
                        },
                      );
                    },
                  ),
                ),
                onChanged: onChanged,
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('关闭'),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
