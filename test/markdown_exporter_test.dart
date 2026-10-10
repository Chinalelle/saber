import 'package:flutter_test/flutter_test.dart';
import 'package:saber/data/editor/markdown_exporter.dart';

/// `deltaToMarkdown` is the load-bearing part of Markdown export: it turns
/// Quill deltas into Markdown. It is a pure function, so it can be pinned down
/// here instead of by exporting notes by hand on a device.
void main() {
  group('MarkdownExporter.deltaToMarkdown', () {
    test('plain paragraph', () {
      expect(
        MarkdownExporter.deltaToMarkdown([
          {'insert': '你好世界\n'},
        ]),
        '你好世界\n',
      );
    });

    test('blank line separates paragraphs', () {
      expect(
        MarkdownExporter.deltaToMarkdown([
          {'insert': '第一段\n\n第二段\n'},
        ]),
        '第一段\n\n第二段\n',
      );
    });

    test('headers use the newline op attributes', () {
      expect(
        MarkdownExporter.deltaToMarkdown([
          {'insert': '标题'},
          {'insert': '\n', 'attributes': {'header': 2}},
          {'insert': '正文\n'},
        ]),
        '## 标题\n正文\n',
      );
    });

    test('bold and italic are inlined', () {
      expect(
        MarkdownExporter.deltaToMarkdown([
          {'insert': '普通 '},
          {'insert': '粗', 'attributes': {'bold': true}},
          {'insert': ' 与 '},
          {'insert': '斜', 'attributes': {'italic': true}},
          {'insert': '\n'},
        ]),
        '普通 **粗** 与 *斜*\n',
      );
    });

    test('bullet list', () {
      expect(
        MarkdownExporter.deltaToMarkdown([
          {'insert': '苹果'},
          {'insert': '\n', 'attributes': {'list': 'bullet'}},
          {'insert': '香蕉'},
          {'insert': '\n', 'attributes': {'list': 'bullet'}},
        ]),
        '- 苹果\n- 香蕉\n',
      );
    });

    test('ordered list', () {
      expect(
        MarkdownExporter.deltaToMarkdown([
          {'insert': '一'},
          {'insert': '\n', 'attributes': {'list': 'ordered'}},
        ]),
        '1. 一\n',
      );
    });

    test('checkboxes', () {
      expect(
        MarkdownExporter.deltaToMarkdown([
          {'insert': '背完了'},
          {'insert': '\n', 'attributes': {'list': 'checked'}},
          {'insert': '没背完'},
          {'insert': '\n', 'attributes': {'list': 'unchecked'}},
        ]),
        '- [x] 背完了\n- [ ] 没背完\n',
      );
    });

    test('code block opens and closes exactly once', () {
      expect(
        MarkdownExporter.deltaToMarkdown([
          {'insert': 'line1'},
          {'insert': '\n', 'attributes': {'code-block': true}},
          {'insert': 'line2'},
          {'insert': '\n', 'attributes': {'code-block': true}},
        ]),
        '```\nline1\nline2\n```\n',
      );
    });

    test('blockquote', () {
      expect(
        MarkdownExporter.deltaToMarkdown([
          {'insert': '引用'},
          {'insert': '\n', 'attributes': {'blockquote': true}},
        ]),
        '> 引用\n',
      );
    });

    test('link', () {
      expect(
        MarkdownExporter.deltaToMarkdown([
          {'insert': '点这里', 'attributes': {'link': 'https://example.com'}},
          {'insert': '\n'},
        ]),
        '[点这里](https://example.com)\n',
      );
    });

    test('inline code', () {
      expect(
        MarkdownExporter.deltaToMarkdown([
          {'insert': 'print()', 'attributes': {'code': true}},
          {'insert': '\n'},
        ]),
        '`print()`\n',
      );
    });

    test('indented bullet', () {
      expect(
        MarkdownExporter.deltaToMarkdown([
          {'insert': '子项'},
          {
            'insert': '\n',
            'attributes': {'list': 'bullet', 'indent': 1},
          },
        ]),
        '  - 子项\n',
      );
    });

    test('embedded image becomes a placeholder', () {
      expect(
        MarkdownExporter.deltaToMarkdown([
          {
            'insert': {'image': 'data:image/png;base64,AAAA'},
          },
          {'insert': '\n'},
        ]),
        '![图片](saber-embedded-image)\n',
      );
    });

    test('empty delta produces nothing', () {
      expect(MarkdownExporter.deltaToMarkdown([]), '');
    });

    test('a lone newline produces a blank line', () {
      expect(MarkdownExporter.deltaToMarkdown([{'insert': '\n'}]), '\n');
    });
  });
}
