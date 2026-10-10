import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perfect_freehand/perfect_freehand.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/tools/eraser.dart';
import 'package:sbn/has_size.dart';

/// 这个文件原来测的是 `checkForOverlappingStrokes` / `onDragEnd`，
/// 那套 API 在「橡皮擦三模式」那次重构里被 `Eraser.eraseAt` 取代了，
/// 所以这里按新 API 重写。**用例本身没动** ——
/// 「1 倍 size 以内要擦掉、1.1 倍 size 以外不能碰」这组边界还是值得钉住的。
final _options = StrokeOptions(
  size: 1, // 尺寸小一点，测试里精度更高
);
const _eraserPos = Offset(50, 50);

void main() {
  test('笔迹模式：擦除范围内的整条被删掉，范围外的一条不动', () {
    final eraser = Eraser(size: 10);

    final List<Stroke> strokesToErase = [
      // 正中
      _strokeWithPoint(_eraserPos),

      // 正下 1 个 size
      _strokeWithPoint(_eraserPos + const Offset(0, 1) * eraser.size),

      // 正右 1 个 size
      _strokeWithPoint(_eraserPos + const Offset(1, 0) * eraser.size),

      // 斜向 1 个 sqrt(size)
      _strokeWithPoint(_eraserPos + const Offset(1, 1) * sqrt(eraser.size)),

      // 正右 0.5 个 size
      _strokeWithPoint(_eraserPos + const Offset(0.5, 0) * eraser.size),

      // 一条穿过正中的长线
      _strokeWithPoint(_eraserPos + const Offset(-20, -20) * eraser.size)
        ..addPoint(_eraserPos + const Offset(20, 20) * eraser.size)
        ..addPoint(_eraserPos + const Offset(20, 20) * eraser.size),
    ];

    final List<Stroke> strokesToKeep = [
      // 正下超过 1 个 size
      _strokeWithPoint(_eraserPos + const Offset(0, 1.1) * eraser.size),

      // 正右超过 1 个 size
      _strokeWithPoint(_eraserPos + const Offset(1.1, 0) * eraser.size),

      // 斜向超过 1 个 size
      _strokeWithPoint(_eraserPos + const Offset(1, 1) * eraser.size),

      // 正右 2 个 size
      _strokeWithPoint(_eraserPos + const Offset(2, 0) * eraser.size),
    ];

    final strokes = <Stroke>[...strokesToErase, ...strokesToKeep];
    final result = eraser.eraseAt(_eraserPos, strokes);

    for (final stroke in strokesToErase) {
      expect(
        result.removed,
        contains(stroke),
        reason: '应该被擦掉: $stroke',
      );
    }

    for (final stroke in strokesToKeep) {
      expect(
        result.removed,
        isNot(contains(stroke)),
        reason: '不该被擦掉: $stroke',
      );
    }

    // 笔迹模式是整条删除，不会切出新的分段
    expect(result.added, isEmpty, reason: '笔迹模式不该产生分段');
  });

  test('笔迹模式：在同一个位置再擦一遍，已经被移除的笔迹不再出现', () {
    final eraser = Eraser(size: 10);

    final strokes = [
      _strokeWithPoint(_eraserPos),
      _strokeWithPoint(_eraserPos + const Offset(0, 1) * eraser.size),
      _strokeWithPoint(_eraserPos + const Offset(5, 0) * eraser.size),
    ];

    final first = eraser.eraseAt(_eraserPos, strokes);
    expect(first.removed, hasLength(2));

    // 调用方会把擦掉的移出页面，剩下那些再擦一次不该有任何变化
    final remaining = strokes.where((s) => !first.removed.contains(s)).toList();
    final second = eraser.eraseAt(_eraserPos, remaining);
    expect(second.removed, isEmpty);
    expect(second.added, isEmpty);
  });
}

Stroke _strokeWithPoint(Offset point) => Stroke(
  color: Stroke.defaultColor,
  pressureEnabled: Stroke.defaultPressureEnabled,
  options: _options,
  pageIndex: 0,
  page: const HasSize(Size(100, 100)),
  toolId: .fountainPen,
)..addPoint(point);
