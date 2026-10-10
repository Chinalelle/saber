import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/io_client.dart';
import 'package:saber/data/webdav/webdav_client.dart';

/// 临时冒烟测试：用真群晖跑一遍 WebDavClient 的全部操作。
/// 用法：dart run tool/webdav_smoke.dart
Future<void> main() async {
  final baseUrl = Platform.environment['WD_URL'] ?? 'https://100.88.161.25:5006/';
  final user = Platform.environment['WD_USER'] ?? 'Arigo';
  final pass = Platform.environment['WD_PASS'] ?? 'Khl20071226#';
  final dir = Platform.environment['WD_DIR'] ?? '/home/SaberTest';

  // 群晖默认自签证书，冒烟测试里放行
  final httpClient = IOClient(
    HttpClient()..badCertificateCallback = (cert, host, port) => true,
  );
  final client = WebDavClient(
    baseUrl: baseUrl,
    username: user,
    password: pass,
    httpClient: httpClient,
  );

  try {
    stdout.writeln('1) checkCredentials  ($baseUrl)');
    await client.checkCredentials();
    stdout.writeln('   ✅ 地址与账号可用');

    stdout.writeln('2) mkcol $dir');
    await client.mkcol(dir);
    stdout.writeln('   ✅ 目录就绪（已存在也算成功）');

    final filePath = '$dir/smoke.txt';
    final payload = 'hello from webdav client @ ${DateTime.now()}';
    stdout.writeln('3) put $filePath');
    await client.put(filePath, Uint8List.fromList(utf8.encode(payload)));
    stdout.writeln('   ✅ 上传成功');

    stdout.writeln('4) list $dir');
    final files = await client.list(dir);
    for (final f in files) {
      stdout.writeln(
        '   ${f.path}  dir=${f.isDirectory} size=${f.size} '
        'at=${f.lastModified} etag=${f.etag}',
      );
    }
    if (files.every((f) => !f.path.endsWith('smoke.txt'))) {
      throw StateError('list 结果里没有刚上传的文件');
    }
    stdout.writeln('   ✅ 列表包含刚上传的文件');

    stdout.writeln('5) stat $filePath');
    final meta = await client.stat(filePath);
    stdout.writeln('   $meta');
    if (meta == null || meta.size == null) {
      throw StateError('stat 没拿到元数据');
    }
    stdout.writeln('   ✅ 元数据正常');

    stdout.writeln('6) get $filePath');
    final bytes = await client.get(filePath);
    final text = utf8.decode(bytes);
    stdout.writeln('   内容: $text');
    if (text != payload) throw StateError('下载内容与上传不一致');
    stdout.writeln('   ✅ 内容一致');

    stdout.writeln('7) stat 一个不存在的文件（应返回 null，不抛异常）');
    final missing = await client.stat('$dir/definitely-not-here.txt');
    if (missing != null) throw StateError('不存在的文件居然返回了元数据');
    stdout.writeln('   ✅ 正确处理 404');

    stdout.writeln('8) delete $filePath');
    await client.delete(filePath);
    final after = await client.stat(filePath);
    if (after != null) throw StateError('删除后还能查到文件');
    stdout.writeln('   ✅ 删除成功');

    stdout.writeln('\n🎉 WebDavClient 全部操作通过');
  } finally {
    client.close();
  }
}
