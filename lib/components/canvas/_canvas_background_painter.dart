import 'dart:ui' show PointMode;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:saber/data/extensions/color_extensions.dart';
import 'package:sbn/canvas_background_pattern.dart';
import 'package:sbn/canvas_texture.dart';

class CanvasBackgroundPainter extends CustomPainter {
  const new({
    required this.invert,
    required this.backgroundColor,
    this.backgroundPattern = .none,
    this.texture = .smooth,
    required this.lineHeight,
    required this.lineThickness,
    this.gridDensity = 1.0,
    this.primaryColor = Colors.blue,
    this.secondaryColor = Colors.red,
    this.preview = false,
  });

  final bool invert;
  final Color backgroundColor;

  /// The pattern to use for the background. See [CanvasBackgroundPatterns].
  final CanvasBackgroundPattern backgroundPattern;

  /// 画布表面的质感（光滑／纸张）。
  final CanvasTexture texture;

  /// The height between each line in the background pattern
  final int lineHeight;
  final int lineThickness;

  /// 方格／点阵的疏密倍率：小于 1 更密。
  ///
  /// 只管 [CanvasBackgroundPattern.grid] 和 [CanvasBackgroundPattern.dots]；
  /// 横线纸、五线谱、康奈尔笔记这些还是老老实实按 lineHeight 走。
  final double gridDensity;
  final Color primaryColor, secondaryColor;

  /// Whether to draw the background pattern in a preview mode (more opaque).
  final bool preview;

  @override
  void paint(Canvas canvas, Size size) {
    final canvasRect = Offset.zero & size;
    final paint = Paint();

    paint.color = backgroundColor.withInversion(invert);
    canvas.drawRect(canvasRect, paint);

    paint.strokeWidth = lineThickness.toDouble();

    if (backgroundPattern.requiresClipping) {
      canvas.save();
      canvas.clipRect(canvasRect);
    }

    for (final element in getPatternElements(
      pattern: backgroundPattern,
      size: size,
      lineHeight: lineHeight,
      gridDensity: gridDensity,
    )) {
      if (element.secondaryColor) {
        paint.color = secondaryColor.withValues(alpha: preview ? 0.5 : 0.2);
      } else {
        paint.color = primaryColor.withValues(alpha: preview ? 0.5 : 0.2);
      }

      if (element.isLine) {
        canvas.drawLine(element.start, element.end, paint);
      } else {
        // 点跟着疏密一起缩，不然密了之后点会糊成一片
        canvas.drawCircle(
          element.start,
          paint.strokeWidth * 4 / 3 * gridDensity,
          paint,
        );
      }
    }

    if (backgroundPattern.requiresClipping) {
      canvas.restore();
    }

    if (texture == .paper) _paintPaperGrain(canvas);
  }

  /// 纸张质感：撒一层很淡的颗粒。
  ///
  /// 只画当前裁剪区域内的点 —— 无边画布有 6000×6000，整块画会卡死。
  void _paintPaperGrain(Canvas canvas) {
    final clip = canvas.getLocalClipBounds();
    if (clip.isEmpty) return;

    const step = 4.0;
    final points = <Offset>[];
    // 固定种子的伪随机：同一块区域每次画出来都一样，不会闪
    var seed = 0x9E3779B9;
    double next() {
      seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF;
      return (seed % 1000) / 1000;
    }

    for (double y = clip.top; y < clip.bottom; y += step) {
      for (double x = clip.left; x < clip.right; x += step) {
        final jx = next();
        final jy = next();
        if (next() > .5) continue;
        points.add(Offset(x + jx * step, y + jy * step));
      }
    }
    if (points.isEmpty) return;

    canvas.drawPoints(
      PointMode.points,
      points,
      Paint()
        ..color = (invert ? Colors.white : Colors.black).withValues(alpha: .05)
        ..strokeWidth = .8
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(CanvasBackgroundPainter oldDelegate) =>
      kDebugMode ||
      oldDelegate.invert != invert ||
      oldDelegate.backgroundColor != backgroundColor ||
      oldDelegate.backgroundPattern != backgroundPattern ||
      oldDelegate.texture != texture ||
      oldDelegate.lineHeight != lineHeight ||
      oldDelegate.gridDensity != gridDensity ||
      oldDelegate.primaryColor != primaryColor ||
      oldDelegate.secondaryColor != secondaryColor;

  static Iterable<PatternElement> getPatternElements({
    required CanvasBackgroundPattern pattern,
    required Size size,
    required int lineHeight,
    double gridDensity = 1.0,
  }) sync* {
    switch (pattern) {
      case .none:
        return;
      case .collegeLtr:
      case .collegeRtl:
      case .lined:
        // horizontal lines
        for (double y = lineHeight * 2; y < size.height; y += lineHeight) {
          yield PatternElement(
            Offset(0, y),
            Offset(size.width, y),
            isLine: true,
          );
        }

        // vertical line
        if (pattern == .collegeLtr) {
          yield PatternElement(
            Offset(lineHeight * 2, 0),
            Offset(lineHeight * 2, size.height),
            isLine: true,
            secondaryColor: true,
          );
        } else if (pattern == .collegeRtl) {
          yield PatternElement(
            Offset(size.width - lineHeight * 2, 0),
            Offset(size.width - lineHeight * 2, size.height),
            isLine: true,
            secondaryColor: true,
          );
        }
      case .grid:
        final step = lineHeight * gridDensity;
        for (double y = step * 2; y < size.height; y += step) {
          yield PatternElement(
            Offset(0, y),
            Offset(size.width, y),
            isLine: true,
          );
        }
        for (double x = 0; x < size.width; x += step) {
          yield PatternElement(
            Offset(x, step * 2),
            Offset(x, size.height),
            isLine: true,
          );
        }
      case .dots:
        final step = lineHeight * gridDensity;
        for (double y = step * 2; y <= size.height; y += step) {
          for (double x = 0; x <= size.width; x += step) {
            yield PatternElement(Offset(x, y), Offset(x, y), isLine: false);
          }
        }
      case .staffs:
      case .tablature:
        final staffSpaces = pattern == .staffs ? 4 : 5;
        final staffHeight = lineHeight * staffSpaces;
        final staffSpacing = lineHeight * 3;

        for (
          double topOfStaff = staffSpacing.toDouble() - lineHeight;
          topOfStaff + staffHeight < size.height;
          topOfStaff += staffHeight + staffSpacing
        ) {
          // horizontal lines
          for (int line = 0; line < staffSpaces + 1; line++) {
            yield PatternElement(
              Offset(lineHeight.toDouble(), topOfStaff + lineHeight * line),
              Offset(size.width - lineHeight, topOfStaff + lineHeight * line),
              isLine: true,
            );
          }

          // vertical lines on either side
          yield PatternElement(
            Offset(lineHeight.toDouble(), topOfStaff),
            Offset(lineHeight.toDouble(), topOfStaff + staffHeight),
            isLine: true,
          );
          yield PatternElement(
            Offset(size.width - lineHeight, topOfStaff),
            Offset(size.width - lineHeight, topOfStaff + staffHeight),
            isLine: true,
          );
        }
      case .cornell:
        // half-width line for name field
        yield PatternElement(
          Offset(lineHeight.toDouble(), lineHeight * 2),
          Offset(size.width / 2 - lineHeight / 2, lineHeight * 2),
          isLine: true,
        );
        // half-width line for date field
        yield PatternElement(
          Offset(size.width / 2 + lineHeight / 2, lineHeight * 2),
          Offset(size.width - lineHeight, lineHeight * 2),
          isLine: true,
        );
        // full-width line for title field
        yield PatternElement(
          Offset(lineHeight.toDouble(), lineHeight * 3),
          Offset(size.width - lineHeight, lineHeight * 3),
          isLine: true,
        );

        // lines for main notes
        final left = size.width * 0.35; // 35% width reserved for cues column
        final bottom = size.height * 0.7; // 30% height reserved for summary
        for (double y = lineHeight * 5; y < bottom; y += lineHeight) {
          yield PatternElement(
            Offset(left, y),
            Offset(size.width - lineHeight, y),
            isLine: true,
          );
        }
    }
  }
}

class PatternElement {
  final Offset start, end;

  /// Whether this is a line or a dot
  final bool isLine;

  /// Whether this should use a secondary color
  final bool secondaryColor;

  const new(
    this.start,
    this.end, {
    this.isLine = true,
    this.secondaryColor = false,
  });
}
