import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saber/components/canvas/canvas_gesture_detector.dart';
import 'package:saber/data/editor/page.dart';

/// 「无边画布」不是一块固定大小的纸，而是拖到边上就往外接一段。
///
/// 这里钉住接的规则：还剩不到 buffer 就接 growBy；接完要能稳定下来
/// （不能一次接一次地抖着长），而且画布只增不减。
void main() {
  group('无边画布自动扩展', () {
    Size grow({
      Size canvas = const Size(8000, 8000),
      double left = 0,
      double top = 0,
      double right = 1363,
      double bottom = 748,
    }) => CanvasGestureDetectorState.grownCanvasSize(
      canvasSize: canvas,
      left: left,
      top: top,
      right: right,
      bottom: bottom,
    );

    test('视口还在画布中间：一点不动', () {
      expect(
        grow(left: 1000, top: 1000, right: 2363, bottom: 1748),
        const Size(8000, 8000),
      );
    });

    test('快到右边缘：往右接一段', () {
      final grown = grow(left: 5000, right: 7000, bottom: 1000);
      expect(grown.width, 7000 + 4000);
      expect(grown.height, 8000, reason: '纵向离边缘还很远，不该跟着长');
    });

    test('快到下边缘：往下接一段', () {
      final grown = grow(left: 1000, right: 2363, top: 5000, bottom: 7000);
      expect(grown.width, 8000);
      expect(grown.height, 7000 + 4000);
    });

    test('两个方向都到边：一起长', () {
      final grown = grow(left: 5000, top: 5000, right: 7000, bottom: 7000);
      expect(grown, const Size(11000, 11000));
    });

    test('接完就稳定：同一位置不会接着再长', () {
      final grown = grow(left: 5000, right: 7000, bottom: 1000);
      final again = grow(canvas: grown, left: 5000, right: 7000, bottom: 1000);
      expect(again, grown, reason: '长完之后 right 离新边界还有 growBy 那么远');
    });

    test('视口缩得很小、跑到画布中间：画布不缩水', () {
      final grown = grow(left: 3000, top: 3000, right: 4000, bottom: 3500);
      expect(grown, const Size(8000, 8000));
    });

    test('缩放到 0.3x 时视口很长，贴边照样触发', () {
      // scale=0.3，视口 1363x748 逻辑 -> 覆盖 4543x2493 的画布坐标
      final grown = grow(left: 0, top: 0, right: 4543, bottom: 2493);
      expect(grown.width, 8000, reason: '4543 < 8000-2000，还没到就该长的地方');
      expect(grown.height, 8000);
    });
  });

  group('EditorPage.growTo', () {
    test('只增不减', () {
      final page = EditorPage(size: const Size(8000, 8000));
      addTearDown(page.dispose);

      page.growTo(const Size(4000, 4000));
      expect(page.size, const Size(8000, 8000), reason: '不许缩回去');

      page.growTo(const Size(12000, 9000));
      expect(page.size, const Size(12000, 9000));

      page.growTo(const Size(11000, 20000));
      expect(page.size, const Size(12000, 20000), reason: '每个方向各取最大');
    });

    test('尺寸没变时不通知（避免白重建）', () {
      final page = EditorPage(size: const Size(8000, 8000));
      addTearDown(page.dispose);

      var notified = 0;
      page.addListener(() => notified++);

      page.growTo(const Size(8000, 8000));
      page.growTo(const Size(7000, 7000));
      expect(notified, 0);

      page.growTo(const Size(9000, 8000));
      expect(notified, 1);
    });
  });
}
