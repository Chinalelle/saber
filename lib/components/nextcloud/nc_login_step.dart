import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:saber/components/settings/app_info.dart';
import 'package:saber/components/theming/adaptive_circular_progress_indicator.dart';
import 'package:saber/data/nextcloud/nextcloud_client_extension.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/webdav/webdav_client.dart';
import 'package:saber/i18n/strings.g.dart';
import 'package:url_launcher/url_launcher.dart';

const _width = 400.0;

const _ncColor = Color(0xFF0082c9);

/// 登录步骤。
///
/// 以前这里跑的是 Nextcloud 的 login flow v2（弹浏览器、等用户授权、再轮询拿
/// app password），只有 Nextcloud 系的服务能用。改成通用 WebDAV 之后就没这套
/// 东西了，直接填「服务器地址 + 用户名 + 密码」，当场用 WebDAV 探活验证。
class NcLoginStep extends HookWidget {
  const new({super.key, required this.recheckCurrentStep});

  final void Function() recheckCurrentStep;

  @override
  Widget build(BuildContext context) {
    final addressController = useTextEditingController(text: stows.url.value);
    final usernameController = useTextEditingController(
      text: stows.username.value,
    );
    final passwordController = useTextEditingController();
    final busy = useState(false);
    final error = useState<String?>(null);

    Future<void> submit() async {
      final address = _prependHttpsIfMissing(addressController.text.trim());
      final username = usernameController.text.trim();
      final password = passwordController.text;

      busy.value = true;
      error.value = null;

      final client = WebDavClient(
        baseUrl: address,
        username: username,
        password: password,
        httpClient: NextcloudClientExtension.newHttpClient(),
      );
      try {
        // 能对根目录做一次 PROPFIND 就说明地址、账号、密码都对
        await client.checkCredentials();

        stows.url.value = address;
        stows.username.value = username;
        stows.ncPassword.value = password;
        stows.encPassword.value = '';
        stows.pfp.value = null;

        recheckCurrentStep();
      } on WebDavException catch (e) {
        error.value = e.statusCode == 401 || e.statusCode == 403
            ? t.login.ncLoginStep.wrongCredentials
            : t.login.ncLoginStep.loginFailed(error: e.toString());
      } catch (e) {
        error.value = t.login.ncLoginStep.loginFailed(error: '$e');
      } finally {
        client.close();
        busy.value = false;
      }
    }

    final screenSize = MediaQuery.sizeOf(context);
    final shouldUseTwoColumns = _shouldUseTwoColumns(screenSize);
    final form = _LoginForm(
      addressController: addressController,
      usernameController: usernameController,
      passwordController: passwordController,
      busy: busy.value,
      error: error.value,
      onSubmit: submit,
    );

    if (shouldUseTwoColumns) {
      return Center(
        child: Padding(
          padding: const .all(64),
          child: SizedBox(
            width: _width * 3,
            child: Row(
              mainAxisAlignment: .center,
              crossAxisAlignment: .start,
              spacing: 64,
              children: [
                Expanded(
                  child: _Header(shouldUseTwoColumns: shouldUseTwoColumns),
                ),
                Expanded(child: form),
              ],
            ),
          ),
        ),
      );
    } else {
      return ListView(
        padding: .symmetric(
          horizontal: screenSize.width > _width
              ? (screenSize.width - _width) / 2
              : 16,
          vertical: 16,
        ),
        children: [
          const SizedBox(height: 16),
          _Header(shouldUseTwoColumns: shouldUseTwoColumns),
          const SizedBox(height: 32),
          form,
        ],
      );
    }
  }
}

class _LoginForm extends HookWidget {
  const new({
    required this.addressController,
    required this.usernameController,
    required this.passwordController,
    required this.busy,
    required this.error,
    required this.onSubmit,
  });

  final TextEditingController addressController;
  final TextEditingController usernameController;
  final TextEditingController passwordController;
  final bool busy;
  final String? error;
  final Future<void> Function() onSubmit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = ColorScheme.of(context);

    Widget field({
      required TextEditingController controller,
      required String label,
      String? hint,
      bool obscure = false,
      bool autocorrect = false,
      Iterable<String>? autofillHints,
      TextInputType? keyboardType,
    }) {
      return TextField(
        controller: controller,
        enabled: !busy,
        obscureText: obscure,
        autocorrect: autocorrect,
        enableSuggestions: autocorrect,
        keyboardType: keyboardType,
        autofillHints: autofillHints,
        decoration: InputDecoration(labelText: label, hintText: hint),
        onSubmitted: (_) => onSubmit(),
      );
    }

    return Column(
      crossAxisAlignment: .stretch,
      children: [
        Row(
          mainAxisAlignment: .end,
          children: [
            SvgPicture.asset(
              'assets/images/nextcloud-logo.svg',
              width: 32,
              height: 32,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                t.login.ncLoginStep.otherNcServer,
                style: theme.textTheme.headlineSmall,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        field(
          controller: addressController,
          label: t.login.ncLoginStep.serverUrl,
          hint: t.login.ncLoginStep.serverUrlHint,
          autofillHints: const [AutofillHints.url],
          keyboardType: TextInputType.url,
        ),
        const SizedBox(height: 8),
        field(
          controller: usernameController,
          label: t.login.ncLoginStep.username,
          autofillHints: const [AutofillHints.username],
        ),
        const SizedBox(height: 8),
        field(
          controller: passwordController,
          label: t.login.ncLoginStep.password,
          obscure: true,
          autofillHints: const [AutofillHints.password],
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: busy ? null : onSubmit,
          style: _buttonStyleFromBrand(_ncColor),
          child: busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: AdaptiveCircularProgressIndicator(),
                )
              : Text(t.login.ncLoginStep.login),
        ),
        if (error != null) ...[
          const SizedBox(height: 12),
          Text(
            error!,
            style: TextStyle(color: colorScheme.error),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }
}

class const _Header({required final bool shouldUseTwoColumns})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .stretch,
      children: [
        if (!shouldUseTwoColumns)
          _HeaderImage(shouldUseTwoColumns: shouldUseTwoColumns),
        Text(
          t.login.ncLoginStep.whereToStoreData,
          style: theme.textTheme.headlineSmall,
        ),
        Text.rich(
          t.login.form.agreeToPrivacyPolicy(
            linkToPrivacyPolicy: (text) => TextSpan(
              text: text,
              style: TextStyle(color: theme.colorScheme.primary),
              recognizer: TapGestureRecognizer()
                ..onTap = () {
                  launchUrl(AppInfo.privacyPolicyUrl);
                },
            ),
          ),
        ),
        if (shouldUseTwoColumns)
          _HeaderImage(shouldUseTwoColumns: shouldUseTwoColumns),
      ],
    );
  }
}

class const _HeaderImage({required final bool shouldUseTwoColumns})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);

    // Remove banner image on tiny screens to save space
    if (screenSize.height < 500) return const SizedBox();

    final maxHeight = shouldUseTwoColumns
        ? screenSize.height * 0.3
        : screenSize.height * 0.25;

    return Padding(
      padding: .only(bottom: min(64, screenSize.height * 0.05)),
      child: SvgPicture.asset(
        'assets/images/undraw_cloud_sync_re_02p1.svg',
        width: _width,
        height: min(_width * 576 / 844.6693, maxHeight),
        excludeFromSemantics: true,
      ),
    );
  }
}

bool _shouldUseTwoColumns(Size screenSize) {
  const minWidthForTwoColumns = _width * 2;
  const minHeightForTwoColumns = _width * 1.5;
  final landscape = screenSize.width >= screenSize.height;
  return landscape &&
      screenSize.width > minWidthForTwoColumns &&
      screenSize.height > minHeightForTwoColumns;
}

String _prependHttpsIfMissing(String url) =>
    url.startsWith(RegExp(r'https?://')) ? url : 'https://$url';

ButtonStyle _buttonStyleFromBrand(Color primary, [Color? onPrimary]) {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: primary,
    primary: primary,
    onPrimary: onPrimary,
  );
  return ElevatedButton.styleFrom(
    backgroundColor: colorScheme.primary,
    foregroundColor: colorScheme.onPrimary,
  );
}
