import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:one_dollar_unistroke_recognizer/one_dollar_unistroke_recognizer.dart';
import 'package:onyxsdk_pen/onyxsdk_pen.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/components/canvas/image/editor_image.dart';
import 'package:saber/components/canvas/inner_canvas.dart';
import 'package:saber/components/editor/math_embed.dart';
import 'package:saber/data/editor/editor_core_info.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/tools/_tool.dart';
import 'package:saber/data/tools/pen.dart';
import 'package:saber/data/tools/select.dart';
import 'package:saber/i18n/strings.g.dart';
import 'package:sbn/quill_styles.dart';
import 'package:sbn/tool_id.dart';

class Canvas extends StatelessWidget {
  const new({
    super.key,
    required this.path,
    required this.page,
    required this.pageIndex,
    required this.textEditing,
    required this.coreInfo,
    required this.currentStroke,
    required this.currentStrokeDetectedShape,
    required this.currentSelection,
    required this.setAsBackground,
    required this.currentTool,
    required this.currentScale,
    this.placeholder = false,
  });

  final String path;
  final EditorPage page;
  final int pageIndex;

  final bool textEditing;
  final EditorCoreInfo coreInfo;
  final Stroke? currentStroke;
  final RecognizedUnistroke? currentStrokeDetectedShape;
  final SelectResult? currentSelection;

  final void Function(EditorImage image)? setAsBackground;

  final Tool currentTool;
  final double currentScale;
  final bool placeholder;

  OnyxStrokeStyle _getOnyxTool(Tool currentTool) {
    if (placeholder) return OnyxStrokeStyle.pen;
    switch (currentTool.toolId) {
      case ToolId.fountainPen:
        return OnyxStrokeStyle.brush;
      case ToolId.ballpointPen:
        return OnyxStrokeStyle.pen;
      case ToolId.highlighter:
        return OnyxStrokeStyle.marker;
      case ToolId.pencil:
        return OnyxStrokeStyle.pencil;
      case ToolId.shapePen:
        return OnyxStrokeStyle.disabled;
      case ToolId.eraser:
        return OnyxStrokeStyle.disabled;
      case ToolId.select:
        return OnyxStrokeStyle.pen;
      case ToolId.laserPointer:
        return OnyxStrokeStyle.pen;
      default:
        return OnyxStrokeStyle.disabled;
    }
  }

  Color _getOnyxColor() {
    if (currentTool is Pen) {
      return (currentTool as Pen).color;
    } else {
      return Colors.black;
    }
  }

  double _getOnyxWidth() {
    if (currentTool is Pen) {
      final baseSize = (currentTool as Pen).options.size * currentScale;
      if ((currentTool as Pen).pressureEnabled) {
        return baseSize;
      } else {
        return baseSize * 2;
      }
    } else {
      return 3;
    }
  }

  @override
  Widget build(BuildContext context) {
    final invert = stows.editorAutoInvert.value &&
        Theme.brightnessOf(context) == Brightness.dark;

    final pageContent = !placeholder
        ? SizedBox(
            width: page.size.width,
            height: page.size.height,
            child: OnyxSdkPenArea(
              refreshDelay: const Duration(seconds: 1),
              strokeStyle: _getOnyxTool(currentTool),
              strokeColor: _getOnyxColor(),
              strokeWidth: _getOnyxWidth(),
              child: InnerCanvas(
                key: page.innerCanvasKey,
                pageIndex: pageIndex,
                redrawPageListenable: page,
                width: page.size.width,
                height: page.size.height,
                textEditing: textEditing,
                coreInfo: coreInfo,
                currentStroke: currentStroke,
                currentStrokeDetectedShape: currentStrokeDetectedShape,
                currentSelection: currentSelection,
                setAsBackground: setAsBackground,
                currentToolIsSelect: currentTool.toolId == ToolId.select,
                currentScale: currentScale,
              ),
            ),
          )
        : SizedBox(width: page.size.width, height: page.size.height);

    // 浮动文本框挂在 InnerCanvas **外面**这一层。
    // InnerCanvas 里 CustomPaint 的 child 在这台设备上画不出来（背景走 painter、
    // 笔迹走 foregroundPainter，两者都正常，只有 child 那一支是空的），
    // 所以文本框不能放在它里面。
    final content = Stack(
      children: [
        // 无边画布不画纸张阴影 —— 那一圈阴影正是用户看到的"页面分界线"
        if (coreInfo.isInfiniteCanvas)
          pageContent
        else
          DecoratedBox(
            decoration: BoxDecoration(
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 10,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: pageContent,
          ),
        for (final box in page.textBoxes)
          Positioned(
            left: box.position.dx,
            top: box.position.dy,
            child: CanvasTextBox(
              box: box,
              invert: invert,
              lineHeight: coreInfo.lineHeight,
              readOnly: coreInfo.readOnly,
            ),
          ),
      ],
    );

    // 无边画布是一整块大画布：不能套 FittedBox，否则会被压成"适应屏幕"那么小。
    // 保持原始尺寸，用户靠双指缩放/平移来看。
    if (coreInfo.isInfiniteCanvas) return content;

    return Center(child: FittedBox(child: content));
  }
}

/// 画布上的一个浮动文本框：带一圈细边框的小编辑器。
class CanvasTextBox extends StatelessWidget {
  const new({
    super.key,
    required this.box,
    required this.invert,
    required this.lineHeight,
    required this.readOnly,
  });

  final EditorTextBox box;
  final bool invert;
  final int lineHeight;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    return SizedBox(
      width: box.size.width,
      height: box.size.height,
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(
                  color: colorScheme.primary.withValues(alpha: .6),
                  width: 1.5,
                ),
                borderRadius: BorderRadius.circular(6),
                color: colorScheme.surface.withValues(
                  alpha: stows.textBoxOpacity.value.clamp(0.0, 1.0),
                ),
              ),
              child: IgnorePointer(
                ignoring: readOnly,
                child: QuillEditor(
                  controller: box.quill.controller,
                  config: QuillEditorConfig(
                    customStyles: SaberQuillStyles.get(
                      invert: invert,
                      secondary: colorScheme.secondary,
                      lineHeight: lineHeight,
                    ),
                    scrollable: true,
                    autoFocus: false,
                    expands: true,
                    placeholder: t.editor.quill.typeSomething,
                    showCursor: true,
                    keyboardAppearance: invert
                        ? Brightness.dark
                        : Brightness.light,
                    padding: const EdgeInsets.all(8),
                    showCodeBlockLineNumbers: false,
                    // 文本框里的 LaTeX 公式（内联 embed）
                    embedBuilders: const [MathEmbedBuilder()],
                  ),
                  scrollController: ScrollController(),
                  focusNode: box.quill.focusNode,
                ),
              ),
            ),
          ),
          // 右上角一个小按钮：在光标处插一个公式
          Positioned(
            top: 2,
            right: 2,
            child: _InsertMathButton(
              controller: box.quill.controller,
              enabled: !readOnly,
            ),
          ),
        ],
      ),
    );
  }
}

/// 文本框右上角那个「∑」小按钮。
class _InsertMathButton extends StatelessWidget {
  const new({required this.controller, required this.enabled});

  final QuillController controller;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    return Tooltip(
      message: t.editor.insertMath,
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: enabled ? () => promptForMath(context, controller) : null,
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Icon(
            Icons.functions,
            size: 16,
            color: colorScheme.primary.withValues(alpha: enabled ? .8 : .3),
          ),
        ),
      ),
    );
  }
}
