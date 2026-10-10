import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:saber/data/extensions/axis_extensions.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/tools/eraser.dart';
import 'package:saber/i18n/strings.g.dart';
import 'package:sbn/eraser_mode.dart';

/// 橡皮擦的工具选项：挑模式（笔迹／圆形／方形）+ 调擦子大小。
///
/// 大小的调节方式跟笔的粗细保持一致（同一套工具栏弹出面板）。
class EraserModal extends StatefulWidget {
  const new({super.key, required this.getTool, this.onChanged});

  final Eraser Function() getTool;

  /// 模式/大小改动后通知 editor 重绘。
  ///
  /// 注意别用 `setTool` —— 那个入口对 Eraser 有「再传一次就把工具切回上一个」的
  /// 特殊处理，面板改个模式会被它顺手把橡皮擦收掉。
  final VoidCallback? onChanged;

  @override
  State<EraserModal> createState() => _EraserModalState();
}

class _EraserModalState extends State<EraserModal> {
  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    final axis = stows.editorToolbarAlignment.value.axis.opposite;
    final eraser = widget.getTool();

    Widget modeButton(EraserMode mode, Widget icon, String tooltip) {
      final selected = eraser.mode == mode;
      return IconButton(
        tooltip: tooltip,
        onPressed: () => setState(() {
          eraser.mode = mode;
          widget.onChanged?.call();
        }),
        style: TextButton.styleFrom(
          foregroundColor: selected
              ? colorScheme.secondary
              : colorScheme.onSurface,
          backgroundColor: selected
              ? colorScheme.secondary.withValues(alpha: 0.1)
              : Colors.transparent,
          shape: const CircleBorder(),
        ),
        icon: icon,
      );
    }

    return Flex(
      direction: axis,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        modeButton(
          EraserMode.stroke,
          const FaIcon(FontAwesomeIcons.eraser, size: 20),
          t.editor.eraser.modeStroke,
        ),
        modeButton(
          EraserMode.circle,
          const Icon(Icons.circle_outlined, size: 22),
          t.editor.eraser.modeCircle,
        ),
        modeButton(
          EraserMode.square,
          const Icon(Icons.crop_square, size: 20),
          t.editor.eraser.modeSquare,
        ),
        // 笔迹模式没有"大小"可调，只有圆／方擦子才有
        if (eraser.mode != EraserMode.stroke) ...[
          const SizedBox.square(dimension: 8),
          SizedBox(
            width: axis == Axis.horizontal ? 140 : null,
            height: axis == Axis.vertical ? 140 : null,
            child: RotatedBox(
              quarterTurns: axis == Axis.horizontal ? 0 : 1,
              child: Slider(
                value: eraser.size,
                min: Eraser.sizeMin,
                max: Eraser.sizeMax,
                onChanged: (value) => setState(() {
                  eraser.size = value;
                  widget.onChanged?.call();
                }),
              ),
            ),
          ),
          Text(
            t.editor.eraser.size,
            style: TextStyle(
              color: colorScheme.onSurface.withValues(alpha: 0.8),
              fontSize: 10,
              height: 1,
            ),
          ),
          Text(eraser.size.round().toString()),
        ],
      ],
    );
  }
}
