import 'package:flutter/foundation.dart';

/// 大纲里的一条：一个标题，加上它指向的页面。
///
/// 「大纲」是这一版新加的东西，用来给导入的 PDF 做目录：点击条目就跳到
/// 对应的那页（PDF 导入后是「一页 PDF = 一个 [EditorPage]」，所以这里存的是
/// `coreInfo.pages` 的下标，而不是 PDF 自己的页码）。
@immutable
class OutlineEntry {
  const new({
    required this.title,
    required this.pageIndex,
    this.level = 1,
    this.source = OutlineSource.ai,
  });

  /// 标题原文（模型不做翻译、不改写）。
  final String title;

  /// 指向 `EditorCoreInfo.pages` 的下标。
  final int pageIndex;

  /// 层级，从 1 开始（1 是最高级）。模型自己判断。
  final int level;

  /// 这条是怎么来的：PDF 自带书签，还是大模型看图认出来的。
  final OutlineSource source;

  /// 在 `coreInfo.pages` 里找到这一条指向的页；找不到返回 null。
  ///
  /// 页数会变（用户插页、删页、重新导入 PDF），所以渲染和跳转之前都要先过一遍这个。
  OutlineEntry? clampToPageCount(int pageCount) {
    if (pageIndex >= 0 && pageIndex < pageCount) return this;
    // 越界就夹到最后一页，总比点了没反应强
    if (pageCount <= 0) return null;
    return OutlineEntry(
      title: title,
      pageIndex: pageCount - 1,
      level: level,
      source: source,
    );
  }

  Map<String, dynamic> toJson() => {
    't': title,
    'p': pageIndex,
    'l': level,
    's': source.name,
  };

  factory fromJson(Map<String, dynamic> json) => OutlineEntry(
    title: json['t'] as String? ?? '',
    pageIndex: (json['p'] as num?)?.toInt() ?? 0,
    level: (json['l'] as num?)?.toInt() ?? 1,
    source: OutlineSource.fromName(json['s'] as String?),
  );

  OutlineEntry copyWith({String? title, int? pageIndex, int? level, OutlineSource? source}) =>
      OutlineEntry(
        title: title ?? this.title,
        pageIndex: pageIndex ?? this.pageIndex,
        level: level ?? this.level,
        source: source ?? this.source,
      );

  @override
  bool operator ==(Object other) =>
      other is OutlineEntry &&
      other.title == title &&
      other.pageIndex == pageIndex &&
      other.level == level &&
      other.source == source;

  @override
  int get hashCode => Object.hash(title, pageIndex, level, source);

  @override
  String toString() => 'OutlineEntry($level, $title -> page $pageIndex, $source)';
}

/// 大纲条目的来源。
enum OutlineSource {
  /// PDF 文件里自带的书签（`PdfDocument.loadOutline`）。
  ///
  /// 有的话优先用它：不要钱、页码还绝对准。
  pdfBookmark,

  /// 大模型逐页看图认出来的章节标题。
  ai;

  static OutlineSource fromName(String? name) => switch (name) {
    'pdfBookmark' => OutlineSource.pdfBookmark,
    _ => OutlineSource.ai,
  };
}
