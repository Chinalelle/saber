import 'package:flutter/widgets.dart' show TextSelection;
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saber/components/editor/math_embed.dart';

void main() {
  group('文本框里的 LaTeX 公式 embed', () {
    test('插入的公式会以 {"math": ...} 存进 Delta', () {
      final doc = Document()..insert(0, '前后');
      final controller = QuillController(
        document: doc,
        selection: const TextSelection.collapsed(offset: 1),
      );

      insertMathEmbed(controller, r'E=mc^2');

      final json = doc.toDelta().toJson();
      final mathOps = json
          .where(
            (op) =>
                op['insert'] is Map &&
                (op['insert'] as Map).containsKey(MathEmbedBuilder.embedType),
          )
          .toList();
      expect(mathOps, hasLength(1), reason: '应该只有一个公式 embed');
      expect(mathOps.first['insert'][MathEmbedBuilder.embedType], r'E=mc^2');
    });

    test('存进 sbn2 再读回来，公式还在（序列化往返）', () {
      final doc = Document()..insert(0, '面积 ');
      final controller = QuillController(
        document: doc,
        selection: TextSelection.collapsed(offset: doc.length - 1),
      );
      insertMathEmbed(controller, r'S=\pi r^2');

      final json = doc.toDelta().toJson();
      final restored = Document.fromJson(json);

      final restoredOps = restored
          .toDelta()
          .toJson()
          .where(
            (op) =>
                op['insert'] is Map &&
                (op['insert'] as Map).containsKey(MathEmbedBuilder.embedType),
          )
          .toList();
      expect(restoredOps, hasLength(1));
      expect(
        restoredOps.first['insert'][MathEmbedBuilder.embedType],
        r'S=\pi r^2',
        reason: 'TeX 源码要原样回来，不能丢反斜杠',
      );
      expect(restored.toPlainText(), contains('面积'));
    });

    test('公式会按顺序插在光标位置', () {
      final doc = Document()..insert(0, 'AB');
      final controller = QuillController(
        document: doc,
        selection: const TextSelection.collapsed(offset: 1),
      );

      insertMathEmbed(controller, r'x');

      // 公式应该夹在 A 和 B 中间
      final ops = doc.toDelta().toJson();
      final mathIndex = ops.indexWhere(
        (op) =>
            op['insert'] is Map &&
            (op['insert'] as Map).containsKey(MathEmbedBuilder.embedType),
      );
      expect(ops[mathIndex - 1]['insert'], 'A');
      // 文档最后一段会带上段落换行，所以用 startsWith
      expect(ops[mathIndex + 1]['insert'], startsWith('B'));
    });
  });
}
