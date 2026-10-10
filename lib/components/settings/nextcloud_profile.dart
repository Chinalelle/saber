import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';
import 'package:saber/components/theming/adaptive_icon.dart';
import 'package:saber/components/theming/adaptive_linear_progress_indicator.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/nextcloud/saber_syncer.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/quota.dart';
import 'package:saber/data/routes.dart';
import 'package:saber/i18n/strings.g.dart';
import 'package:saber/pages/user/login.dart';

class const NextcloudProfile({super.key}) extends HookWidget {
  /// If non-null, this will be used instead of the actual login state.
  @visibleForTesting
  static LoginStep? forceLoginStep;

  @override
  Widget build(BuildContext context) {
    final username = useValueListenable(stows.username);
    final encPassword = useValueListenable(stows.encPassword);
    final key = useValueListenable(stows.key);
    final iv = useValueListenable(stows.iv);
    final pfp = useValueListenable(stows.pfp);

    final quota = useValueListenable(stows.lastStorageQuota);
    useMemoized(getStorageQuota, [username, encPassword, key, iv]);

    final loginStep = forceLoginStep ?? NcLoginPage.getCurrentStep();
    final heading = switch (loginStep) {
      .waitingForPrefs => '',
      .nc => t.login.status.loggedOut,
      .enc || .done => t.login.status.hi(u: stows.username.value),
    };
    final subheading = switch (loginStep) {
      .waitingForPrefs => '',
      .nc => t.login.status.tapToLogin,
      .enc => t.login.status.almostDone,
      .done => t.login.status.loggedIn,
    };
    const pfpSize = 48.0;

    return ListTile(
      visualDensity: VisualDensity.standard,
      onTap: () => context.push(RoutePaths.login),
      leading: ClipRSuperellipse(
        borderRadius: const .all(.circular(18)),
        child: pfp == null
            ? const _UnknownPfp(size: pfpSize)
            : Image.memory(pfp, width: pfpSize, height: pfpSize),
      ),
      title: Text(heading),
      subtitle: Text(subheading),
      trailing: loginStep == .done
          ? Row(
              mainAxisSize: .min,
              spacing: 8,
              children: [
                _QuotaSummary(quota: quota),
                IconButton(
                  icon: const AdaptiveIcon(
                    icon: Icons.cloud_upload,
                    cupertinoIcon: CupertinoIcons.cloud_upload,
                  ),
                  tooltip: t.settings.resyncEverything,
                  onPressed: () async {
                    stows.fileSyncResyncEverythingDate.value = DateTime.now();
                    final allFiles = await FileManager.getAllFiles(
                      includeExtensions: true,
                      includeAssets: true,
                    );
                    for (final file in allFiles) {
                      syncer.uploader.enqueueRel(file);
                    }
                  },
                ),
                // 手动下载：拉取服务器上的改动（本地较旧的笔记会被覆盖）
                IconButton(
                  icon: const AdaptiveIcon(
                    icon: Icons.cloud_download,
                    cupertinoIcon: CupertinoIcons.cloud_download,
                  ),
                  tooltip: t.settings.downloadFromServer,
                  onPressed: () async {
                    await syncer.downloader.refresh();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(t.settings.downloadFromServer),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    }
                  },
                ),
              ],
            )
          : null,
    );
  }

  /// 存储配额。
  ///
  /// 原来的做法是查 Nextcloud 的 provisioning API，换成通用 WebDAV 后没有对应接口
  /// —— Synology 的 WebDAV 连标准的 `DAV:quota-available-bytes` 都不返回（一律 404），
  /// 所以这里改读服务器上的一个 JSON 文件：
  ///
  ///   <服务器URL>/.saber_quota.json  ->  {"used": 123, "total": 456}
  ///
  /// 该文件由 NAS 上的定时任务（`synosharequota`）每 5 分钟刷新一次。
  /// 它位于 Saber 同步目录（`Saber/`）之外，所以不会被同步逻辑碰到。
  static Future<Quota?> getStorageQuota() async {
    try {
      final url = stows.url.value;
      if (url.isEmpty) return stows.lastStorageQuota.value = null;

      final client = SaberSyncInterface.client;
      if (client == null) return stows.lastStorageQuota.value = null;

      // 注意：WebDavClient.uriFor 会把参数当成【相对 baseUrl 的路径】来拼接，
      // 所以这里只能传文件名，不能传完整 URL。
      final bytes = await client.get(_quotaFileName);
      final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      final used = (json['used'] as num?)?.toInt() ?? 0;
      final total = (json['total'] as num?)?.toInt() ?? 0;
      if (total <= 0) return stows.lastStorageQuota.value = null;

      return stows.lastStorageQuota.value = Quota(
        .fromJson({
          'free': total - used,
          'used': used,
          'total': total,
          'relative': used / total * 100,
          'quota': total,
        }),
      );
    } catch (e, st) {
      // 服务器没放这个文件时是正常情况，不必当成错误刷屏
      log.fine('Failed to load storage quota', e, st);
      return stows.lastStorageQuota.value = null;
    }
  }

  /// 配额文件的名字（由服务器端的定时任务生成）。
  static const _quotaFileName = '.saber_quota.json';

  static final log = Logger('NextcloudProfile');
}

class _UnknownPfp extends StatelessWidget {
  const new({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    return SizedBox(
      width: size,
      height: size,
      child: ColoredBox(
        color: colorScheme.primaryContainer,
        child: Icon(
          Icons.person,
          color: colorScheme.onPrimaryContainer,
          size: size * 0.7,
        ),
      ),
    );
  }
}

class _QuotaSummary extends StatelessWidget {
  const new({required this.quota});

  final Quota? quota;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);

    return IntrinsicWidth(
      child: Column(
        mainAxisSize: .min,
        spacing: 2,
        children: [
          AdaptiveLinearProgressIndicator(
            semanticsLabel: 'Storage usage',
            value: quota?.progressIndicatorValue,
            backgroundColor: colorScheme.primary.withValues(alpha: 0.3),
            color: colorScheme.primary.withValues(alpha: 0.8),
            minHeight: 8,
          ),
          Text(quota?.describeConcise() ?? Quota.describeConcisePlaceholder()),
        ],
      ),
    );
  }
}
