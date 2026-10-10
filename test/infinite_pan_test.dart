import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saber/components/canvas/interactive_canvas.dart';

/// 无边画布能不能左右拖，根子在于 child 拿到的是不是"无限宽"约束。
///
/// 视口只有 800x600，而画布是 6000x6000。如果 child 的宽度被压成视口宽，
/// `_boundaryRect` 的横向余量就是 0，横向拖动会被 clamp 掉 —— 表现就是
/// "只能上下拖"。这两个用例一个复现、一个验证修复。
Future<TransformationController> _pump(
  WidgetTester tester, {
  required bool unconstrainedWidth,
}) async {
  final controller = TransformationController();
  await tester.pumpWidget(
    MaterialApp(
      home: Center(
        child: SizedBox(
          width: 800,
          height: 600,
          child: InteractiveCanvasViewer.builder(
            unconstrainedWidth: unconstrainedWidth,
            transformationController: controller,
            minScale: 0.5,
            maxScale: 4,
            boundaryMargin: EdgeInsets.zero,
            builder: (context, viewport) =>
                const SizedBox(width: 6000, height: 6000),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return controller;
}

void main() {
  testWidgets('未放开宽度时：横向拖不动（复现旧行为）', (tester) async {
    final controller = await _pump(tester, unconstrainedWidth: false);

    await tester.dragFrom(const Offset(400, 300), const Offset(-200, 0));
    await tester.pumpAndSettle();

    expect(
      controller.value.getTranslation().x,
      0,
      reason: 'child 宽被压成视口宽，横向没有可平移的余量',
    );
  });

  testWidgets('放开宽度后：横向能拖出 200', (tester) async {
    final controller = await _pump(tester, unconstrainedWidth: true);

    await tester.dragFrom(const Offset(400, 300), const Offset(-200, 0));
    await tester.pumpAndSettle();

    expect(
      controller.value.getTranslation().x,
      closeTo(-200, 1),
      reason: '画布 6000 宽、视口 800 宽，横向余量充足，手指左移 200 内容就左移 200',
    );
  });

  testWidgets('放开宽度后：纵向依然是 200', (tester) async {
    final controller = await _pump(tester, unconstrainedWidth: true);

    await tester.dragFrom(const Offset(400, 300), const Offset(0, -200));
    await tester.pumpAndSettle();

    expect(controller.value.getTranslation().y, closeTo(-200, 1));
  });

  // 平板上单指是画笔，用户实际用的是双指平移，所以单指用例只能算参考。
  // 下面几个用例用两个 pointer 真按双指走一遍。
  testWidgets('双指平移：未放开宽度时横向依然拖不动', (tester) async {
    final controller = TransformationController();
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 800,
            height: 600,
            child: InteractiveCanvasViewer.builder(
              transformationController: controller,
              minScale: 0.5,
              maxScale: 4,
              boundaryMargin: EdgeInsets.zero,
              builder: (context, viewport) =>
                  const SizedBox(width: 6000, height: 6000),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final a = await tester.startGesture(const Offset(300, 300));
    final b = await tester.startGesture(const Offset(500, 300));
    for (var i = 0; i < 10; i++) {
      await a.moveBy(const Offset(-40, 0));
      await b.moveBy(const Offset(-40, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await a.up();
    await b.up();
    await tester.pumpAndSettle();

    expect(controller.value.getTranslation().x, 0);
  });

  testWidgets('双指平移：放开宽度后横向能拖 400', (tester) async {
    final controller = TransformationController();
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 800,
            height: 600,
            child: InteractiveCanvasViewer.builder(
              unconstrainedWidth: true,
              transformationController: controller,
              minScale: 0.5,
              maxScale: 4,
              boundaryMargin: EdgeInsets.zero,
              builder: (context, viewport) =>
                  const SizedBox(width: 6000, height: 6000),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final a = await tester.startGesture(const Offset(300, 300));
    final b = await tester.startGesture(const Offset(500, 300));
    for (var i = 0; i < 10; i++) {
      await a.moveBy(const Offset(-40, 0));
      await b.moveBy(const Offset(-40, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await a.up();
    await b.up();
    await tester.pumpAndSettle();

    // 手指刚按下时的那点位移会被触摸 slop 吃掉，所以留 25px 余量
    expect(
      controller.value.getTranslation().x,
      closeTo(-400, 25),
      reason: '横向余量充足，双指左移 400 内容就左移 400',
    );
  });

  // 双指缩放会一起改缩放，横向平移的余量跟着变；这里只要求"不是 0"。
  testWidgets('双指平移：斜向拖动两个方向都动', (tester) async {
    final controller = TransformationController();
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 800,
            height: 600,
            child: InteractiveCanvasViewer.builder(
              unconstrainedWidth: true,
              transformationController: controller,
              minScale: 0.5,
              maxScale: 4,
              boundaryMargin: EdgeInsets.zero,
              builder: (context, viewport) =>
                  const SizedBox(width: 6000, height: 6000),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final a = await tester.startGesture(const Offset(300, 300));
    final b = await tester.startGesture(const Offset(500, 300));
    for (var i = 0; i < 10; i++) {
      await a.moveBy(const Offset(-30, -20));
      await b.moveBy(const Offset(-30, -20));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await a.up();
    await b.up();
    await tester.pumpAndSettle();

    final t = controller.value.getTranslation();
    expect(t.x, lessThan(-100), reason: '横向必须真的动');
    expect(t.y, lessThan(-100), reason: '纵向必须真的动');
  });
}
