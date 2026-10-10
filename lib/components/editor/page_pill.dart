import 'package:flutter/material.dart';
import 'package:saber/i18n/strings.g.dart';

/// 屏幕角落常驻的页码胶囊：`‹  12 / 128  ›`
///
/// 起因是「大文档里根本不知道自己在第几页，也没法快速跳到某一页」。
/// 点中间那段文字可以输入页码直接跳过去；两边的箭头翻上/下一页。
///
/// 只在文档式笔记里用 —— 无边画布只有一页，页码没有意义。
class PagePill extends StatelessWidget {
  const new({
    super.key,
    required this.currentPage,
    required this.pageCount,
    required this.onJump,
    this.onPrevious,
    this.onNext,
  });

  /// 当前页，0 起（内部计算用的就是这个）。
  final int currentPage;

  /// 总页数。
  final int pageCount;

  /// 跳到某一页，参数是 0 起的页下标。
  final ValueChanged<int> onJump;

  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  Future<void> _promptForPage(BuildContext context) async {
    final result = await showDialog<int>(
      context: context,
      builder: (_) => _GoToPageDialog(
        currentPage: currentPage,
        pageCount: pageCount,
      ),
    );
    if (result != null && result != currentPage) onJump(result);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);

    return Material(
      color: colorScheme.surface.withValues(alpha: 0.9),
      elevation: 3,
      borderRadius: BorderRadius.circular(999),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PillButton(
            icon: Icons.chevron_left,
            tooltip: t.editor.previousPage,
            onPressed: onPrevious,
          ),
          InkWell(
            onTap: () => _promptForPage(context),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Text(
                '${currentPage + 1} / $pageCount',
                style: TextStyle(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
          _PillButton(
            icon: Icons.chevron_right,
            tooltip: t.editor.nextPage,
            onPressed: onNext,
          ),
        ],
      ),
    );
  }
}

/// 「跳到第几页」的输入框。
///
/// 单独做成一个 StatefulWidget，是为了让 [TextEditingController] 的生命周期
/// 跟着对话框走 —— 在 `showDialog` 返回后立刻 dispose 会报
/// 「A TextEditingController was used after being disposed」，
/// 因为关闭动画还没跑完、TextField 还在读它。
class _GoToPageDialog extends StatefulWidget {
  const new({required this.currentPage, required this.pageCount});

  final int currentPage;
  final int pageCount;

  @override
  State<_GoToPageDialog> createState() => _GoToPageDialogState();
}

class _GoToPageDialogState extends State<_GoToPageDialog> {
  late final _controller = TextEditingController(
    text: '${widget.currentPage + 1}',
  );
  String? _errorText;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = int.tryParse(_controller.text.trim());
    if (value == null || value < 1 || value > widget.pageCount) {
      setState(() {
        _errorText = t.editor.pageNumberOutOfRange(max: '${widget.pageCount}');
      });
      return;
    }
    Navigator.of(context).pop(value - 1);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(t.editor.goToPage),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        textInputAction: TextInputAction.go,
        decoration: InputDecoration(
          labelText: t.editor.pageNumber,
          helperText: '1 – ${widget.pageCount}',
          errorText: _errorText,
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(MaterialLocalizations.of(context).okButtonLabel),
        ),
      ],
    );
  }
}

class _PillButton extends StatelessWidget {
  const new({required this.icon, required this.tooltip, this.onPressed});

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    return IconButton(
      icon: Icon(icon),
      tooltip: tooltip,
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
      color: onPressed == null
          ? colorScheme.onSurface.withValues(alpha: 0.3)
          : colorScheme.onSurface,
    );
  }
}
