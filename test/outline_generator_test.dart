import 'package:flutter_test/flutter_test.dart';
import 'package:saber/data/ai/outline_generator.dart';
import 'package:saber/data/editor/outline_entry.dart';

/// 大纲功能里最容易出错、又最适合单测的两块：
/// 请求体怎么拼（图片必须在 user 消息里、每张前面标页码），
/// 以及模型返回的 JSON 怎么解析（页码 1→0→编辑器页下标，编的页码要丢掉）。
void main() {
  group('请求体构造', () {
    test('图片放在 user 消息里，每张图前面标好页码', () {
      final body = OutlineGenerator.buildRequestBody(
        model: 'deepseek-flash',
        batch: const [
          (pdfPageIndex: 4, base64: 'AAAA'),
          (pdfPageIndex: 5, base64: 'BBBB'),
        ],
      );

      expect(body['model'], 'deepseek-flash');
      expect(body['response_format'], {'type': 'json_object'});
      expect(body['stream'], false);

      final messages = body['messages'] as List;
      expect(messages, hasLength(2));
      expect(messages[0]['role'], 'system');
      expect(messages[1]['role'], 'user');

      // 官方限制：图片只能出现在 user 消息里，system 里带图会 400
      final content = messages[1]['content'] as List;
      expect(content, hasLength(4));

      // pdfPageIndex 是 0 起的，给模型看的是 1 起的页码
      expect(content[0], {'type': 'text', 'text': '第 5 页：'});
      expect(content[1]['type'], 'image_url');
      expect(
        (content[1]['image_url'] as Map)['url'],
        'data:image/png;base64,AAAA',
      );
      expect(content[2], {'type': 'text', 'text': '第 6 页：'});
      expect(
        (content[3]['image_url'] as Map)['url'],
        'data:image/png;base64,BBBB',
      );
    });

    test('认标题要用 original，不能用 low（low 会把图缩到 512×512）', () {
      final body = OutlineGenerator.buildRequestBody(
        model: 'm',
        batch: const [(pdfPageIndex: 0, base64: 'x')],
      );
      final imageUrl =
          (body['messages'] as List)[1]['content'][1]['image_url'] as Map;
      expect(imageUrl['detail'], 'original');
    });

    test('系统提示词里明确要求「只报章节开始」和「页码必须来自给定页」', () {
      expect(OutlineGenerator.systemPrompt, contains('章节标题'));
      expect(OutlineGenerator.systemPrompt, contains('必须是用户给你的页码之一'));
      expect(OutlineGenerator.systemPrompt, contains('不要翻译'));
    });
  });

  group('解析模型返回', () {
    test('1 起的页码 -> 编辑器页下标', () {
      final entries = OutlineGenerator.parseResponse(
        '{"entries":[{"page":3,"level":1,"title":"第一章 绪论"},'
        '{"page":4,"level":2,"title":"1.1 背景"}]}',
        pdfPageToEditorPage: const {2: 7, 3: 8},
      );

      expect(entries, hasLength(2));
      expect(entries[0].title, '第一章 绪论');
      expect(entries[0].pageIndex, 7);
      expect(entries[0].level, 1);
      expect(entries[0].source, OutlineSource.ai);
      expect(entries[1].pageIndex, 8);
      expect(entries[1].level, 2);
    });

    test('模型编出来的页码会被丢掉，而不是跳错地方', () {
      final entries = OutlineGenerator.parseResponse(
        '{"entries":[{"page":99,"level":1,"title":"不存在的页"}]}',
        pdfPageToEditorPage: const {2: 7},
      );
      expect(entries, isEmpty);
    });

    test('标题为空、缺 page 字段的条目跳过', () {
      final entries = OutlineGenerator.parseResponse(
        '{"entries":[{"page":3,"level":1,"title":"   "},'
        '{"level":1,"title":"没有页码"},'
        '{"page":3,"level":1,"title":"正常"}]}',
        pdfPageToEditorPage: const {2: 7},
      );
      expect(entries, hasLength(1));
      expect(entries.single.title, '正常');
    });

    test('层级被夹在 1..3', () {
      final entries = OutlineGenerator.parseResponse(
        '{"entries":[{"page":3,"level":0,"title":"太浅"},'
        '{"page":3,"level":9,"title":"太深"}]}',
        pdfPageToEditorPage: const {2: 7},
      );
      expect(entries.map((e) => e.level), [1, 3]);
    });

    test('没有条目时返回空列表，不报错', () {
      expect(
        OutlineGenerator.parseResponse(
          '{"entries":[]}',
          pdfPageToEditorPage: const {},
        ),
        isEmpty,
      );
      expect(
        OutlineGenerator.parseResponse(
          '{}',
          pdfPageToEditorPage: const {},
        ),
        isEmpty,
      );
    });

    test('返回的不是 JSON 对象就抛 OutlineException', () {
      expect(
        () => OutlineGenerator.parseResponse(
          '[1,2,3]',
          pdfPageToEditorPage: const {},
        ),
        throwsA(isA<OutlineException>()),
      );
    });
  });

  group('OutlineEntry', () {
    test('序列化往返', () {
      const entry = OutlineEntry(
        title: '第二章 方剂',
        pageIndex: 12,
        level: 2,
        source: OutlineSource.pdfBookmark,
      );
      expect(OutlineEntry.fromJson(entry.toJson()), entry);
    });

    test('缺字段时给安全默认值（老文件、脏数据）', () {
      final entry = OutlineEntry.fromJson(const {'t': '只有标题'});
      expect(entry.title, '只有标题');
      expect(entry.pageIndex, 0);
      expect(entry.level, 1);
      expect(entry.source, OutlineSource.ai);
    });

    test('越界的页码夹到最后一页，页数为 0 时给 null', () {
      const entry = OutlineEntry(title: 'x', pageIndex: 99);
      expect(entry.clampToPageCount(10)!.pageIndex, 9);
      expect(entry.clampToPageCount(0), isNull);

      const inRange = OutlineEntry(title: 'y', pageIndex: 3);
      expect(inRange.clampToPageCount(10), same(inRange));
    });

    test('fromName 认不出来的一律当 AI 生成', () {
      expect(OutlineSource.fromName(null), OutlineSource.ai);
      expect(OutlineSource.fromName('看不懂'), OutlineSource.ai);
      expect(
        OutlineSource.fromName('pdfBookmark'),
        OutlineSource.pdfBookmark,
      );
    });
  });
}
