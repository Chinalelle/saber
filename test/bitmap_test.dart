import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saber/components/canvas/_asset_cache.dart';
import 'package:saber/data/editor/editor_bitmap.dart';
import 'package:saber/data/editor/page.dart';

/// 读某个**页面坐标**处的像素透明度（0 = 全透明）。
Future<int> _alphaAt(EditorBitmap bitmap, Size pageSize, Offset point) async {
  final data = await bitmap.image!.toByteData(
    format: ui.ImageByteFormat.rawRgba,
  );
  final bytes = data!.buffer.asUint8List();
  final x = (point.dx * bitmap.pixelWidth / pageSize.width)
      .round()
      .clamp(0, bitmap.pixelWidth - 1);
  final y = (point.dy * bitmap.pixelHeight / pageSize.height)
      .round()
      .clamp(0, bitmap.pixelHeight - 1);
  return bytes[(y * bitmap.pixelWidth + x) * 4 + 3];
}

/// 铺满整页的黑色。
void _fillBlack(Canvas canvas, Size size) => canvas.drawRect(
  Offset.zero & size,
  Paint()..color = const Color(0xFF000000),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('EditorBitmap 尺寸', () {
    test('普通页面按 2 倍分辨率建图', () {
      final bitmap = EditorBitmap.createFor(const Size(1000, 1400));
      expect(bitmap.pixelWidth, 2000);
      expect(bitmap.pixelHeight, 2800);
    });

    test('页面过大时自动降低倍率，不让内存炸掉', () {
      // 无边画布是 8000×8000，按 2 倍就是 256M 像素（1 GB 内存）
      final bitmap = EditorBitmap.createFor(const Size(8000, 8000));
      expect(
        bitmap.pixelWidth * bitmap.pixelHeight,
        lessThanOrEqualTo(6e6 * 1.01),
      );
      expect(bitmap.pixelWidth, lessThan(8000));
      expect(bitmap.pixelWidth, greaterThan(0));
    });

    test('倍率可以自定义，且结果始终为正', () {
      final bitmap = EditorBitmap.createFor(
        const Size(100, 100),
        idealRatio: 3,
      );
      expect(bitmap.pixelWidth, 300);

      // 极端参数下也不能建出 0 像素的图
      final tiny = EditorBitmap.createFor(const Size(1, 1), idealRatio: 0.01);
      expect(tiny.pixelWidth, greaterThanOrEqualTo(1));
    });
  });

  group('EditorBitmap 绘制', () {
    test('画一笔之后有内容，PNG 缓存也同步就绪', () async {
      const pageSize = Size(100, 100);
      final bitmap = EditorBitmap.createFor(pageSize);
      expect(bitmap.isEmpty, isTrue);
      expect(bitmap.isNotEmpty, isFalse);
      expect(bitmap.cachedPng, isNull);

      await bitmap.apply(
        pageSize: pageSize,
        draw: (canvas) => canvas.drawRect(
          const Rect.fromLTWH(0, 0, 50, 50),
          Paint()..color = const Color(0xFF000000),
        ),
      );

      expect(bitmap.isNotEmpty, isTrue);
      expect(bitmap.image, isNotNull);
      // 撤销栈要立刻拿到快照，所以 apply 结束前 PNG 必须已经编好
      expect(bitmap.cachedPng, isNotNull);
    });

    test('BlendMode.clear 能把已有像素真的挖掉（位图橡皮的关键）', () async {
      const pageSize = Size(100, 100);
      final bitmap = EditorBitmap.createFor(pageSize);

      await bitmap.apply(pageSize: pageSize, draw: (c) => _fillBlack(c, pageSize));
      expect(await _alphaAt(bitmap, pageSize, const Offset(50, 50)), 255);

      await bitmap.apply(
        pageSize: pageSize,
        draw: (canvas) => canvas.drawCircle(
          const Offset(50, 50),
          20,
          Paint()..blendMode = BlendMode.clear,
        ),
      );

      expect(
        await _alphaAt(bitmap, pageSize, const Offset(50, 50)),
        0,
        reason: '中间应该被挖空',
      );
      expect(
        await _alphaAt(bitmap, pageSize, const Offset(5, 5)),
        255,
        reason: '角落不该被误伤',
      );
    });

    test('多次绘制是叠加的，不会互相覆盖', () async {
      const pageSize = Size(100, 100);
      final bitmap = EditorBitmap.createFor(pageSize);

      await bitmap.apply(
        pageSize: pageSize,
        draw: (canvas) => canvas.drawRect(
          const Rect.fromLTWH(0, 0, 50, 100),
          Paint()..color = const Color(0xFF000000),
        ),
      );
      await bitmap.apply(
        pageSize: pageSize,
        draw: (canvas) => canvas.drawRect(
          const Rect.fromLTWH(50, 0, 50, 100),
          Paint()..color = const Color(0xFF000000),
        ),
      );

      expect(await _alphaAt(bitmap, pageSize, const Offset(25, 50)), 255);
      expect(await _alphaAt(bitmap, pageSize, const Offset(75, 50)), 255);
    });
  });

  group('EditorBitmap 快照', () {
    test('clone 拿到的是当时那一刻的画面，之后原图再改也不影响它', () async {
      const pageSize = Size(100, 100);
      final bitmap = EditorBitmap.createFor(pageSize);
      await bitmap.apply(pageSize: pageSize, draw: (c) => _fillBlack(c, pageSize));

      final snapshot = bitmap.clone();

      // 原图上挖个洞
      await bitmap.apply(
        pageSize: pageSize,
        draw: (canvas) => canvas.drawCircle(
          const Offset(50, 50),
          20,
          Paint()..blendMode = BlendMode.clear,
        ),
      );

      expect(await _alphaAt(bitmap, pageSize, const Offset(50, 50)), 0);
      expect(
        await _alphaAt(snapshot, pageSize, const Offset(50, 50)),
        255,
        reason: '快照必须是改动前的样子（撤销要靠它还原）',
      );
    });

    test('setFrom 能把位图恢复到快照的样子', () async {
      const pageSize = Size(100, 100);
      final bitmap = EditorBitmap.createFor(pageSize);
      await bitmap.apply(pageSize: pageSize, draw: (c) => _fillBlack(c, pageSize));
      final snapshot = bitmap.clone();

      await bitmap.apply(
        pageSize: pageSize,
        draw: (canvas) => canvas.drawCircle(
          const Offset(50, 50),
          20,
          Paint()..blendMode = BlendMode.clear,
        ),
      );
      expect(await _alphaAt(bitmap, pageSize, const Offset(50, 50)), 0);

      bitmap.setFrom(snapshot);
      expect(
        await _alphaAt(bitmap, pageSize, const Offset(50, 50)),
        255,
        reason: '恢复后洞应该被填回来',
      );
    });
  });

  group('EditorBitmap 序列化', () {
    test('PNG 往返：尺寸与内容都还在', () async {
      const pageSize = Size(60, 80);
      final bitmap = EditorBitmap.createFor(pageSize);
      await bitmap.apply(
        pageSize: pageSize,
        draw: (canvas) => canvas.drawRect(
          const Rect.fromLTWH(0, 0, 30, 40),
          Paint()..color = const Color(0xFFFF0000),
        ),
      );

      final png = await bitmap.ensurePng();
      expect(png, isNotNull);

      final restored = await EditorBitmap.fromPng(png!);
      expect(restored, isNotNull);
      expect(restored!.pixelWidth, bitmap.pixelWidth);
      expect(restored.pixelHeight, bitmap.pixelHeight);
      expect(await _alphaAt(restored, pageSize, const Offset(15, 20)), 255);
      expect(await _alphaAt(restored, pageSize, const Offset(55, 70)), 0);
    });

    test('字节坏掉时返回 null，而不是把异常抛给上层', () async {
      final broken = await EditorBitmap.fromPng(
        Uint8List.fromList([1, 2, 3, 4, 5]),
      );
      expect(broken, isNull);
    });

    test('空位图编不出 PNG', () async {
      final bitmap = EditorBitmap.createFor(const Size(10, 10));
      expect(await bitmap.toPng(), isNull);
    });
  });

  group('EditorPage 接线', () {
    test('toJson 把位图登记进资源缓存，字节取得回来', () async {
      final page = EditorPage(size: const Size(100, 140));
      final bitmap = EditorBitmap.createFor(page.size);
      await bitmap.apply(
        pageSize: page.size,
        draw: (canvas) => _fillBlack(canvas, page.size),
      );
      page.bitmap = bitmap;

      final assets = OrderedAssetCache();
      final json = page.toJson(assets);

      expect(json['bm'], isA<int>(), reason: '位图应该写成资源下标');
      final bytes = await assets.getBytes(json['bm'] as int);
      expect(bytes, isNotEmpty);
      // 存的确实是 PNG（前 8 个字节是 PNG 签名）
      expect(bytes.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
    });

    test('没有位图时不会写 bm 字段', () {
      final page = EditorPage(size: const Size(100, 140));
      final json = page.toJson(OrderedAssetCache());
      expect(json.containsKey('bm'), isFalse);
    });

    test('只有位图的页面算「非空」，不能被当成空白页删掉', () async {
      final page = EditorPage(size: const Size(100, 140));
      // 去掉构造函数自动补的那张空白页影响，直接看这一页
      expect(page.isEmpty, isTrue);

      final bitmap = EditorBitmap.createFor(page.size);
      await bitmap.apply(
        pageSize: page.size,
        draw: (canvas) => _fillBlack(canvas, page.size),
      );
      page.bitmap = bitmap;

      expect(page.isEmpty, isFalse);
    });
  });
}
