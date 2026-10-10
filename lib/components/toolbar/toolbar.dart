import 'dart:io';

import 'package:collapsible/collapsible.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:keybinder/keybinder.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:saber/components/theming/adaptive_icon.dart';
import 'package:saber/components/theming/dynamic_material_app.dart';
import 'package:saber/components/theming/uni_icon.dart';
import 'package:saber/components/toolbar/color_bar.dart';
import 'package:saber/components/toolbar/eraser_modal.dart';
import 'package:saber/components/toolbar/export_bar.dart';
import 'package:saber/components/toolbar/pen_modal.dart';
import 'package:saber/components/toolbar/selection_bar.dart';
import 'package:saber/components/toolbar/size_picker.dart';
import 'package:saber/components/toolbar/toolbar_button.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/extensions/color_extensions.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/tools/_tool.dart';
import 'package:saber/data/tools/eraser.dart';
import 'package:saber/data/tools/highlighter.dart';
import 'package:saber/data/tools/laser_pointer.dart';
import 'package:saber/data/tools/pen.dart';
import 'package:saber/data/tools/pencil.dart';
import 'package:saber/data/tools/select.dart';
import 'package:saber/i18n/strings.g.dart';
import 'package:sbn/eraser_mode.dart';

class Toolbar extends StatefulWidget {
  const new({
    super.key,
    required this.readOnly,
    required this.setTool,
    required this.currentTool,
    required this.setColor,
    required this.quillFocus,
    required this.textEditing,
    required this.toggleTextEditing,
    required this.undo,
    required this.isUndoPossible,
    required this.redo,
    required this.isRedoPossible,
    required this.toggleFingerDrawing,
    required this.pickPhoto,
    required this.paste,
    required this.duplicateSelection,
    required this.deleteSelection,
    required this.exportAsSba,
    required this.exportAsPdf,
    required this.exportAsPng,
    required this.exportAsMarkdown,
    this.onToolbarDragStart,
    this.onToolbarDragUpdate,
    this.onToolbarDragEnd,
    this.takePhoto,
    this.insertTextBox,
    this.onEraserChanged,
    this.onCollapse,
  });

  final bool readOnly;

  final ValueChanged<Tool> setTool;
  final Tool currentTool;
  final ValueChanged<Color> setColor;

  final ValueNotifier<QuillStruct?> quillFocus;
  final bool textEditing;
  final VoidCallback toggleTextEditing;

  final VoidCallback undo;
  final bool isUndoPossible;
  final VoidCallback redo;
  final bool isRedoPossible;

  final VoidCallback toggleFingerDrawing;

  final VoidCallback pickPhoto;

  /// 调起相机拍一张，确认后直接把照片插进笔记。
  final VoidCallback? takePhoto;

  /// 在当前页插一个浮动文本框。
  final VoidCallback? insertTextBox;

  /// 橡皮擦面板改了模式/大小时通知编辑页重绘。
  final VoidCallback? onEraserChanged;

  /// 点一下把工具栏收成边缘的一条细条（想腾出屏幕写字时用）。
  /// 为空时不显示这个按钮。
  final VoidCallback? onCollapse;

  final VoidCallback paste;

  final VoidCallback duplicateSelection;
  final VoidCallback deleteSelection;

  final Future Function(BuildContext)? exportAsSba;
  final Future Function(BuildContext)? exportAsPdf;
  final Future Function(BuildContext)? exportAsPng;
  final Future Function(BuildContext)? exportAsMarkdown;

  /// 拖动工具栏左端的小把手时回调，用来把工具栏拖到别的边去。
  final void Function(DragStartDetails details)? onToolbarDragStart;
  final void Function(DragUpdateDetails details)? onToolbarDragUpdate;
  final void Function(DragEndDetails details)? onToolbarDragEnd;

  @override
  State<Toolbar> createState() => _ToolbarState();

  static const _buttonPaddingHorizontal = EdgeInsets.symmetric(horizontal: 6);
  static const _buttonPaddingVertical = EdgeInsets.symmetric(vertical: 6);
}

class _ToolbarState extends State<Toolbar> {
  ValueNotifier<bool> showExportOptions = ValueNotifier(false);
  ValueNotifier<bool> showColorOptions = ValueNotifier(false);
  ValueNotifier<ToolOptions> toolOptionsType = ValueNotifier(ToolOptions.hide);

  @override
  void initState() {
    _assignKeybindings();

    DynamicMaterialApp.addFullscreenListener(_setState);

    super.initState();
  }

  void _setState() => setState(() {});

  Keybinding? _ctrlF;
  Keybinding? _ctrlE;
  Keybinding? _ctrlC;
  Keybinding? _ctrlShiftS;
  Keybinding? _f11;
  Keybinding? _ctrlV;
  void _assignKeybindings() {
    _ctrlF = Keybinding([
      KeyCode.ctrl,
      KeyCode.from(LogicalKeyboardKey.keyF),
    ], inclusive: true);
    _ctrlE = Keybinding([
      KeyCode.ctrl,
      KeyCode.from(LogicalKeyboardKey.keyE),
    ], inclusive: true);
    _ctrlC = Keybinding([
      KeyCode.ctrl,
      KeyCode.from(LogicalKeyboardKey.keyC),
    ], inclusive: true);
    _ctrlShiftS = Keybinding([
      KeyCode.ctrl,
      KeyCode.shift,
      KeyCode.from(LogicalKeyboardKey.keyS),
    ], inclusive: true);
    _f11 = Keybinding([KeyCode.from(LogicalKeyboardKey.f11)], inclusive: true);
    _ctrlV = Keybinding([
      KeyCode.ctrl,
      KeyCode.from(LogicalKeyboardKey.keyV),
    ], inclusive: true);

    Keybinder.bind(_ctrlF!, widget.toggleFingerDrawing);
    Keybinder.bind(_ctrlE!, toggleEraser);
    Keybinder.bind(_ctrlC!, toggleColorOptions);
    Keybinder.bind(_ctrlShiftS!, toggleExportBar);
    Keybinder.bind(_f11!, toggleFullscreen);
    Keybinder.bind(_ctrlV!, widget.paste);
  }

  void _removeKeybindings() {
    if (_ctrlF != null) Keybinder.remove(_ctrlF!);
    if (_ctrlE != null) Keybinder.remove(_ctrlE!);
    if (_ctrlC != null) Keybinder.remove(_ctrlC!);
    if (_ctrlShiftS != null) Keybinder.remove(_ctrlShiftS!);
    if (_f11 != null) Keybinder.remove(_f11!);
    if (_ctrlV != null) Keybinder.remove(_ctrlV!);
  }

  void toggleEraser() {
    final wasEraser = widget.currentTool is Eraser;
    widget.setTool(Eraser.currentEraser); // this toggles eraser
    // 点橡皮擦就把它那排模式选项亮出来（原来这里是 .hide，等于点完什么都不给看）
    toolOptionsType.value =
        wasEraser && toolOptionsType.value == ToolOptions.eraser
        ? ToolOptions.hide
        : ToolOptions.eraser;
  }

  void toggleColorOptions() {
    showColorOptions.value = !showColorOptions.value;
  }

  void toggleExportBar() {
    showExportOptions.value = !showExportOptions.value;
  }

  void toggleFullscreen() async {
    DynamicMaterialApp.setFullscreen(
      !DynamicMaterialApp.isFullscreen,
      updateSystem: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);

    final brightness = Theme.brightnessOf(context);
    final invert = stows.editorAutoInvert.value && brightness == .dark;

    final isToolbarVertical =
        stows.editorToolbarAlignment.value == AxisDirection.left ||
        stows.editorToolbarAlignment.value == AxisDirection.right;

    final buttonPadding = isToolbarVertical
        ? Toolbar._buttonPaddingVertical
        : Toolbar._buttonPaddingHorizontal;

    final currentColor = switch (widget.currentTool) {
      final Pen pen => pen.color,
      final Select select => select.getDominantStrokeColor(),
      _ => null,
    };

    if (widget.currentTool == Select.currentSelect) {
      // Enable selection bar only when selection is done
      toolOptionsType.value = Select.currentSelect.doneSelecting
          ? .select
          : .hide;
    }
    // 注意：这里**不能**再写 "当前是橡皮擦就把面板设成 .eraser" ——
    // 那样每次重建都会把面板又拽回来，用户在面板里选完模式后收不起来。
    // 唤出面板的职责交给 toggleEraser()。

    final bars = <Widget>[
      ValueListenableBuilder(
        valueListenable: showExportOptions,
        builder: (context, showExportOptions, child) {
          return Collapsible(
            axis: isToolbarVertical
                ? CollapsibleAxis.horizontal
                : CollapsibleAxis.vertical,
            maintainState: true,
            collapsed: !showExportOptions,
            child: child!,
          );
        },
        child: ExportBar(
          axis: isToolbarVertical ? Axis.vertical : Axis.horizontal,
          toggleExportBar: toggleExportBar,
          exportAsSba: widget.exportAsSba,
          exportAsPdf: widget.exportAsPdf,
          exportAsPng: widget.exportAsPng,
          exportAsMarkdown: widget.exportAsMarkdown,
        ),
      ),
      ValueListenableBuilder(
        valueListenable: toolOptionsType,
        builder: (context, toolOptionsType, _) {
          return Collapsible(
            axis: isToolbarVertical
                ? CollapsibleAxis.horizontal
                : CollapsibleAxis.vertical,
            maintainState: true,
            collapsed: toolOptionsType == .hide,
            child: switch (toolOptionsType) {
              .hide => const SizedBox.square(dimension: SizePicker.smallLength),
              .pen => PenModal(
                getTool: () => Pen.currentPen,
                setTool: widget.setTool,
              ),
              .highlighter => PenModal(
                getTool: () => Highlighter.currentHighlighter,
                setTool: widget.setTool,
              ),
              .pencil => PenModal(
                getTool: () => Pencil.currentPencil,
                setTool: widget.setTool,
              ),
              .eraser => EraserModal(
                getTool: () => Eraser.currentEraser,
                onChanged: () {
                  // 选完模式就把选择栏收起来
                  this.toolOptionsType.value = ToolOptions.hide;
                  setState(() {});
                  widget.onEraserChanged?.call();
                },
              ),
              .select => SelectionBar(
                duplicateSelection: widget.duplicateSelection,
                deleteSelection: widget.deleteSelection,
              ),
            },
          );
        },
      ),
      ValueListenableBuilder(
        valueListenable: showColorOptions,
        builder: (context, showColorOptions, child) {
          return Collapsible(
            axis: isToolbarVertical
                ? CollapsibleAxis.horizontal
                : CollapsibleAxis.vertical,
            maintainState: true,
            collapsed: !showColorOptions,
            child: child!,
          );
        },
        child: ColorBar(
          axis: isToolbarVertical ? Axis.vertical : Axis.horizontal,
          setColor: widget.setColor,
          currentColor: currentColor,
          invert: invert,
        ),
      ),
      ValueListenableBuilder(
        valueListenable: widget.quillFocus,
        builder: (context, quill, _) {
          final baseButtonStyle =
              IconButtonTheme.of(context).style ?? const ButtonStyle();

          final iconTheme = QuillIconTheme(
            iconButtonUnselectedData: IconButtonData(
              style: baseButtonStyle.copyWith(
                backgroundColor: WidgetStateProperty.all(Colors.transparent),
                foregroundColor: WidgetStateProperty.all(colorScheme.primary),
              ),
            ),
            iconButtonSelectedData: IconButtonData(
              style: baseButtonStyle.copyWith(
                backgroundColor: WidgetStateProperty.all(colorScheme.primary),
                foregroundColor: WidgetStateProperty.all(colorScheme.onPrimary),
              ),
            ),
          );
          return Collapsible(
            axis: isToolbarVertical
                ? CollapsibleAxis.horizontal
                : CollapsibleAxis.vertical,
            maintainState: false,
            collapsed: !widget.textEditing || quill == null,
            child: quill != null
                ? QuillSimpleToolbar(
                    controller: quill.controller,
                    config: QuillSimpleToolbarConfig(
                      axis: isToolbarVertical ? Axis.vertical : Axis.horizontal,
                      buttonOptions: QuillSimpleToolbarButtonOptions(
                        base: QuillToolbarBaseButtonOptions(
                          iconTheme: iconTheme,
                        ),
                      ),
                      // scrollable on Android and iOS
                      multiRowsDisplay: !Platform.isAndroid && !Platform.isIOS,
                      showUndo: false,
                      showRedo: false,
                      showFontSize: false,
                      showFontFamily: false,
                      showClearFormat: false,
                    ),
                  )
                : const SizedBox.shrink(),
          );
        },
      ),
      Center(
        child: Padding(
          padding: const .all(8),
          child: Wrap(
            direction: isToolbarVertical ? Axis.vertical : Axis.horizontal,
            alignment: WrapAlignment.center,
            runSpacing: 8,
            children: [
              // 拖动把手：按住它可以把工具栏换到别的边。
              //
              // 必须放在这个 Wrap **里面**。放到外面再包一层 Row 的话，
              // Wrap 会拿到「宽度无限」的约束 → 不再换行 → 整条工具栏溢出屏幕，
              // 最右边的按钮被裁到屏幕外、点都点不着（实测踩过，
              // 还顺带让 golden 测试报 RenderFlex overflowed）。
              if (widget.onToolbarDragStart != null)
                _ToolbarDragHandle(
                  isVertical: isToolbarVertical,
                  onDragStart: widget.onToolbarDragStart!,
                  onDragUpdate: widget.onToolbarDragUpdate,
                  onDragEnd: widget.onToolbarDragEnd,
                ),
              // 位图编辑模式开关：开着的时候，画下去的东西会固化成像素
              ValueListenableBuilder(
                valueListenable: stows.editorBitmapMode,
                builder: (context, bitmapMode, _) => ToolbarIconButton(
                  tooltip: bitmapMode
                      ? t.editor.bitmapModeOn
                      : t.editor.bitmapModeOff,
                  selected: bitmapMode,
                  enabled: !widget.readOnly,
                  onPressed: () =>
                      stows.editorBitmapMode.value = !bitmapMode,
                  padding: buttonPadding,
                  child: const Icon(Icons.grain, size: 16),
                ),
              ),
              ToolbarIconButton(
                tooltip: Pen.currentPen.name,
                selected: widget.currentTool == Pen.currentPen,
                enabled: !widget.readOnly,
                onPressed: () {
                  if (widget.currentTool == Pen.currentPen) {
                    if (toolOptionsType.value == .pen) {
                      toolOptionsType.value = .hide;
                    } else {
                      toolOptionsType.value = .pen;
                    }
                  } else {
                    toolOptionsType.value = .hide;
                    widget.setTool(Pen.currentPen);
                  }
                },
                padding: buttonPadding,
                child: UniIcon(Pen.currentPen.icon, size: 16),
              ),
              ToolbarIconButton(
                tooltip: t.editor.pens.pencil,
                selected: widget.currentTool == Pencil.currentPencil,
                enabled: !widget.readOnly,
                onPressed: () {
                  if (widget.currentTool == Pencil.currentPencil) {
                    if (toolOptionsType.value == .pencil) {
                      toolOptionsType.value = .hide;
                    } else {
                      toolOptionsType.value = .pencil;
                    }
                  } else {
                    toolOptionsType.value = .hide;
                    widget.setTool(Pencil.currentPencil);
                  }
                },
                padding: buttonPadding,
                child: const FaIcon(Pencil.pencilIcon, size: 16),
              ),
              ToolbarIconButton(
                tooltip: t.editor.pens.highlighter,
                selected: widget.currentTool == Highlighter.currentHighlighter,
                enabled: !widget.readOnly,
                onPressed: () {
                  if (widget.currentTool == Highlighter.currentHighlighter) {
                    if (toolOptionsType.value == .highlighter) {
                      toolOptionsType.value = .hide;
                    } else {
                      toolOptionsType.value = .highlighter;
                    }
                  } else {
                    toolOptionsType.value = .hide;
                    widget.setTool(Highlighter.currentHighlighter);
                  }
                },
                padding: buttonPadding,
                child: const FaIcon(Highlighter.highlighterIcon, size: 16),
              ),
              ValueListenableBuilder(
                valueListenable: showColorOptions,
                builder: (context, showColorOptions, child) {
                  return ToolbarIconButton(
                    tooltip: t.editor.toolbar.toggleColors,
                    selected: showColorOptions,
                    enabled: !widget.readOnly,
                    onPressed: toggleColorOptions,
                    padding: buttonPadding,
                    child: child!,
                  );
                },
                child: currentColor == null
                    ? const Icon(Icons.palette)
                    : Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color: currentColor
                              .withInversion(invert)
                              .withValues(alpha: 1),
                          shape: .circle,
                          border: Border.all(
                            color: colorScheme.primary,
                            width: 2,
                          ),
                        ),
                      ),
              ),
              ToolbarIconButton(
                tooltip: t.editor.toolbar.select,
                selected: widget.currentTool is Select,
                enabled: !widget.readOnly,
                onPressed: () {
                  toolOptionsType.value = .hide;
                  widget.setTool(Select.currentSelect);
                },
                padding: buttonPadding,
                child: Icon(
                  CupertinoIcons.lasso,
                  shadows: !widget.readOnly
                      ? [
                          BoxShadow(
                            color: colorScheme.primary,
                            blurRadius: 0.1,
                            spreadRadius: 10,
                            blurStyle: BlurStyle.solid,
                          ),
                        ]
                      : null,
                ),
              ),
              ToolbarIconButton(
                tooltip: t.editor.pens.laserPointer,
                selected:
                    widget.currentTool == LaserPointer.currentLaserPointer,
                enabled: true, // even in read-only mode
                onPressed: () {
                  toolOptionsType.value = .hide;
                  widget.setTool(LaserPointer.currentLaserPointer);
                },
                padding: buttonPadding,
                child: const Icon(Symbols.stylus_laser_pointer),
              ),
              ToolbarIconButton(
                tooltip: t.editor.toolbar.toggleEraser,
                selected: widget.currentTool is Eraser,
                enabled: !widget.readOnly,
                onPressed: toggleEraser,
                padding: buttonPadding,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const FaIcon(FontAwesomeIcons.eraser, size: 16),
                    // 右下角标出当前用的是哪种擦子（笔迹模式不标）
                    if (Eraser.currentEraser.mode != EraserMode.stroke)
                      Positioned(
                        right: -5,
                        bottom: -5,
                        child: Icon(
                          Eraser.currentEraser.mode == EraserMode.square
                              ? Icons.square
                              : Icons.circle,
                          size: 10,
                          color: colorScheme.secondary,
                        ),
                      ),
                  ],
                ),
              ),
              ToolbarIconButton(
                tooltip: t.editor.toolbar.photo,
                enabled: !widget.readOnly,
                onPressed: widget.pickPhoto,
                padding: buttonPadding,
                child: const AdaptiveIcon(
                  icon: Icons.photo,
                  cupertinoIcon: CupertinoIcons.photo,
                ),
              ),
              // 拍照导入：调起相机，拍完确认后直接插进笔记
              if (widget.takePhoto != null)
                ToolbarIconButton(
                  tooltip: t.editor.toolbar.takePhoto,
                  enabled: !widget.readOnly,
                  onPressed: widget.takePhoto,
                  padding: buttonPadding,
                  child: const AdaptiveIcon(
                    icon: Icons.photo_camera,
                    cupertinoIcon: CupertinoIcons.camera,
                  ),
                ),
              // 插入浮动文本框（「无边画布」里写字靠它）
              if (widget.insertTextBox != null)
                ToolbarIconButton(
                  tooltip: t.editor.toolbar.insertTextBox,
                  enabled: !widget.readOnly,
                  onPressed: widget.insertTextBox,
                  padding: buttonPadding,
                  child: const AdaptiveIcon(
                    icon: Icons.add_box_outlined,
                    cupertinoIcon: CupertinoIcons.textbox,
                  ),
                ),
              ToolbarIconButton(
                tooltip: t.editor.toolbar.text,
                selected: widget.textEditing,
                enabled: !widget.readOnly,
                onPressed: widget.toggleTextEditing,
                padding: buttonPadding,
                child: const AdaptiveIcon(
                  icon: Icons.text_fields,
                  cupertinoIcon: CupertinoIcons.text_cursor,
                ),
              ),
              if (!stows.hideFingerDrawingToggle.value)
                ValueListenableBuilder(
                  valueListenable: stows.editorFingerDrawing,
                  builder: (context, value, child) {
                    return ToolbarIconButton(
                      tooltip: t.editor.toolbar.toggleFingerDrawing,
                      selected: value,
                      enabled: !widget.readOnly,
                      onPressed: widget.toggleFingerDrawing,
                      padding: buttonPadding,
                      child: const Icon(CupertinoIcons.hand_draw),
                    );
                  },
                ),
              ToolbarIconButton(
                tooltip: t.editor.toolbar.fullscreen,
                selected: DynamicMaterialApp.isFullscreen,
                enabled: !widget.readOnly,
                onPressed: toggleFullscreen,
                padding: buttonPadding,
                child: AdaptiveIcon(
                  icon: DynamicMaterialApp.isFullscreen
                      ? Icons.fullscreen_exit
                      : Icons.fullscreen,
                  cupertinoIcon: DynamicMaterialApp.isFullscreen
                      ? CupertinoIcons.fullscreen_exit
                      : CupertinoIcons.fullscreen,
                ),
              ),
              Wrap(
                direction: isToolbarVertical ? Axis.vertical : Axis.horizontal,
                children: [
                  ToolbarIconButton(
                    tooltip: t.editor.toolbar.undo,
                    enabled: !widget.readOnly && widget.isUndoPossible,
                    onPressed: widget.undo,
                    padding: buttonPadding,
                    child: const AdaptiveIcon(
                      icon: Icons.undo,
                      cupertinoIcon: CupertinoIcons.arrow_uturn_left,
                    ),
                  ),
                  ToolbarIconButton(
                    tooltip: t.editor.toolbar.redo,
                    enabled: !widget.readOnly && widget.isRedoPossible,
                    onPressed: widget.redo,
                    padding: buttonPadding,
                    child: const AdaptiveIcon(
                      icon: Icons.redo,
                      cupertinoIcon: CupertinoIcons.arrow_uturn_right,
                    ),
                  ),
                ],
              ),
              ValueListenableBuilder(
                valueListenable: showExportOptions,
                builder: (context, showExportOptions, child) {
                  return ToolbarIconButton(
                    tooltip: t.editor.toolbar.export,
                    selected: showExportOptions,
                    enabled: !widget.readOnly,
                    onPressed: toggleExportBar,
                    padding: buttonPadding,
                    child: child!,
                  );
                },
                child: const AdaptiveIcon(
                  icon: Icons.share,
                  cupertinoIcon: CupertinoIcons.share,
                ),
              ),
              // 工具栏末端的小按钮：点一下把工具栏收成边缘的一条细条
              if (widget.onCollapse != null)
                _ToolbarCollapseButton(
                  isVertical: isToolbarVertical,
                  onTap: widget.onCollapse!,
                ),
            ],
          ),
        ),
      ),
    ];

    final toolbarFlex = Flex(
      direction: isToolbarVertical ? Axis.horizontal : Axis.vertical,
      textDirection: switch (stows.editorToolbarAlignment.value) {
        AxisDirection.left => .rtl,
        AxisDirection.right => .ltr,
        _ => null,
      },
      verticalDirection: switch (stows.editorToolbarAlignment.value) {
        AxisDirection.down => VerticalDirection.down,
        AxisDirection.up => VerticalDirection.up,
        _ => VerticalDirection.down,
      },
      children: bars,
    );

    // 拖动把手和「收起」按钮都挂在上面那个 Wrap 的首尾，这里不再包一层
    // Row —— 那会让 Wrap 拿到宽度无限的约束，工具栏就不再换行了。
    return toolbarFlex;
  }

  @override
  void dispose() {
    DynamicMaterialApp.removeFullscreenListener(_setState);
    DynamicMaterialApp.setFullscreen(false, updateSystem: true);

    _removeKeybindings();
    super.dispose();
  }
}

/// 工具栏一端的小把手：拖动它就能把整条工具栏拖到别的边。
class _ToolbarDragHandle extends StatelessWidget {
  const new({
    required this.isVertical,
    required this.onDragStart,
    this.onDragUpdate,
    this.onDragEnd,
  });

  /// 工具栏目前是不是竖着排（贴在左边或右边）。
  final bool isVertical;

  final void Function(DragStartDetails details) onDragStart;
  final void Function(DragUpdateDetails details)? onDragUpdate;
  final void Function(DragEndDetails details)? onDragEnd;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.grab,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: onDragStart,
        onPanUpdate: onDragUpdate,
        onPanEnd: onDragEnd,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: RotatedBox(
            // 竖排时整个工具栏是"转过来"的，图标也转一下才不别扭
            quarterTurns: isVertical ? 1 : 0,
            child: Icon(
              Icons.drag_handle,
              size: 20,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

enum ToolOptions { hide, pen, highlighter, pencil, select, eraser }

/// 工具栏末端的小按钮：点一下把工具栏收成边缘的一条细条。
///
/// 收起来之后屏幕整块留给写字，想用工具栏时点那条细条就回来了。
class _ToolbarCollapseButton extends StatelessWidget {
  const new({required this.isVertical, required this.onTap});

  /// 工具栏目前是不是竖着排（贴在左边或右边）。
  final bool isVertical;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Tooltip(
          message: t.editor.hideToolbar,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: RotatedBox(
              quarterTurns: isVertical ? 1 : 0,
              child: Icon(
                // 贴上下时箭头朝下（往那条边收），贴左右时转 90°
                Icons.keyboard_arrow_down,
                size: 20,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
