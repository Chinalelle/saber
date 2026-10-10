import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// 一页上的「位图图层」——以像素为单位累积的绘制结果。
///
/// 矢量笔迹存的是笔画的路径：想擦掉半条线，只能把笔画拆成两段；
/// 想做出喷枪、叠加混色这类效果也无从下手。这一层存的直接是**像素**，
/// 画上去就固化成像素，擦除就是真的把像素抹掉（可以只擦掉半条线）。
///
/// 两套坐标是统一的：对外一律用页面逻辑坐标，位图只是内部多一个分辨率倍率。
/// 这样画笔、橡皮、选择等上层逻辑都不用关心位图有多大。
class EditorBitmap {
  new({required this.pixelWidth, required this.pixelHeight})
    : assert(pixelWidth > 0, '位图宽度必须为正'),
      assert(pixelHeight > 0, '位图高度必须为正');

  /// 位图的实际像素尺寸。
  final int pixelWidth;
  final int pixelHeight;

  /// 位图内容。null 表示这一层还没画过东西（全透明）。
  ui.Image? _image;
  ui.Image? get image => _image;

  /// 编码好的 PNG 字节。
  ///
  /// `toJson` 是同步的，而 ui.Image 编码成 PNG 是异步的，所以这里缓存一份：
  /// 每次绘制后异步刷新，保存时用 [ensurePng] 等一下即可。
  Uint8List? _png;
  var _pngDirty = true;

  /// 最近一次编码好的 PNG（可能落后于画面，保存前请用 [ensurePng]）。
  Uint8List? get cachedPng => _png;

  /// 确保 PNG 缓存是最新的，返回它。
  Future<Uint8List?> ensurePng() async {
    if (_pngDirty) {
      _png = await toPng();
      _pngDirty = false;
    }
    return _png;
  }

  bool get isEmpty => _image == null;
  bool get isNotEmpty => _image != null;

  /// 估算内存占用（RGBA，每像素 4 字节）。
  int get byteSize => pixelWidth * pixelHeight * 4;

  Size get pixelSize => Size(pixelWidth.toDouble(), pixelHeight.toDouble());

  /// 位图分辨率相对页面逻辑尺寸的倍率。
  double scaleForSize(Size pageSize) =>
      pageSize.width <= 0 ? 1 : pixelWidth / pageSize.width;

  /// 按页面尺寸新建一张空位图。
  ///
  /// [idealRatio] 是理想倍率（2 倍 = 放大到 200% 以内仍然清晰）。
  /// 页面很大时（无边画布可以到 8000×8000）会按 [maxPixels] 反推一个更小的
  /// 倍率 —— 8000² 按 2 倍就是 256M 像素、1 GB 内存，一张图就能把应用拖死。
  /// 宁可这一层糊一点，也不能让笔记打不开。
  factory createFor(
    Size pageSize, {
    double idealRatio = 2,
    double maxPixels = 6e6,
  }) {
    final area = max(pageSize.width * pageSize.height, 1);
    // 上限优先：先算出 maxPixels 允许的最大倍率，再和理想倍率取小的那个。
    // 注意别用 clamp 加下界 —— 那会把上限又顶回去（曾经就是这么写错的）。
    final ratio = min(
      min(idealRatio, 4.0),
      sqrt(maxPixels / area),
    );
    return EditorBitmap(
      pixelWidth: max(1, (pageSize.width * ratio).round()),
      pixelHeight: max(1, (pageSize.height * ratio).round()),
    );
  }

  /// 在位图层上叠加一次绘制。
  ///
  /// [draw] 拿到的是**页面逻辑坐标**下的 canvas，位图分辨率由内部换算，
  /// 所以调用方可以直接用笔迹自己的坐标系去画。
  ///
  /// 橡皮擦只要在 [draw] 里用 `Paint()..blendMode = BlendMode.clear` 即可。
  Future<void> apply({
    required Size pageSize,
    required void Function(Canvas canvas) draw,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.scale(
      pixelWidth / pageSize.width,
      pixelHeight / pageSize.height,
    );

    // saveLayer：让橡皮的 BlendMode.clear 只清这一层的内容。
    // 少了它，clear 会把整个 layers 都抹掉（包括下面画好的位图）。
    canvas.saveLayer(
      Rect.fromLTWH(0, 0, pageSize.width, pageSize.height),
      Paint(),
    );
    final old = _image;
    if (old != null) canvas.drawImage(old, Offset.zero, Paint());
    draw(canvas);
    canvas.restore();

    final picture = recorder.endRecording();
    final next = await picture.toImage(pixelWidth, pixelHeight);
    picture.dispose();

    _image?.dispose();
    _image = next;

    // 画面变了，PNG 缓存作废，立刻重新编码一份。
    //
    // 为什么要 await：撤销栈存的是 PNG 字节（比整张 ui.Image 省内存得多），
    // 记录历史时需要一个**已经编码好**的快照，不能等它后台慢慢编。
    // 位图尺寸被 createFor 限制过，编码通常几十毫秒，抬笔时感知不到。
    _png = null;
    _pngDirty = true;
    await ensurePng();
  }

  /// 位图快照，撤销/重做用。
  ///
  /// [ui.Image.clone] 共享底层像素、不复制内存；又因为 [apply] 每次都生成
  /// **新的** image（而不是原地修改），快照不会被后续绘制污染。
  EditorBitmap clone() {
    final copy = EditorBitmap(
      pixelWidth: pixelWidth,
      pixelHeight: pixelHeight,
    );
    copy._image = _image?.clone();
    copy._png = _png;
    copy._pngDirty = _pngDirty;
    return copy;
  }

  /// 直接换成另一张 image（撤销/重做时用）。
  ///
  /// [image] 的所有权转移给本对象，调用方不要再 dispose 它。
  void setImage(ui.Image? image) {
    if (identical(_image, image)) return;
    _image?.dispose();
    _image = image;
    _png = null;
    _pngDirty = true;
    if (image != null) unawaited(ensurePng());
  }

  /// 用另一个位图的内容覆盖自己（撤销/重做时用）。
  void setFrom(EditorBitmap? other) {
    setImage(other?.image?.clone());
  }

  /// 编码成 PNG 字节，存进 .sbn 文件用。
  Future<Uint8List?> toPng() async {
    final image = _image;
    if (image == null) return null;
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List();
  }

  /// 从 PNG 字节恢复。
  static Future<EditorBitmap?> fromPng(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      codec.dispose();
      final image = frame.image;
      return EditorBitmap(
        pixelWidth: image.width,
        pixelHeight: image.height,
      )
        .._image = image
        // 本来就是 PNG 字节解出来的，直接当缓存用，省一次编码
        .._png = bytes
        .._pngDirty = false;
    } catch (_) {
      // 位图读不出来不该让整篇笔记打不开 —— 上层按「这一层是空的」处理
      return null;
    }
  }

  void dispose() {
    _image?.dispose();
    _image = null;
    _png = null;
    _pngDirty = true;
  }

  @override
  String toString() =>
      'EditorBitmap(${pixelWidth}x$pixelHeight, '
      '${isEmpty ? '空' : '有内容'})';
}
