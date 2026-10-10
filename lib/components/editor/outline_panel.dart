import 'package:flutter/material.dart';
import 'package:saber/data/ai/outline_generator.dart';
import 'package:saber/data/editor/outline_entry.dart';
import 'package:saber/i18n/strings.g.dart';

/// 大纲面板的内容：按层级缩进列出条目，点一条就跳到对应页。
///
/// 只负责展示和回调，不管怎么生成 —— 生成逻辑在 editor 里，
/// 因为它要碰 PDF 文档、笔记数据和网络。
class OutlinePanel extends StatelessWidget {
  const new({
    super.key,
    required this.entries,
    required this.currentPage,
    required this.onTap,
    this.onGenerate,
    this.onCancel,
    this.progress,
  });

  final List<OutlineEntry> entries;

  /// 当前所在页（0 起），用来高亮「你在这里」。
  final int? currentPage;

  final ValueChanged<OutlineEntry> onTap;

  /// 没大纲时显示「生成」；已有大纲时显示「重新生成」。
  final VoidCallback? onGenerate;

  /// 正在生成时的取消回调。
  final VoidCallback? onCancel;

  /// 生成中的进度；为 null 表示没在生成。
  final OutlineProgress? progress;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);

    if (progress != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LinearProgressIndicator(value: progress!.fraction),
            const SizedBox(height: 16),
            Text(progress!.status, textAlign: TextAlign.center),
            const SizedBox(height: 4),
            Text(
              t.editor.outline.progress(
                done: '${progress!.done}',
                total: '${progress!.total}',
              ),
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            TextButton(
              onPressed: onCancel,
              child: Text(t.editor.outline.cancel),
            ),
          ],
        ),
      );
    }

    if (entries.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.list_alt_outlined,
              size: 40,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(t.editor.outline.empty),
            const SizedBox(height: 4),
            Text(
              t.editor.outline.emptyHint,
              textAlign: TextAlign.center,
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            if (onGenerate != null)
              FilledButton.icon(
                onPressed: onGenerate,
                icon: const Icon(Icons.auto_awesome),
                label: Text(t.editor.outline.generate),
              ),
          ],
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: entries.length,
            itemBuilder: (context, index) {
              final entry = entries[index];
              final isCurrent = entry.pageIndex == currentPage;
              // 层级最多缩进 3 级，再多就看不出结构了
              final indent = ((entry.level - 1).clamp(0, 2)) * 16.0;

              return ListTile(
                dense: true,
                contentPadding: EdgeInsets.only(
                  left: 16 + indent,
                  right: 16,
                ),
                leading: Icon(
                  entry.source == OutlineSource.pdfBookmark
                      ? Icons.bookmark_outline
                      : Icons.auto_awesome_outlined,
                  size: 18,
                  color: isCurrent
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant,
                ),
                title: Text(
                  entry.title,
                  style: TextStyle(
                    fontWeight: entry.level == 1
                        ? FontWeight.w600
                        : FontWeight.normal,
                    color: isCurrent ? colorScheme.primary : null,
                  ),
                ),
                trailing: Text(
                  '${entry.pageIndex + 1}',
                  style: TextStyle(color: colorScheme.onSurfaceVariant),
                ),
                selected: isCurrent,
                onTap: () => onTap(entry),
              );
            },
          ),
        ),
        if (onGenerate != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Row(
              children: [
                Text(
                  entries.first.source == OutlineSource.pdfBookmark
                      ? t.editor.outline.fromBookmarks
                      : t.editor.outline.fromAi,
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: onGenerate,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: Text(t.editor.outline.regenerate),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
