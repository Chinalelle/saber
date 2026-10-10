import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:saber/i18n/strings.g.dart';

/// Quill 里的内联公式。
///
/// 存进 Delta 就是一个自定义 embed：`{"insert":{"math":"E=mc^2"}}`，
/// 所以老版本 Saber 打开会看到一块"未知嵌入"，不会崩，也不会丢别的文字。
///
/// 渲染用纯 Dart 的 flutter_math_fork，不联网、不依赖系统字体。
class MathEmbedBuilder extends quill.EmbedBuilder {
  const new();

  /// Delta 里用的类型名。
  static const embedType = 'math';

  @override
  String get key => embedType;

  @override
  WidgetSpan buildWidgetSpan(Widget widget) {
    // 默认是贴底的，公式挂在文字中间才不难看
    return WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: widget,
    );
  }

  @override
  Widget build(BuildContext context, quill.EmbedContext embedContext) {
    final data = embedContext.node.value.data;
    return _MathSpan(tex: data is String ? data : '');
  }
}

class _MathSpan extends StatelessWidget {
  const new({required this.tex});

  final String tex;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
      child: Math.tex(
        tex,
        // inline：跟着字号走，不要占满一整行
        mathStyle: MathStyle.text,
        textStyle: TextStyle(
          color: colorScheme.onSurface,
          fontSize: 15,
        ),
      ),
    );
  }
}

/// 在光标处插一个公式；没有有效光标就插到末尾。
void insertMathEmbed(quill.QuillController controller, String tex) {
  final document = controller.document;
  final selection = controller.selection;
  final index = selection.isValid && selection.baseOffset >= 0
      ? selection.baseOffset
      : document.length - 1;
  controller.replaceText(
    index,
    0,
    quill.Embeddable(MathEmbedBuilder.embedType, tex),
    TextSelection.collapsed(offset: index + 1),
  );
}

/// 弹个输入框要 TeX 源码，确认后插到光标处。
Future<void> promptForMath(
  BuildContext context,
  quill.QuillController controller,
) async {
  final tex = await showDialog<String>(
    context: context,
    builder: (_) => const _MathInputDialog(),
  );
  if (tex == null || tex.trim().isEmpty) return;
  insertMathEmbed(controller, tex.trim());
}

class _MathInputDialog extends StatefulWidget {
  const new();

  @override
  State<_MathInputDialog> createState() => _MathInputDialogState();
}

class _MathInputDialogState extends State<_MathInputDialog> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final tex = _controller.text.trim();
    if (tex.isEmpty) {
      setState(() => _error = t.editor.mathEmpty);
      return;
    }
    // 先自己解析一遍，别等插进去才在文档里显示一段报错
    try {
      Math.tex(tex);
    } catch (e) {
      setState(() => _error = t.editor.mathInvalid);
      return;
    }
    Navigator.of(context).pop(tex);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      // 平板横屏的软键盘只占屏幕右下角，又没被算成 viewInsets，
      // 对话框居中时右下角的按钮必然被键盘压住 —— 干脆贴到屏幕上方。
      alignment: Alignment.topCenter,
      title: Text(t.editor.insertMath),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            maxLines: 3,
            minLines: 1,
            // 平板横屏时软键盘会盖住对话框右下角的「确定」，
            // 让键盘自带的「完成」也能当提交入口
            textInputAction: TextInputAction.done,
            style: const TextStyle(fontFamily: 'monospace'),
            decoration: InputDecoration(
              labelText: t.editor.mathTex,
              hintText: r'\frac{a}{b}',
              errorText: _error,
            ),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 12),
          // 边打边预览，省得插进去才发现括号写错了
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _controller,
            builder: (context, value, _) {
              final tex = value.text.trim();
              if (tex.isEmpty) return const SizedBox.shrink();
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: ColorScheme.of(context).surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Math.tex(tex, mathStyle: MathStyle.text),
              );
            },
          ),
          const SizedBox(height: 8),
          // 平板横屏的软键盘会盖住 AlertDialog 右下角的 actions（实测「确定」被压在键盘后面），
          // 所以把两个按钮放进内容里：键盘顶起来时它们跟着输入框一起往上走。
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(
                  MaterialLocalizations.of(context).cancelButtonLabel,
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _submit,
                child: Text(MaterialLocalizations.of(context).okButtonLabel),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
