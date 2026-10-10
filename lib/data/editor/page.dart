import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' show FragmentShader;

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:saber/components/canvas/_asset_cache.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/components/canvas/image/editor_image.dart';
import 'package:saber/components/canvas/inner_canvas.dart';
import 'package:saber/components/canvas/pencil_shader.dart';
import 'package:saber/data/editor/editor_exporter.dart';
import 'package:saber/data/tools/laser_pointer.dart';
import 'package:sbn/has_size.dart';

typedef CanvasKey = GlobalKey<State<InnerCanvas>>;

class EditorPage extends ChangeNotifier implements HasSize {
  static const double defaultWidth = 1000;
  static const double defaultHeight = defaultWidth * 1.4;
  static const defaultSize = Size(defaultWidth, defaultHeight);

  /// 「无边画布」用的那一整块大画布。
  ///
  /// 这里给的是**起始**大小，不是上限：拖到边上时 `growTo` 会把它接出去
  /// （见 `CanvasGestureDetector._growInfiniteCanvasIfNeeded`），
  /// 所以用户实际感受不到这块纸有边。坐标系和序列化都不用动。
  static const infiniteSize = Size(8000, 8000);

  /// 把画布长大到至少 [newSize]（只增不减），并通知重绘。
  ///
  /// 坐标系原点不动，所以已有笔迹/图片/文本框的坐标都不受影响，
  /// 只是"纸"往右下方又接了一大块。
  void growTo(Size newSize) {
    if (newSize.width <= size.width && newSize.height <= size.height) return;
    size = Size(
      max(size.width, newSize.width),
      max(size.height, newSize.height),
    );
    notifyListeners();
  }

  /// 页面尺寸。文档页是 1000×1400，**无边画布是 6000×6000**。
  ///
  /// 故意不做成 final：从旧笔记/普通笔记升成无边画布时要把尺寸顶上去，
  /// 否则画布只比一个屏幕宽一点点，横向几乎没有平移余量
  /// （表现就是"只能上下拖、不能左右拖"）。
  @override
  Size size;

  late final CanvasKey innerCanvasKey = CanvasKey();
  RenderBox? _renderBox;
  RenderBox? get renderBox {
    return _renderBox ??=
        innerCanvasKey.currentState?.context.findRenderObject() as RenderBox?;
  }

  var _isRendered = false;
  bool get isRendered => _isRendered;
  set isRendered(bool isRendered) {
    if (isRendered == _isRendered) return;
    _isRendered = isRendered;

    // reset renderBox as renderObject has changed
    _renderBox = null;
  }

  FragmentShader get pencilShader => _pencilShader ??= PencilShader.create();
  FragmentShader? _pencilShader;

  final List<Stroke> strokes;
  final List<LaserStroke> laserStrokes;
  final List<EditorImage> images;
  final QuillStruct quill;

  /// 页面上的浮动文本框。「无边画布」主要靠它写字：
  /// 想在哪写就在哪放一个框，而不是整页铺一层文本。
  final List<EditorTextBox> textBoxes;

  EditorImage? backgroundImage;

  bool get isEmpty =>
      strokes.isEmpty &&
      images.isEmpty &&
      textBoxes.every((box) => box.isEmpty) &&
      quill.controller.document.isEmpty() &&
      backgroundImage == null;
  bool get isNotEmpty => !isEmpty;

  /// The height of the canvas cropped to the content.
  double previewHeight({required int lineHeight}) {
    // avoid dividing by zero (this should never happen)
    assert(size.height != 0);
    assert(size.width != 0);
    if (size.height == 0 || size.width == 0) {
      return 0;
    }

    // if we have a background image, show full height
    if (backgroundImage != null) {
      return size.height;
    }

    /// The maximum y value of any stroke, image, or text.
    double maxY = 0;
    for (final stroke in strokes) {
      maxY = max(maxY, stroke.maxY);
    }
    for (final image in images) {
      maxY = max(maxY, image.dstRect.bottom);
    }
    if (!quill.controller.document.isEmpty()) {
      // this does not account for text that wraps to the next line
      final int linesOfText = quill.controller.document
          .toPlainText()
          .split('\n')
          .length;
      maxY = max(maxY, linesOfText * lineHeight * 1.5); // ×1.5 fudge factor
    }

    /// The uncropped height of the page.
    /// In lots of cases, this is [Editor.defaultHeight].
    final fullHeight = size.height;

    /// The height of the canvas (cropped),
    /// adjusted to be between 10% and 100% of the full height.
    final croppedHeight = min(fullHeight, max(maxY, 0) + (0.1 * fullHeight));

    return croppedHeight;
  }

  new({
    Size? size,
    double? width,
    double? height,
    List<Stroke>? strokes,
    List<EditorImage>? images,
    List<EditorTextBox>? textBoxes,
    QuillStruct? quill,
    this.backgroundImage,
  }) : assert(
         (size == null) || (width == null && height == null),
         "size and width/height shouldn't both be specified",
       ),
       size = size ?? Size(width ?? defaultWidth, height ?? defaultHeight),
       strokes = strokes ?? [],
       laserStrokes = [],
       images = images ?? [],
       textBoxes = textBoxes ?? [],
       quill =
           quill ??
           QuillStruct(
             controller: QuillController.basic(),
             focusNode: FocusNode(debugLabel: 'Quill Focus Node'),
           );

  factory fromJson(
    Map<String, dynamic> json, {
    required List<Uint8List>? inlineAssets,
    required bool readOnly,
    required int fileVersion,
    required String sbnPath,
    required AssetCache assetCache,
  }) {
    final size = Size(json['w'] ?? defaultWidth, json['h'] ?? defaultHeight);
    return EditorPage(
      size: size,
      strokes: parseStrokesJson(
        json['s'] as List?,
        page: HasSize(size),
        onlyFirstPage: false,
        fileVersion: fileVersion,
      ),
      images: parseImagesJson(
        json['i'] as List?,
        inlineAssets: inlineAssets,
        isThumbnail: readOnly,
        onlyFirstPage: false,
        sbnPath: sbnPath,
        assetCache: assetCache,
      ),
      quill: QuillStruct(
        controller: json['q'] != null
            ? QuillController(
                document: Document.fromJson(json['q'] as List),
                selection: const TextSelection.collapsed(offset: 0),
              )
            : QuillController.basic(),
        focusNode: FocusNode(debugLabel: 'Quill Focus Node'),
      ),
      textBoxes: [
        for (final box in (json['tb'] as List? ?? const []))
          if (box is Map)
            EditorTextBox.fromJson(box.cast<String, dynamic>()),
      ],
      backgroundImage: json['b'] != null
          ? parseImageJson(
              json['b'],
              inlineAssets: inlineAssets,
              isThumbnail: false,
              sbnPath: sbnPath,
              assetCache: assetCache,
            )
          : null,
    );
  }

  Map<String, dynamic> toJson(OrderedAssetCache assets) => {
    'w': size.width,
    'h': size.height,
    if (strokes.isNotEmpty)
      's': strokes.map((stroke) => stroke.toJson()).toList(),
    if (images.isNotEmpty)
      'i': images.map((image) => image.toJson(assets)).toList(),
    if (textBoxes.isNotEmpty)
      'tb': textBoxes.map((box) => box.toJson()).toList(),
    if (!quill.controller.document.isEmpty())
      'q': quill.controller.document.toDelta().toJson(),
    if (backgroundImage != null) 'b': backgroundImage?.toJson(assets),
  };

  /// Inserts a stroke, while keeping the strokes sorted by
  /// pen type and color.
  void insertStroke(Stroke newStroke) {
    final int newStrokeColor = newStroke.color.toARGB32();

    int index = 0;
    for (final stroke in strokes) {
      final penTypeComparison = stroke.toolId.id.compareTo(newStroke.toolId.id);
      final color = stroke.color.toARGB32();
      if (penTypeComparison > 0) {
        break; // this stroke's pen type comes after the new stroke's pen type
      } else if (stroke.toolId == .highlighter &&
          penTypeComparison == 0 &&
          color > newStrokeColor) {
        break; // this highlighter color comes after the new highlighter color
      }
      index++;
    }

    strokes.insert(index, newStroke);
  }

  /// Sorts the strokes by pen type and color.
  void sortStrokes() {
    strokes.sort((Stroke a, Stroke b) {
      final penTypeComparison = a.toolId.id.compareTo(b.toolId.id);
      if (penTypeComparison != 0) return penTypeComparison;
      if (a.toolId != .highlighter) return 0;
      return a.color.toARGB32().compareTo(b.color.toARGB32());
    });
  }

  static List<Stroke> parseStrokesJson(
    List<dynamic>? strokes, {
    required HasSize page,
    required bool onlyFirstPage,
    required int fileVersion,
  }) => (strokes ?? [])
      .map((dynamic stroke) {
        final map = stroke as Map<String, dynamic>;
        final pageIndex = map['i'] ?? 0;
        if (onlyFirstPage && pageIndex > 0) return null;
        return Stroke.fromJson(
          map,
          fileVersion: fileVersion,
          pageIndex: pageIndex,
          page: page,
        );
      })
      .where((element) => element != null)
      .cast<Stroke>()
      .toList();

  static List<EditorImage> parseImagesJson(
    List<dynamic>? images, {
    required List<Uint8List>? inlineAssets,
    required bool isThumbnail,
    required bool onlyFirstPage,
    required String sbnPath,
    required AssetCache assetCache,
  }) =>
      images
          ?.cast<Map<String, dynamic>>()
          .map((Map<String, dynamic> image) {
            if (onlyFirstPage && image['i'] > 0) return null;
            return parseImageJson(
              image,
              inlineAssets: inlineAssets,
              isThumbnail: isThumbnail,
              sbnPath: sbnPath,
              assetCache: assetCache,
            );
          })
          .where((element) => element != null)
          .cast<EditorImage>()
          .toList() ??
      [];

  static EditorImage parseImageJson(
    Map<String, dynamic> json, {
    required List<Uint8List>? inlineAssets,
    required bool isThumbnail,
    required String sbnPath,
    required AssetCache assetCache,
  }) => EditorImage.fromJson(
    json,
    inlineAssets: inlineAssets,
    isThumbnail: isThumbnail,
    sbnPath: sbnPath,
    assetCache: assetCache,
  );

  /// Triggers a redraw of the strokes. If you need to redraw images,
  /// call [setState] instead.
  void redrawStrokes() {
    notifyListeners();
  }

  /// Updates the `pageIndex` fields of this page's strokes/images.
  void updatePageIndex(int pageIndex) {
    for (final stroke in strokes) stroke.pageIndex = pageIndex;
    for (final stroke in laserStrokes) stroke.pageIndex = pageIndex;
    for (final image in images) image.pageIndex = pageIndex;
    backgroundImage?.pageIndex = pageIndex;
  }

  @override
  void dispose() {
    quill.dispose();
    for (final box in textBoxes) {
      box.dispose();
    }
    _pencilShader?.dispose();
    isRendered = false;
    for (final image in images) {
      image.dispose();
    }
    backgroundImage?.dispose();
    super.dispose();
  }

  /// [cloneForRasterization] creates some new resources that need to be
  /// disposed, but it also contains some resources from the original page
  /// that should not be disposed since they are still in use.
  ///
  /// Call this method instead of [dispose] to dispose only the resources
  /// exclusive to the cloned page.
  void disposeClonedData() {
    quill.dispose();
    for (final box in textBoxes) {
      box.dispose();
    }
    _pencilShader?.dispose();
    isRendered = false;
    super.dispose();
  }

  EditorPage copyWith({
    Size? size,
    List<Stroke>? strokes,
    List<EditorImage>? images,
    List<EditorTextBox>? textBoxes,
    QuillStruct? quill,
    EditorImage? backgroundImage,
  }) => EditorPage(
    size: size ?? this.size,
    strokes: strokes ?? this.strokes,
    images: images ?? this.images,
    textBoxes: textBoxes ?? this.textBoxes,
    quill: quill ?? this.quill,
    backgroundImage: backgroundImage ?? this.backgroundImage,
  );

  /// Clones this page for use in a screenshot.
  ///
  /// Avoids bugs caused by the quill editor being attached to multiple
  /// contexts, and filters out strokes that shouldn't be rasterized.
  ///
  /// Make sure to call [disposeClonedData] on the returned page when
  /// you're done with it.
  EditorPage cloneForRasterization({bool rasterizeAllStrokes = false}) {
    return copyWith(
      strokes: rasterizeAllStrokes
          ? strokes
          : strokes.where(EditorExporter.shouldRasterizeStroke).toList(),
      textBoxes: [for (final box in textBoxes) box.clone()],
      quill: quill.cloneForScreenshot(),
    );
  }
}

class QuillStruct {
  final QuillController controller;
  late final FocusNode focusNode;
  StreamSubscription? changeSubscription;

  new({required this.controller, required this.focusNode});

  void dispose() {
    changeSubscription?.cancel();
    focusNode.dispose();
    controller.dispose();
  }

  QuillStruct cloneForScreenshot() => QuillStruct(
    controller: QuillController(
      document: Document.fromDelta(controller.document.toDelta()),
      selection: const TextSelection.collapsed(offset: 0),
    ),
    focusNode: FocusNode(debugLabel: 'Screenshot Quill Focus Node'),
  );
}

/// 一个浮动文本框：页面上的一块固定位置和大小的富文本。
///
/// 位置和尺寸都用页面的逻辑坐标（跟笔迹、图片一致），数据存在
/// [EditorPage.textBoxes] 里。这是「无边画布」里书写文字的方式 ——
/// 想在哪写就在哪放一个框，而不是整页铺一层文本。
class EditorTextBox {
  new({
    required this.id,
    required this.position,
    required this.size,
    QuillController? controller,
  }) : quill = QuillStruct(
         controller: controller ?? QuillController.basic(),
         focusNode: FocusNode(debugLabel: 'Text box #$id focus node'),
       );

  /// 同一页内唯一，方便撤销/重做时认人。
  final int id;

  /// 页面坐标下的左上角。
  Offset position;

  /// 文本框大小。
  Size size;

  final QuillStruct quill;

  /// 新建时给的默认尺寸。
  static const defaultSize = Size(360, 160);

  bool get isEmpty => quill.controller.document.isEmpty();

  void dispose() => quill.dispose();

  Map<String, dynamic> toJson() => {
    'i': id,
    'x': position.dx,
    'y': position.dy,
    'w': size.width,
    'h': size.height,
    'q': quill.controller.document.toDelta().toJson(),
  };

  factory fromJson(Map<String, dynamic> json) {
    final delta = json['q'];
    return EditorTextBox(
      id: (json['i'] as num?)?.toInt() ?? 0,
      position: Offset(
        (json['x'] as num?)?.toDouble() ?? 0,
        (json['y'] as num?)?.toDouble() ?? 0,
      ),
      size: Size(
        (json['w'] as num?)?.toDouble() ?? defaultSize.width,
        (json['h'] as num?)?.toDouble() ?? defaultSize.height,
      ),
      controller: delta is List
          ? QuillController(
              document: Document.fromJson(delta),
              selection: const TextSelection.collapsed(offset: 0),
            )
          : null,
    );
  }

  /// 复制一份（内容一样，但 Quill 控制器是独立的）。
  EditorTextBox clone() => EditorTextBox(
    id: id,
    position: position,
    size: size,
    controller: QuillController(
      document: Document.fromJson(quill.controller.document.toDelta().toJson()),
      selection: const TextSelection.collapsed(offset: 0),
    ),
  );
}
