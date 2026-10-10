import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart';
import 'package:http/io_client.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/nextcloud/errors.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/version.dart';
import 'package:saber/data/webdav/webdav_client.dart';

/// 同步用的传输层扩展。
///
/// 以前这里挂在 `NextcloudClient` 上（Nextcloud 专用 SDK，路径写死成
/// `/remote.php/dav/files/<user>/...`）。现在换成标准 WebDAV 客户端，
/// 群晖、坚果云这类服务都能连，配置只要「地址 + 账号 + 密码」。
/// 类名保持不变，是为了让同步各处的引用不用改。
extension NextcloudClientExtension on WebDavClient {
  static const String appRootDirectoryPrefix =
      FileManager.appRootDirectoryPrefix;
  static const configFileName = 'config.sbc';
  static const configFilePath =
      '$appRootDirectoryPrefix/$configFileName';

  static const _utf8Decoder = Utf8Decoder(allowMalformed: true);

  static const reproducibleSalt = r'8MnPs64@R&mF8XjWeLrD';

  static final userAgent =
      'Saber/$buildName '
      '(${Platform.operatingSystem}) '
      'Dart/${Platform.version.split(' ').first}';

  /// 群晖/家用 NAS 的 WebDAV 默认是自签证书，因此这里跟随 Saber 已有的
  /// 「允许不安全的连接」开关（设置 → 高级）。
  static IOClient newHttpClient() {
    final httpClient = HttpClient()..userAgent = userAgent;
    if (stows.allowInsecureConnections.value) {
      httpClient.badCertificateCallback = (cert, host, port) => true;
    }
    return IOClient(httpClient);
  }

  static WebDavClient? withSavedDetails() {
    if (!stows.loggedIn) return null;

    final url = stows.url.value;
    if (url.isEmpty) return null;

    return WebDavClient(
      baseUrl: url,
      username: stows.username.value,
      password: stows.ncPassword.value,
      httpClient: newHttpClient(),
    );
  }

  /// 下载远端配置（加密密钥那份）。
  Future<Map<String, String>> getConfig() async {
    final Uint8List bytes;
    try {
      bytes = await get(configFilePath);
    } on WebDavException catch (e) {
      if (e.statusCode == HttpStatus.notFound) return {};
      rethrow;
    }

    final json = _utf8Decoder.convert(bytes);
    final decoded = jsonDecode(json) as Map<String, dynamic>;
    return decoded.cast<String, String>();
  }

  /// Generates a config using known values (i.e. from [stows]),
  /// updating the given [config] in place.
  ///
  /// This is usually preceded by a call to [getConfig]
  /// and followed by a call to [setConfig].
  ///
  /// Returns the existing [config] for convenience.
  Future<Map<String, String>> generateConfig({
    required Map<String, String> config,
    Encrypter? encrypter,
    IV? iv,
    Key? key,
  }) async {
    encrypter ??= this.encrypter;
    iv ??= IV.fromBase64(stows.iv.value);
    key ??= Key.fromBase64(stows.key.value);

    config[stows.key.key] = encrypter.encrypt(key.base64, iv: iv).base64;
    config[stows.iv.key] = iv.base64;

    return config;
  }

  /// 上传配置到远端（目录不存在会自动建）。
  Future<void> setConfig(Map<String, String> config) async {
    final json = jsonEncode(config);
    final file = Uint8List.fromList(utf8.encode(json));
    // mkcol 在目录已存在时内部视为成功
    await mkcol(appRootDirectoryPrefix);
    await put(configFilePath, file);
  }

  Future<String> loadEncryptionKey({bool generateKeyIfMissing = true}) async {
    final Encrypter encrypter = this.encrypter;

    final Map<String, String> config = await getConfig();
    if (config.containsKey(stows.key.key) && config.containsKey(stows.iv.key)) {
      final IV iv = IV.fromBase64(config[stows.iv.key]!);
      final encryptedKey = config[stows.key.key]!;
      try {
        final key = encrypter.decrypt64(encryptedKey, iv: iv);
        stows.key.value = key;
        stows.iv.value = iv.base64;
        return key;
      } catch (e) {
        // can't decrypt, so we need to get the previous encryption key (user's password)
        throw EncLoginFailure();
      }
    }

    if (!generateKeyIfMissing) throw EncLoginFailure();

    final Key key = Key.fromSecureRandom(32);
    final IV iv = IV.fromSecureRandom(16);

    await generateConfig(
      config: config,
      encrypter: encrypter,
      iv: iv,
      key: key,
    );
    await setConfig(config);

    stows.key.value = key.base64;
    stows.iv.value = iv.base64;

    return key.base64;
  }

  /// 以前靠 Nextcloud 的 provisioning API 拿用户名，
  /// 换通用 WebDAV 后没有这种接口，直接用设置里填的账号。
  Future<String> getUsername() async => stows.username.value;

  Encrypter get encrypter {
    final List<int> encodedPassword = utf8.encode(
      stows.encPassword.value + reproducibleSalt,
    );
    final List<int> hashedPasswordBytes = sha256.convert(encodedPassword).bytes;
    final Key passwordKey = Key(hashedPasswordBytes as Uint8List);
    return Encrypter(AES(passwordKey));
  }
}
