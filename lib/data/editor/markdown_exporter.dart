import 'package:saber/data/editor/editor_core_info.dart';

/// Converts a Saber note into a Markdown document.
///
/// A Saber page holds three kinds of content, and not all of them survive the
/// trip to Markdown:
///
/// - [EditorPage.quill]: rich text (Quill deltas). Converts cleanly.
/// - [EditorPage.strokes]: handwriting. Pure vector data with no textual
///   representation, so it is reported as an HTML comment instead of being
///   silently dropped — the reader should know the page is not fully captured.
/// - [EditorPage.images] / [EditorPage.backgroundImage]: raster images. Only
///   placeholders can be emitted, because a note's images live inside its
///   `.sbn2` container rather than as separate files.
abstract class MarkdownExporter {
  /// Renders [coreInfo] as a Markdown document.
  ///
  /// Pass [exportedAt] to make the output deterministic in tests.
  static String generateMarkdown(
    EditorCoreInfo coreInfo, {
    DateTime? exportedAt,
  }) {
    final now = exportedAt ?? DateTime.now();
    final out = StringBuffer();

    out.writeln('# ${_escapeInline(coreInfo.fileName)}');
    out.writeln();
    out.writeln(
      '> Saber 导出 · ${now.year}-${_two(now.month)}-${_two(now.day)}'
      ' ${_two(now.hour)}:${_two(now.minute)}'
      ' · 共 ${coreInfo.pages.length} 页',
    );
    out.writeln();

    var wroteAnyText = false;
    final pageCount = coreInfo.pages.length;

    for (var i = 0; i < pageCount; i++) {
      final page = coreInfo.pages[i];
      final body = deltaToMarkdown(
        page.quill.controller.document.toDelta().toJson(),
      ).trimRight();

      final strokeCount = page.strokes.length;
      final imageCount = page.images.length + (page.backgroundImage != null ? 1 : 0);
      final hasGraphics = strokeCount > 0 || imageCount > 0;

      if (pageCount > 1) {
        out.writeln('## 第 ${i + 1} 页');
        out.writeln();
      }

      if (body.isNotEmpty) {
        out.writeln(body);
        out.writeln();
        wroteAnyText = true;
      }

      if (hasGraphics) {
        final parts = <String>[
          if (strokeCount > 0) '$strokeCount 处手写笔迹',
          if (imageCount > 0) '$imageCount 张图片',
        ];
        out.writeln('<!-- 本页另有 ${parts.join('、')}，无法转为文字 -->');
        out.writeln();
      } else if (body.isEmpty) {
        out.writeln('<!-- 本页为空 -->');
        out.writeln();
      }
    }

    if (!wroteAnyText) {
      out.writeln('> ⚠️ 这篇笔记没有可提取的文字内容：全部内容都是手写笔迹或图片。');
      out.writeln('> 若要检索这类笔记，需要先做手写识别（OCR）。');
      out.writeln();
    }

    return out.toString();
  }

  /// Converts a Quill delta (`List` of ops) into Markdown.
  ///
  /// Quill's model maps onto Markdown almost one-to-one, with one wrinkle:
  /// inline attributes (`bold`, `link`, …) live on the text op, while
  /// line-level attributes (`header`, `list`, …) live on the newline op that
  /// terminates the line. So text is accumulated into runs and only committed
  /// when a newline arrives, at which point both attribute sets are known.
  static String deltaToMarkdown(List<dynamic> ops) {
    final out = StringBuffer();
    var runs = <_Run>[];
    Map<String, dynamic>? lineAttrs;
    var inCodeBlock = false;

    void endLine() {
      final attrs = lineAttrs ?? const <String, dynamic>{};
      final text = runs.map((r) => r.text).join();
      final isCodeBlock = attrs['code-block'] == true;

      // Open or close a fenced block at the boundary, never per line.
      if (isCodeBlock != inCodeBlock) {
        out.writeln('```');
        inCodeBlock = isCodeBlock;
      }

      if (isCodeBlock) {
        out.writeln(text);
      } else if (text.trim().isEmpty && attrs.isEmpty) {
        out.writeln();
      } else {
        out.writeln(_renderLine(runs, attrs));
      }

      runs = <_Run>[];
      lineAttrs = null;
    }

    for (final raw in ops) {
      if (raw is! Map) continue;
      final insert = raw['insert'];
      final attrs = (raw['attributes'] as Map?)?.cast<String, dynamic>();

      if (insert is String) {
        final lines = insert.split('\n');
        for (var i = 0; i < lines.length; i++) {
          if (lines[i].isNotEmpty) runs.add(_Run(lines[i], attrs));
          if (i != lines.length - 1) {
            lineAttrs = attrs;
            endLine();
          }
        }
      } else if (insert is Map) {
        // Embedded object: images are base64 inside the note, so only a
        // placeholder can be emitted.
        if (insert['image'] != null) {
          runs.add(const _Run('![图片](saber-embedded-image)', null));
        } else {
          runs.add(const _Run('<!-- 嵌入内容 -->', null));
        }
      }
    }

    if (runs.isNotEmpty) endLine();
    if (inCodeBlock) out.writeln('```');

    return out.toString();
  }

  static String _renderLine(List<_Run> runs, Map<String, dynamic> attrs) {
    var prefix = '';

    final header = attrs['header'];
    final list = attrs['list'];

    if (header is int && header >= 1 && header <= 6) {
      prefix = '${'#' * header} ';
    } else if (attrs['blockquote'] == true) {
      prefix = '> ';
    } else if (list == 'ordered') {
      prefix = '1. ';
    } else if (list == 'bullet') {
      prefix = '- ';
    } else if (list == 'checked') {
      prefix = '- [x] ';
    } else if (list == 'unchecked') {
      prefix = '- [ ] ';
    }

    final indent = attrs['indent'];
    if (indent is int && indent > 0 && prefix.isNotEmpty) {
      prefix = '${'  ' * indent}$prefix';
    }

    return '$prefix${runs.map(_renderRun).join()}';
  }

  static String _renderRun(_Run run) {
    var text = run.text;
    if (text.isEmpty) return text;

    final attrs = run.attrs;
    if (attrs == null || attrs.isEmpty) return text;

    if (attrs['code'] == true) return '`$text`';

    if (attrs['bold'] == true) text = '**$text**';
    if (attrs['italic'] == true) text = '*$text*';
    if (attrs['strike'] == true) text = '~~$text~~';
    if (attrs['underline'] == true) text = '<u>$text</u>';

    final link = attrs['link'];
    if (link is String) text = '[$text]($link)';

    return text;
  }

  static String _escapeInline(String s) =>
      s.replaceAllMapped(RegExp(r'[\\`*_\[\]#]'), (m) => '\\${m[0]}');

  static String _two(int n) => n.toString().padLeft(2, '0');
}

class _Run {
  const new(this.text, this.attrs);

  final String text;
  final Map<String, dynamic>? attrs;
}
