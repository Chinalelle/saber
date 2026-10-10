import 'package:flutter/material.dart';
import 'package:saber/components/theming/uni_icon.dart';
import 'package:stow/stow.dart';

/// 一个「点一下弹框填文本」的设置项，给 API Key、接口地址这类值用。
///
/// 长按可以清空（跟 [SettingsSwitch] 的长按重置保持一致的手感）。
class SettingsTextInput extends StatefulWidget {
  const new({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    required this.pref,
    this.hintText,
    this.helperText,
    this.obscureText = false,
    this.keyboardType,
    this.validator,
  });

  final String title;
  final String? subtitle;
  final Object? icon;
  final Stow<dynamic, String, dynamic> pref;
  final String? hintText;
  final String? helperText;

  /// 输入时打码显示（API Key 用）。
  final bool obscureText;
  final TextInputType? keyboardType;

  /// 返回非 null 表示不合法，直接显示这句话并阻止保存。
  final String? Function(String value)? validator;

  @override
  State<SettingsTextInput> createState() => _SettingsTextInputState();
}

class _SettingsTextInputState extends State<SettingsTextInput> {
  @override
  void initState() {
    widget.pref.addListener(onChanged);
    super.initState();
  }

  @override
  void dispose() {
    widget.pref.removeListener(onChanged);
    super.dispose();
  }

  void onChanged() => setState(() {});

  String get _displayValue {
    final value = widget.pref.value;
    if (value.isEmpty) return '';
    if (!widget.obscureText) return value;
    // Key 只露最后 4 位
    if (value.length <= 4) return '••••';
    return '••••${value.substring(value.length - 4)}';
  }

  Future<void> _edit() async {
    final controller = TextEditingController(text: widget.pref.value);
    String? errorText;

    final result = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(widget.title),
          content: TextField(
            controller: controller,
            autofocus: true,
            obscureText: widget.obscureText,
            keyboardType: widget.keyboardType,
            decoration: InputDecoration(
              hintText: widget.hintText,
              helperText: widget.helperText,
              errorText: errorText,
            ),
            onSubmitted: (_) => Navigator.of(context).pop(controller.text),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final value = controller.text.trim();
                final error = widget.validator?.call(value);
                if (error != null) {
                  setDialogState(() => errorText = error);
                  return;
                }
                Navigator.of(context).pop(value);
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );

    controller.dispose();

    if (result != null && result != widget.pref.value) {
      widget.pref.value = result;
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    final value = _displayValue;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
      leading: widget.icon == null ? null : UniIcon(widget.icon!),
      title: Text(widget.title),
      subtitle: widget.subtitle == null ? null : Text(widget.subtitle!),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (value.isNotEmpty)
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 180),
              child: Text(
                value,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
            ),
          const SizedBox(width: 4),
          Icon(Icons.edit_outlined, color: colorScheme.onSurfaceVariant),
        ],
      ),
      onTap: _edit,
      onLongPress: () {
        if (widget.pref.value.isEmpty) return;
        widget.pref.value = '';
        setState(() {});
      },
    );
  }
}
