import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perfect_freehand/perfect_freehand.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/tools/eraser.dart';
import 'package:sbn/eraser_mode.dart';
import 'package:sbn/has_size.dart';
import 'package:sbn/tool_id.dart';

class _Page implements HasSize {
  @override
  final size = const Size(1000, 1000);
}

Stroke makeStroke(List<Offset> points) {
  final stroke = Stroke(
    color: Colors.black,
    pressureEnabled: false,
    options: StrokeOptions(),
    pageIndex: 0,
    page: _Page(),
    toolId: ToolId.fountainPen,
  );
  stroke.addPoints(points);
  return stroke;
}

/// 一条从 x=0 到 x=800、每 20 一格的横线（41 个点）。
Stroke horizontalStroke() =>
    makeStroke([for (var i = 0; i <= 40; i++) Offset(i * 20.0, 500)]);

void main() {
  group('Eraser 擦除', () {
    test('笔迹模式：碰到就整条删掉', () {
      final stroke = horizontalStroke();
      final eraser = Eraser(mode: EraserMode.stroke, size: 20);

      final result = eraser.eraseAt(const Offset(400, 500), [stroke]);

      expect(result.removed, [stroke]);
      expect(result.added, isEmpty);
    });

    test('笔迹模式：离得远就不动它', () {
      final stroke = horizontalStroke();
      final eraser = Eraser(mode: EraserMode.stroke, size: 20);

      final result = eraser.eraseAt(const Offset(400, 900), [stroke]);

      expect(result.removed, isEmpty);
      expect(result.added, isEmpty);
    });

    test('圆形擦子：中间挖掉后笔迹被切成两条', () {
      final stroke = horizontalStroke();
      final eraser = Eraser(mode: EraserMode.circle, size: 60);

      final result = eraser.eraseAt(const Offset(400, 500), [stroke]);

      expect(result.removed, [stroke], reason: '原来的整条要被替换掉');
      expect(result.added.length, 2, reason: '左边一段 + 右边一段');
      // 两段都不该还盖在擦除区域里
      // （插值会让新笔迹的点数变多，所以不能拿总点数跟原来比）
      for (final segment in result.added) {
        expect(segment.length, greaterThan(1));
        expect(
          segment.lowQualityPolygon.every((p) => (p.dx - 400).abs() > 1),
          isTrue,
          reason: '切完的笔迹不该还有顶点落在被挖掉的中心附近',
        );
      }
    });

    test('方形擦子：同样能切开，但判定形状是方的', () {
      final stroke = horizontalStroke();
      final eraser = Eraser(mode: EraserMode.square, size: 60);

      final result = eraser.eraseAt(const Offset(400, 500), [stroke]);

      expect(result.removed, [stroke]);
      expect(result.added.length, 2);
    });

    test('方形擦子：横向够近但纵向超出方框时不该擦到', () {
      // 方形擦子只看 |dx|<=size 且 |dy|<=size，这个点在斜对角外侧
      final stroke = horizontalStroke();
      final eraser = Eraser(mode: EraserMode.square, size: 30);

      final result = eraser.eraseAt(const Offset(400, 590), [stroke]);

      expect(result.removed, isEmpty, reason: '离 90 已经超出 30 的方框');
    });

    test('圆形擦子：擦掉整条时返回空的分段', () {
      final stroke = makeStroke([
        const Offset(500, 500),
        const Offset(510, 500),
        const Offset(520, 500),
      ]);
      final eraser = Eraser(mode: EraserMode.circle, size: 100);

      final result = eraser.eraseAt(const Offset(510, 500), [stroke]);

      expect(result.removed, [stroke]);
      expect(result.added, isEmpty, reason: '整条都没了，没有剩余分段');
    });

    test('size 会被夹在允许范围内', () {
      final eraser = Eraser();
      eraser.size = 1;
      expect(eraser.size, Eraser.sizeMin);
      eraser.size = 9999;
      expect(eraser.size, Eraser.sizeMax);
    });
    test('圆擦：点很稀的长线也要按区域切开，不能整条消失', () {
      // 只有 3 个点的长线（快速划一笔的典型情况），擦除区域落在中间两点之间
      final stroke = makeStroke([
        const Offset(0, 500),
        const Offset(400, 500),
        const Offset(800, 500),
      ]);
      final eraser = Eraser(mode: EraserMode.circle, size: 60);

      final result = eraser.eraseAt(const Offset(400, 500), [stroke]);

      expect(result.removed, [stroke]);
      expect(
        result.added.length,
        2,
        reason: '中间那一下就挖掉一小段，两边应该都留下来（补插值后才成立）',
      );
    });

    test('方擦：稀疏点同理', () {
      final stroke = makeStroke([
        const Offset(0, 500),
        const Offset(400, 500),
        const Offset(800, 500),
      ]);
      final eraser = Eraser(mode: EraserMode.square, size: 60);

      final result = eraser.eraseAt(const Offset(400, 500), [stroke]);

      expect(result.removed, [stroke]);
      expect(result.added.length, 2);
    });
  });

  group('笔迹采样率', () {
    test('每两个触点之间会插一个中点（点数约翻倍）', () {
      final stroke = Stroke(
        color: Colors.black,
        pressureEnabled: false,
        options: StrokeOptions(),
        pageIndex: 0,
        page: _Page(),
        toolId: ToolId.fountainPen,
      );

      stroke.addPoint(Offset.zero);
      expect(stroke.length, 1, reason: '第一个点没有前一个点，不插值');

      stroke.addPoint(const Offset(10, 0));
      expect(
        stroke.length,
        3,
        reason: '1 个中点 + 1 个真实点，追加在原来那个点之后',
      );

      stroke.addPoint(const Offset(20, 0));
      expect(stroke.length, 5, reason: '每次真实触点都带一个中点');
    });
  });
}
