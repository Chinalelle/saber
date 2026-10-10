import 'dart:ui';

import 'package:saber/components/canvas/_stroke.dart';

import 'package:saber/data/tools/_tool.dart';
import 'package:sbn/eraser_mode.dart';
import 'package:sbn/tool_id.dart';

double square(double x) => x * x;
double sqrDistanceBetween(Offset p1, Offset p2) =>
    square(p1.dx - p2.dx) + square(p1.dy - p2.dy);

/// 一次擦除的结果：要从页面里拿掉哪些笔迹、再放回去哪些。
///
/// 笔迹模式只会填 [removed]；圆形/方形擦子会把一条笔迹切成几段，
/// 于是原来的那条进 [removed]，切剩下的几段进 [added]。
typedef EraseResult = ({List<Stroke> removed, List<Stroke> added});

class Eraser extends Tool {
  /// 工作模式：笔迹／圆形擦子／方形擦子。
  EraserMode mode;

  /// 擦子大小。笔迹模式用它判断"碰没碰到"，圆方模式就是半径/半边长。
  double get size => _size;
  set size(double value) {
    _size = value.clamp(sizeMin, sizeMax);
    sqrSize = square(_size);
  }

  double _size;
  late double sqrSize;

  static const sizeMin = 4.0;
  static const sizeMax = 120.0;
  static const sizeStep = 2.0;
  int get sizeStepsBetweenMinAndMax => ((sizeMax - sizeMin) / sizeStep).round();

  new({this.mode = EraserMode.stroke, double size = 10})
    : _size = size.clamp(sizeMin, sizeMax),
      sqrSize = square(size.clamp(sizeMin, sizeMax));

  @override
  ToolId get toolId => .eraser;

  /// 当前在用的那把橡皮擦。
  ///
  /// 模式、大小都记在这个实例上，所以每次取工具时要返回它，
  /// 不能 `Eraser()` 新建一个 —— 那样用户刚调好的设置会丢。
  static var currentEraser = Eraser();

  /// 笔尖当前按在哪（页面坐标）。
  ///
  /// 圆／方擦子靠它在笔尖处画出"等大空心预览"；抬起或换成别的工具时置为 null。
  Offset? previewPosition;

  /// 用 [eraserPos] 处的擦子擦一遍，返回该怎么改动页面的笔迹列表。
  EraseResult eraseAt(Offset eraserPos, List<Stroke> strokes) {
    final removed = <Stroke>[];
    final added = <Stroke>[];

    for (final stroke in strokes) {
      if (mode == EraserMode.stroke) {
        // 老行为：碰到就整条删掉
        if (_shouldStrokeBeErased(eraserPos, stroke, sqrSize)) {
          removed.add(stroke);
        }
        continue;
      }

      // 圆形/方形：先把够不着的筛掉，再按区域切开
      if (!_touchesArea(eraserPos, stroke)) continue;

      final segments = stroke.cutBy((p) => isInsideArea(eraserPos, p));
      // 一条都没少说明其实没切到，别白白重建
      if (segments.length == 1 && segments.first.length == stroke.length) {
        continue;
      }
      removed.add(stroke);
      added.addAll(segments);
    }

    return (removed: removed, added: added);
  }

  /// [point] 在不在擦除区域里（圆／方各按各的形状判断）。
  bool isInsideArea(Offset center, Offset point) {
    if (mode == EraserMode.square) {
      return (point.dx - center.dx).abs() <= _size &&
          (point.dy - center.dy).abs() <= _size;
    }
    return sqrDistanceBetween(point, center) <= sqrSize;
  }

  /// 粗筛：笔迹有没有可能落在擦除区域附近。够不着就不用逐点算了。
  bool _touchesArea(Offset center, Stroke stroke) {
    final reach = _size + stroke.options.size;
    final sqrReach = square(reach);
    for (final vertex in stroke.lowQualityPolygon) {
      if (sqrDistanceBetween(vertex, center) <= sqrReach) return true;
    }
    return false;
  }

  /// 笔迹模式下的判定：这条笔迹有没有碰到擦子。
  static bool _shouldStrokeBeErased(
    Offset eraserPos,
    Stroke stroke,
    double sqrSize,
  ) {
    if (stroke.length <= 3) {
      if (stroke.lowQualityPath.contains(eraserPos)) return true;
    }

    /// skip checking every few vertices for performance
    final int verticesToSkip = switch (stroke.lowQualityPolygon.length) {
      < 100 => 0,
      < 1000 => 1,
      _ => 2,
    };

    for (
      int i = 0;
      i < stroke.lowQualityPolygon.length;
      i += verticesToSkip + 1
    ) {
      final Offset strokeVertex = stroke.lowQualityPolygon[i];
      if (sqrDistanceBetween(strokeVertex, eraserPos) <= sqrSize) return true;
    }
    return false;
  }
}
