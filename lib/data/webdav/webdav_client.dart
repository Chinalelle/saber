import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

/// 一个 WebDAV 资源（文件或目录）。
class WebDavFile {
  const new({
    required this.path,
    required this.isDirectory,
    this.size,
    this.lastModified,
    this.etag,
  });

  /// 相对服务器根的路径，已做 URL 解码，例如 `/Saber/笔记.sbn2`。
  final String path;

  final bool isDirectory;

  /// 字节数；目录一般为 null。
  final int? size;

  final DateTime? lastModified;

  /// 服务器给的 ETag（群晖会返回）。
  final String? etag;

  String get name {
    final parts = path.split('/').where((s) => s.isNotEmpty).toList();
    return parts.isEmpty ? '' : parts.last;
  }

  @override
  String toString() =>
      'WebDavFile($path, dir=$isDirectory, size=$size, at=$lastModified)';
}

/// WebDAV 请求失败（非 2xx）。刻意保持和 Nextcloud SDK 的异常同名属性
/// （`statusCode`），这样上层 `catch` 逻辑基本不用改。
class WebDavException implements Exception {
  const new(this.statusCode, [this.message]);

  final int statusCode;
  final String? message;

  @override
  String toString() =>
      'WebDavException($statusCode${message == null ? '' : ': $message'})';
}

/// 一个够用的 WebDAV 客户端：Basic Auth + PROPFIND / GET / PUT / MKCOL / DELETE。
///
/// Saber 原来用的是 Nextcloud 专用 SDK，路径写死成 `/remote.php/dav/files/<user>/...`
/// 并且要跑 Nextcloud 的 login flow v2 —— 连群晖、坚果云这类标准 WebDAV 服务都不行。
/// 这个实现只依赖 RFC 4918 的标准部分，服务器地址 + 账号 + 密码就能用。
class WebDavClient {
  new({
    required String baseUrl,
    required this.username,
    required this.password,
    http.Client? httpClient,
  }) : baseUri = _normalizeBase(baseUrl),
       _http = httpClient ?? http.Client();

  /// 服务器根地址，末尾一定带 `/`。
  final Uri baseUri;

  final String username;
  final String password;
  final http.Client _http;

  static Uri _normalizeBase(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return Uri.parse('https://localhost/');
    final withScheme = trimmed.contains('://') ? trimmed : 'https://$trimmed';
    final uri = Uri.parse(withScheme);
    final path = uri.path.endsWith('/') ? uri.path : '${uri.path}/';
    return uri.replace(path: path.isEmpty ? '/' : path);
  }

  String get _authorization =>
      'Basic ${base64Encode(utf8.encode('$username:$password'))}';

  /// 把 `/a/b c.txt` 拼成完整的、各段都转义过的 URL。
  Uri uriFor(String path, {bool directory = false}) {
    final segments = path
        .split('/')
        .where((s) => s.isNotEmpty)
        .map(Uri.encodeComponent)
        .join('/');
    var full = baseUri.toString();
    if (segments.isNotEmpty) {
      full = '$full$segments';
      if (directory) full = '$full/';
    }
    return Uri.parse(full);
  }

  Map<String, String> _headers({int? depth}) => {
    'Authorization': _authorization,
    if (depth != null) 'Depth': '$depth',
  };

  static const _propfindBody =
      '<?xml version="1.0" encoding="utf-8"?>'
      '<d:propfind xmlns:d="DAV:">'
      '<d:prop>'
      '<d:getcontentlength/>'
      '<d:getlastmodified/>'
      '<d:resourcetype/>'
      '<d:getetag/>'
      '</d:prop>'
      '</d:propfind>';

  /// 列出目录内容（Depth: 1），不含目录自身。目录不存在会抛 404。
  Future<List<WebDavFile>> list(String path) async {
    final files = await _propfind(path, depth: 1);
    final self = path.endsWith('/') ? path : '$path/';
    return files.where((f) => f.path != self && f.path != path).toList();
  }

  /// 取单个资源的元数据（Depth: 0）；不存在返回 null。
  Future<WebDavFile?> stat(String path) async {
    try {
      final files = await _propfind(path, depth: 0);
      return files.firstOrNull;
    } on WebDavException catch (e) {
      if (e.statusCode == HttpStatus.notFound) return null;
      rethrow;
    }
  }

  Future<List<WebDavFile>> _propfind(String path, {required int depth}) async {
    final request = http.Request('PROPFIND', uriFor(path))
      ..headers.addAll(_headers(depth: depth))
      ..headers['Content-Type'] = 'application/xml; charset=utf-8'
      ..body = _propfindBody;

    final response = await _http.send(request);
    final body = await response.stream.bytesToString();
    _ensureSuccess(response.statusCode, body);
    return _parseMultiStatus(body);
  }

  Future<Uint8List> get(String path) async {
    final response = await _http.get(uriFor(path), headers: _headers());
    _ensureSuccess(response.statusCode, response.body);
    return response.bodyBytes;
  }

  /// 上传文件。
  ///
  /// [lastModified] 会以标准的 `Last-Modified` 头发出去：采纳它的服务器
  /// （群晖会）会让远端 mtime 与本地一致，否则每次同步都会因为「远端更新」
  /// 而反复回传。不采纳的服务器只是忽略这个头，没有副作用。
  Future<void> put(
    String path,
    Uint8List bytes, {
    DateTime? lastModified,
  }) async {
    final response = await _http.put(
      uriFor(path),
      headers: {
        ..._headers(),
        'Content-Type': 'application/octet-stream',
        if (lastModified != null)
          'Last-Modified': HttpDate.format(lastModified.toUtc()),
      },
      body: bytes,
    );
    _ensureSuccess(response.statusCode, response.body);
  }

  /// 建目录；已存在时静默成功（405 / 301 / 200 都算）。
  Future<void> mkcol(String path) async {
    final response = await _http.send(
      http.Request('MKCOL', uriFor(path, directory: true))
        ..headers.addAll(_headers()),
    );
    final status = response.statusCode;
    await response.stream.drain<void>();
    if (status == HttpStatus.created ||
        status == HttpStatus.ok ||
        status == HttpStatus.methodNotAllowed ||
        status == HttpStatus.movedPermanently) {
      return;
    }
    throw WebDavException(status);
  }

  Future<void> delete(String path) async {
    final response = await _http.delete(uriFor(path), headers: _headers());
    _ensureSuccess(response.statusCode, response.body);
  }

  /// 快速探活 + 校验账号密码：能列出根目录就说明地址和凭据都对。
  Future<void> checkCredentials() async {
    await _propfind('', depth: 0);
  }

  void close() => _http.close();

  void _ensureSuccess(int statusCode, String body) {
    if (statusCode >= 200 && statusCode < 300) return;
    throw WebDavException(
      statusCode,
      body.isEmpty
          ? null
          : (body.length > 200 ? body.substring(0, 200) : body),
    );
  }

  static const _davNamespace = 'DAV:';

  List<WebDavFile> _parseMultiStatus(String xmlText) {
    final document = XmlDocument.parse(xmlText);
    final result = <WebDavFile>[];

    for (final response in document.findAllElements(
      'response',
      namespace: _davNamespace,
    )) {
      final href = response
          .findElements('href', namespace: _davNamespace)
          .firstOrNull
          ?.innerText;
      if (href == null || href.isEmpty) continue;

      final decodedPath = Uri.decodeComponent(Uri.parse(href).path);

      final prop = response
          .findElements('propstat', namespace: _davNamespace)
          .expand((e) => e.findElements('prop', namespace: _davNamespace))
          .firstOrNull;

      if (prop == null) continue;

      final isDirectory = prop
          .findElements('resourcetype', namespace: _davNamespace)
          .expand(
            (e) => e.findElements('collection', namespace: _davNamespace),
          )
          .isNotEmpty;

      final lengthText = prop
          .findElements('getcontentlength', namespace: _davNamespace)
          .firstOrNull
          ?.innerText;
      final modifiedText = prop
          .findElements('getlastmodified', namespace: _davNamespace)
          .firstOrNull
          ?.innerText;
      final etagText = prop
          .findElements('getetag', namespace: _davNamespace)
          .firstOrNull
          ?.innerText;

      DateTime? modified;
      if (modifiedText != null) {
        try {
          modified = HttpDate.parse(modifiedText);
        } catch (_) {
          modified = DateTime.tryParse(modifiedText);
        }
      }

      result.add(
        WebDavFile(
          path: decodedPath,
          isDirectory: isDirectory,
          size: lengthText == null ? null : int.tryParse(lengthText),
          lastModified: modified,
          etag: etagText,
        ),
      );
    }
    return result;
  }
}
