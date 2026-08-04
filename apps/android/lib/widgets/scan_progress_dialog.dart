import 'package:flutter/material.dart';

/// 扫描过程日志的驱动器。调用方在扫描开始前创建一个实例传给
/// [showScanProgressDialog]，扫描过程中不断调用 [appendLine] 追加一行日志，
/// 扫描结束后调用 [complete] 让弹窗把"确定"按钮从禁用变为可点击。
///
/// 弹窗关闭前用户无法通过返回键/点击遮罩关闭（[showScanProgressDialog]
/// 内部已设置 `barrierDismissible: false`），必须显式点击"确定"，避免用户
/// 在扫描进行中误触退出导致状态不一致。
class ScanProgressController {
  final ValueNotifier<List<String>> lines = ValueNotifier(<String>[]);
  final ValueNotifier<bool> finished = ValueNotifier(false);

  void appendLine(String line) {
    // 避免无界增长：仅保留最近 500 行用于展示，不影响扫描本身。
    final next = List<String>.from(lines.value)..add(line);
    if (next.length > 500) next.removeRange(0, next.length - 500);
    lines.value = next;
  }

  void complete() {
    finished.value = true;
  }

  void dispose() {
    lines.dispose();
    finished.dispose();
  }
}

/// 显示扫描进度弹窗（视频/音乐扫描通用）。
///
/// - [title] 弹窗标题，如"扫描视频"/"扫描音乐"。
/// - [controller] 由调用方持有，扫描过程中用它追加日志、标记完成。
/// - 弹窗自身不发起扫描，只负责展示；扫描逻辑由调用方在弹出后异步执行。
/// - 扫描未完成时"确定"按钮禁用；[controller.complete] 调用后按钮才可点击，
///   点击后关闭弹窗。
Future<void> showScanProgressDialog(
  BuildContext context, {
  required String title,
  required ScanProgressController controller,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => PopScope(
      // 扫描未完成时禁止用返回键关闭，避免中途退出导致状态不一致。
      canPop: false,
      child: _ScanProgressDialog(title: title, controller: controller),
    ),
  );
}

class _ScanProgressDialog extends StatelessWidget {
  final String title;
  final ScanProgressController controller;

  const _ScanProgressDialog({required this.title, required this.controller});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Dialog(
      backgroundColor: scheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.9,
          maxHeight: MediaQuery.of(context).size.height * 0.7,
          minWidth: 300,
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ValueListenableBuilder<bool>(
                valueListenable: controller.finished,
                builder: (context, finished, _) => Row(
                  children: [
                    if (!finished)
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      Icon(Icons.check_circle,
                          color: scheme.primary, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        finished ? '$title完成' : title,
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Flexible(
                child: Container(
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest.withAlpha(100),
                    borderRadius: BorderRadius.circular(8),
                    border:
                        Border.all(color: scheme.outlineVariant.withAlpha(120)),
                  ),
                  padding: const EdgeInsets.all(12),
                  child: ValueListenableBuilder<List<String>>(
                    valueListenable: controller.lines,
                    builder: (context, lines, _) {
                      if (lines.isEmpty) {
                        return Text(
                          '准备扫描…',
                          style: TextStyle(
                              color: scheme.onSurfaceVariant, fontSize: 13),
                        );
                      }
                      // 新日志追加在底部，用 ListView 让最新内容自动可见。
                      return ListView.builder(
                        reverse: true,
                        shrinkWrap: true,
                        itemCount: lines.length,
                        itemBuilder: (context, i) {
                          final line = lines[lines.length - 1 - i];
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Text(
                              line,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 13, color: scheme.onSurface),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 20),
              ValueListenableBuilder<bool>(
                valueListenable: controller.finished,
                builder: (context, finished, _) => SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed:
                        finished ? () => Navigator.of(context).pop() : null,
                    child: const Text('确定'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
