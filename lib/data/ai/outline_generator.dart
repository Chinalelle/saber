import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:saber/data/editor/outline_entry.dart';

/// 生成大纲时的进度。
@immutable
class OutlineProgress {
  const new({
    required this.done,
    required this.total,
    required this.status,
  });

  /// 已经处理完的页数（不含失败跳过的）。
  final int done;

  /// 一共要处理多少页。
  final int total;

  /// 给用户看的一句话，比如「正在识别第 9-16 页」。
  final String status;

  double get fraction => total <= 0 ? 0 : (done / total).clamp(0, 1);
}

/// 生成大纲过程中的错误（网络、鉴权、返回格式不对等）。
///
/// 单独一个类型，是为了让 UI 能直接把 [message] 显示给用户，
/// 而不用去 `toString()` 一个看不懂的异常。
class OutlineException implements Exception {
  const new(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => 'OutlineException($message)';
}

/// 一页待识别的图片：PDF 页码 + PNG 的 base64。
typedef OutlineBatchPage = ({int pdfPageIndex, String base64});

/// 用大模型给 PDF 生成大纲。
///
/// 两件事分开：`fromPdfBookmarks` 读 PDF 自带书签（不要钱、页码绝对准），
/// `generateWithAi` 才去调模型逐页看图。调用方先试前者，没有书签再用后者。
class OutlineGenerator {
  static final log = Logger('OutlineGenerator');

  /// 系统提示词。要点：
  /// - 只要「章节/小节开始」的页，不要每页都写摘要（那样大纲会变成流水账）
  /// - 页码必须是给它的那些页之一，防止模型编页码
  /// - 标题保留原文，不翻译不改写
  static const systemPrompt =
      '你是一个文档结构分析助手，任务是给一份扫描文档做目录（大纲）。\n'
      '用户会把若干页的图片发给你，每张图片前面都标明了它属于第几页。\n'
      '\n'
      '请找出这些页中出现的「章节标题」和「小节标题」，判断它们各属于第几级。\n'
      '\n'
      '只输出 JSON，格式如下：\n'
      '{"entries":[{"page":3,"level":1,"title":"第一章 绪论"}]}\n'
      '\n'
      '规则：\n'
      '1. page 必须是整数，且必须是用户给你的页码之一，不要自己推算或编造。\n'
      '2. level 表示层级：1 是章，2 是节，3 是小节。拿不准就用 1。\n'
      '3. title 用页面上的原文，不要翻译、不要改写、不要加编号以外的修饰。\n'
      '4. 只有「这一页是某个章节或小节的开始」时才输出它；某页只是正文的继续，不要输出。\n'
      '5. 封面、目录页、版权页、参考文献列表本身不算条目。\n'
      '6. 如果这些页里没有任何标题，返回 {"entries":[]}。';

  /// 读 PDF 自带的书签，转成大纲条目。
  ///
  /// [pdfPageToEditorPage] 把 PDF 的页码（0 起）映射到 `coreInfo.pages` 的下标；
  /// 不在表里的页（用户删掉了）会被丢掉。返回按页码排序的结果，可能为空
  /// —— 扫描件通常没有书签。
  static Future<List<OutlineEntry>> fromPdfBookmarks(
    PdfDocument pdf, {
    required Map<int, int> pdfPageToEditorPage,
  }) async {
    final List<OutlineEntry> entries = [];

    void walk(List<PdfOutlineNode> nodes, int level) {
      for (final node in nodes) {
        final pdfPage = node.dest?.pageNumber;
        final editorPage = pdfPage == null
            ? null
            : pdfPageToEditorPage[pdfPage];
        final title = node.title.trim();
        if (editorPage != null && title.isNotEmpty) {
          entries.add(
            OutlineEntry(
              title: title,
              pageIndex: editorPage,
              level: level.clamp(1, 3),
              source: OutlineSource.pdfBookmark,
            ),
          );
        }
        if (node.children.isNotEmpty) walk(node.children, level + 1);
      }
    }

    try {
      walk(await pdf.loadOutline(), 1);
    } catch (e) {
      log.warning('读取 PDF 书签失败: $e');
      return const [];
    }

    entries.sort((a, b) => a.pageIndex.compareTo(b.pageIndex));
    return entries;
  }

  /// 调大模型逐页看图，生成大纲。
  ///
  /// [pagesToProcess] 是要处理的 PDF 页码（0 起，升序）。
  /// [onProgress] 每批开始时和结束后各回调一次。
  /// [isCancelled] 返回 true 时尽快停下，并把已经拿到的结果返回（不清空）。
  static Future<List<OutlineEntry>> generateWithAi({
    required PdfDocument pdf,
    required List<int> pagesToProcess,
    required Map<int, int> pdfPageToEditorPage,
    required String apiKey,
    required String baseUrl,
    required String model,
    required int pagesPerBatch,
    required int renderLongSide,
    required void Function(OutlineProgress) onProgress,
    bool Function()? isCancelled,
    http.Client? httpClient,
    Duration timeout = const Duration(seconds: 90),
  }) async {
    if (apiKey.trim().isEmpty) {
      throw const OutlineException('还没有填 API Key，去「设置 → AI 大纲」里填一下');
    }
    if (pagesToProcess.isEmpty) {
      throw const OutlineException('这份笔记里没有可识别的 PDF 页面');
    }

    final client = httpClient ?? http.Client();
    final ownsClient = httpClient == null;
    final batchSize = pagesPerBatch.clamp(1, 40);
    final total = pagesToProcess.length;
    final gathered = <OutlineEntry>[];
    var done = 0;

    try {
      for (var start = 0; start < total; start += batchSize) {
        if (isCancelled?.call() ?? false) {
          log.info('大纲生成被取消，已处理 $done/$total 页');
          break;
        }

        final batch = pagesToProcess.sublist(
          start,
          (start + batchSize).clamp(0, total),
        );
        final firstPage = batch.first + 1;
        final lastPage = batch.last + 1;
        onProgress(
          OutlineProgress(
            done: done,
            total: total,
            status: '正在识别第 $firstPage-$lastPage 页',
          ),
        );

        // 逐页渲染 + 编码；单页失败就跳过这一页，不要让整批报废
        final batchPages = <OutlineBatchPage>[];
        for (final pdfPageIndex in batch) {
          try {
            final png = await renderPageToPng(
              pdf.pages[pdfPageIndex],
              longSide: renderLongSide,
            );
            batchPages.add((
              pdfPageIndex: pdfPageIndex,
              base64: base64Encode(png),
            ));
          } catch (e) {
            log.warning('第 ${pdfPageIndex + 1} 页渲染失败，跳过: $e');
            done++;
          }
        }

        if (batchPages.isNotEmpty) {
          final entries = await _requestBatch(
            client: client,
            baseUrl: baseUrl,
            model: model,
            apiKey: apiKey,
            batch: batchPages,
            pdfPageToEditorPage: pdfPageToEditorPage,
            timeout: timeout,
          );
          gathered.addAll(entries);
        }

        done = (start + batch.length).clamp(0, total);
        onProgress(
          OutlineProgress(
            done: done,
            total: total,
            status: '已完成第 $firstPage-$lastPage 页',
          ),
        );
      }
    } finally {
      if (ownsClient) client.close();
    }

    return _dedupe(gathered);
  }

  /// 把一页 PDF 渲染成 PNG。
  ///
  /// [longSide] 控制长边像素：太大白花 token（模型最多按 ~1300×1300 算），
  /// 太小标题的笔画会糊。默认 1400。
  @visibleForTesting
  static Future<Uint8List> renderPageToPng(
    PdfPage page, {
    required int longSide,
  }) async {
    final landscape = page.width >= page.height;
    final rendered = await page.render(
      fullWidth: landscape ? longSide.toDouble() : null,
      fullHeight: landscape ? null : longSide.toDouble(),
    );
    if (rendered == null) {
      throw OutlineException('第 ${page.pageNumber} 页渲染不出来');
    }

    try {
      final image = await rendered.createImage();
      try {
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        if (bytes == null) {
          throw OutlineException('第 ${page.pageNumber} 页转 PNG 失败');
        }
        return bytes.buffer.asUint8List();
      } finally {
        image.dispose();
      }
    } finally {
      rendered.dispose();
    }
  }

  /// 构造一次请求的 body。抽出来是为了能单测。
  @visibleForTesting
  static Map<String, dynamic> buildRequestBody({
    required String model,
    required List<OutlineBatchPage> batch,
  }) {
    final content = <Map<String, dynamic>>[];
    for (final page in batch) {
      // 图片必须在 user 消息里（官方限制），且每张前面标上页码
      content.add({'type': 'text', 'text': '第 ${page.pdfPageIndex + 1} 页：'});
      content.add({
        'type': 'image_url',
        'image_url': {
          'url': 'data:image/png;base64,${page.base64}',
          // 认标题需要细节，不能用 low（low 会把图缩到 512×512）
          'detail': 'original',
        },
      });
    }

    return {
      'model': model,
      'messages': [
        {'role': 'system', 'content': systemPrompt},
        {'role': 'user', 'content': content},
      ],
      'response_format': {'type': 'json_object'},
      'temperature': 0.2,
      // deepseek-flash 是推理模型，thinking 会和正文共用这个额度：
      // 实测一批 8 页要花 6000+ 个 reasoning token，留 4000 会导致
      // finish_reason=length、content 为空。给足额度才有正文。
      'max_tokens': 16000,
      'stream': false,
    };
  }

  /// 解析模型返回的 JSON，转成大纲条目。
  ///
  /// 页码不在 [pdfPageToEditorPage] 里的条目会被丢掉 —— 模型偶尔会回答一个
  /// 没让它看的页码，宁可少一条也不要跳错地方。
  @visibleForTesting
  static List<OutlineEntry> parseResponse(
    String responseBody, {
    required Map<int, int> pdfPageToEditorPage,
  }) {
    final dynamic decoded = jsonDecode(responseBody);
    if (decoded is! Map) {
      throw const OutlineException('模型返回的不是一个 JSON 对象');
    }

    final rawEntries = decoded['entries'];
    if (rawEntries is! List) return const [];

    final entries = <OutlineEntry>[];
    for (final raw in rawEntries) {
      if (raw is! Map) continue;
      final title = (raw['title'] as String? ?? '').trim();
      final rawPage = raw['page'];
      if (title.isEmpty || rawPage is! num) continue;

      // 模型给的是 1 起的页码，减一回 0 起
      final pdfPageIndex = rawPage.toInt() - 1;
      final editorPage = pdfPageToEditorPage[pdfPageIndex];
      if (editorPage == null) {
        log.info('模型给了一个没让它看的页码 ${rawPage.toInt()}，丢掉');
        continue;
      }

      final level = (raw['level'] as num?)?.toInt() ?? 1;
      entries.add(
        OutlineEntry(
          title: title,
          pageIndex: editorPage,
          level: level.clamp(1, 3),
          source: OutlineSource.ai,
        ),
      );
    }
    return entries;
  }

  static Future<List<OutlineEntry>> _requestBatch({
    required http.Client client,
    required String baseUrl,
    required String model,
    required String apiKey,
    required List<OutlineBatchPage> batch,
    required Map<int, int> pdfPageToEditorPage,
    required Duration timeout,
  }) async {
    final uri = Uri.parse('${baseUrl.trimRight().replaceAll(RegExp(r'/+$'), '')}/chat/completions');
    final body = jsonEncode(buildRequestBody(model: model, batch: batch));

    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      if (attempt > 0) {
        await Future.delayed(Duration(milliseconds: 500 * (1 << attempt)));
        log.info('大纲请求重试第 $attempt 次');
      }
      try {
        final response = await client
            .post(
              uri,
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $apiKey',
              },
              body: body,
            )
            .timeout(timeout);

        if (response.statusCode == 200) {
          final content =
              (jsonDecode(utf8.decode(response.bodyBytes))
                      as Map)['choices']?[0]?['message']?['content']
                  as String?;
          if (content == null || content.isEmpty) {
            throw const OutlineException('模型返回了空内容');
          }
          return parseResponse(
            content,
            pdfPageToEditorPage: pdfPageToEditorPage,
          );
        }

        // 鉴权、额度这类错误重试也没用，直接抛
        if (response.statusCode == 401 || response.statusCode == 403) {
          throw const OutlineException(
            'API Key 被拒绝了（401/403），检查一下设置里的 Key',
            statusCode: 401,
          );
        }
        if (response.statusCode == 402) {
          throw const OutlineException('账户余额不足（402）', statusCode: 402);
        }
        if (response.statusCode == 429) {
          // 限流：退避后再来
          throw const OutlineException('请求太频繁（429）', statusCode: 429);
        }
        throw OutlineException(
          '接口返回 HTTP ${response.statusCode}：'
          '${utf8.decode(response.bodyBytes).substring(0, 200)}',
          statusCode: response.statusCode,
        );
      } catch (e) {
        lastError = e;
        // 鉴权/余额错误不重试
        if (e is OutlineException &&
            (e.statusCode == 401 || e.statusCode == 402)) {
          rethrow;
        }
      }
    }

    throw OutlineException('这批页识别失败：$lastError');
  }

  /// 去掉重复（同一页同一标题）并按页码排序。
  static List<OutlineEntry> _dedupe(List<OutlineEntry> entries) {
    final seen = <String>{};
    final result = <OutlineEntry>[];
    for (final entry in entries) {
      final key = '${entry.pageIndex}|${entry.title}';
      if (seen.add(key)) result.add(entry);
    }
    result.sort((a, b) {
      final byPage = a.pageIndex.compareTo(b.pageIndex);
      return byPage != 0 ? byPage : a.level.compareTo(b.level);
    });
    return result;
  }
}
