import 'dart:io';

import 'package:collapsible/collapsible.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:saber/components/navbar/responsive_navbar.dart';
import 'package:saber/components/settings/app_info.dart';
import 'package:saber/components/settings/nextcloud_profile.dart';
import 'package:saber/components/settings/settings_button.dart';
import 'package:saber/components/settings/settings_color.dart';
import 'package:saber/components/settings/settings_directory_selector.dart';
import 'package:saber/components/settings/settings_dropdown.dart';
import 'package:saber/components/settings/settings_selection.dart';
import 'package:saber/components/settings/settings_sentry.dart';
import 'package:saber/components/settings/settings_subtitle.dart';
import 'package:saber/components/settings/settings_switch.dart';
import 'package:saber/components/settings/settings_text_input.dart';
import 'package:saber/components/settings/update_manager.dart';
import 'package:saber/components/theming/adaptive_alert_dialog.dart';
import 'package:saber/components/theming/adaptive_toggle_buttons.dart';
import 'package:saber/components/theming/saber_theme.dart';
import 'package:saber/components/theming/uni_icon.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/flavor_config.dart';
import 'package:saber/data/is_this_a_test.dart';
import 'package:saber/data/locales.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/routes.dart';
import 'package:saber/data/sentry/sentry_init.dart';
import 'package:saber/data/tools/shape_pen.dart';
import 'package:saber/i18n/strings.g.dart';
import 'package:sbn/canvas_background_pattern.dart';
import 'package:sbn/canvas_texture.dart';
import 'package:stow/stow.dart';

class const SettingsPage({super.key}) extends StatefulWidget {
  @override
  State<SettingsPage> createState() => _SettingsPageState();

  static Future<bool?> showResetDialog({
    required BuildContext context,
    required Stow pref,
    required String prefTitle,
  }) async {
    if (pref.value == pref.defaultValue) return null;
    return await showDialog(
      context: context,
      builder: (context) => AdaptiveAlertDialog(
        title: Text(t.settings.reset.title),
        content: Text(prefTitle),
        actions: [
          CupertinoDialogAction(
            onPressed: () {
              Navigator.of(context).pop(false);
            },
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () {
              pref.value = pref.defaultValue;
              Navigator.of(context).pop(true);
            },
            child: Text(t.settings.reset.button),
          ),
        ],
      ),
    );
  }
}

abstract class _SettingsStows {
  static final appTheme = TransformedStow(
    stows.appTheme,
    (ThemeMode value) => value.index,
    (int value) => ThemeMode.values[value],
  );

  static final platform = TransformedStow(
    stows.platform,
    (TargetPlatform value) => value.index,
    (int value) => TargetPlatform.values[value],
  );

  static final layoutSize = TransformedStow(
    stows.layoutSize,
    (LayoutSize value) => value.index,
    (int value) => LayoutSize.values[value],
  );

  static final editorToolbarAlignment = TransformedStow(
    stows.editorToolbarAlignment,
    (AxisDirection value) => value.index,
    (int value) => AxisDirection.values[value],
  );

  static final infiniteCanvasPattern = TransformedStow(
    stows.infiniteCanvasPattern,
    (CanvasBackgroundPattern value) => value.index,
    (int value) => CanvasBackgroundPattern.values[value],
  );

  static final infiniteCanvasTexture = TransformedStow(
    stows.infiniteCanvasTexture,
    (CanvasTexture value) => value.index,
    (int value) => CanvasTexture.values[value],
  );

  /// AI 的两个数字设置：内部存 int，界面上是文本框，所以来回转成 String。
  static final aiPagesPerBatch = TransformedStow(
    stows.aiPagesPerBatch,
    (int value) => '$value',
    (String value) => int.tryParse(value.trim()) ?? stows.aiPagesPerBatch.value,
  );

  static final aiRenderLongSide = TransformedStow(
    stows.aiRenderLongSide,
    (int value) => '$value',
    (String value) => int.tryParse(value.trim()) ?? stows.aiRenderLongSide.value,
  );
}

class _SettingsPageState extends State<SettingsPage> {
  late TargetPlatform platform;

  @override
  void initState() {
    stows.locale.addListener(onChanged);
    UpdateManager.status.addListener(onChanged);
    super.initState();
  }

  void onChanged() {
    setState(() {});
  }

  // In tests, pretend the current platform is the defaultTargetPlatform
  bool get usesCupertinoByDefault =>
      switch (isThisATest ? platform : defaultTargetPlatform) {
        .iOS => true,
        .macOS => true,
        _ => false,
      };
  bool get usesYaruByDefault =>
      switch (isThisATest ? platform : defaultTargetPlatform) {
        .linux => true,
        _ => false,
      };
  bool get usesMaterialByDefault =>
      !usesCupertinoByDefault && !usesYaruByDefault;

  static const cupertinoDirectionIcons = [
    CupertinoIcons.arrow_up_to_line,
    CupertinoIcons.arrow_right_to_line,
    CupertinoIcons.arrow_down_to_line,
    CupertinoIcons.arrow_left_to_line,
  ];
  static const materialDirectionIcons = [
    Icons.north,
    Icons.east,
    Icons.south,
    Icons.west,
  ];

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    platform = Theme.of(context).platform;
    final cupertino = platform.isCupertino;

    final requiresManualUpdates = FlavorConfig.appStore.isEmpty;

    final materialIcon = switch (defaultTargetPlatform) {
      .windows => FontAwesomeIcons.windows,
      _ => Icons.android,
    };

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const .only(bottom: 8),
            sliver: SliverAppBar(
              collapsedHeight: kToolbarHeight,
              expandedHeight: 200,
              pinned: true,
              scrolledUnderElevation: 1,
              flexibleSpace: FlexibleSpaceBar(
                title: Text(
                  t.home.titles.settings,
                  style: TextStyle(color: colorScheme.onSurface),
                ),
                centerTitle: false,
                titlePadding: const EdgeInsetsDirectional.only(
                  start: 16,
                  bottom: 16,
                ),
              ),
              actions: [
                if (UpdateManager.status.value != .upToDate)
                  IconButton(
                    tooltip: t.home.tooltips.showUpdateDialog,
                    icon: const Icon(Icons.system_update),
                    onPressed: () {
                      UpdateManager.showUpdateDialog(
                        context,
                        userTriggered: true,
                      );
                    },
                  ),
              ],
            ),
          ),
          SliverSafeArea(
            sliver: SliverList.list(
              children: [
                const NextcloudProfile(),
                const Padding(padding: .all(8), child: AppInfo()),
                SettingsSubtitle(subtitle: t.settings.prefCategories.general),
                SettingsDropdown(
                  title: t.settings.prefLabels.locale,
                  icon: cupertino ? CupertinoIcons.globe : Icons.language,
                  pref: stows.locale,
                  options: [
                    ToggleButtonsOption('', Text(t.settings.systemLanguage)),
                    ...AppLocaleUtils.supportedLocales.map((locale) {
                      final localeCode = locale.toLanguageTag();
                      final localeName = localeNames[localeCode];
                      assert(
                        localeName != null,
                        'Missing locale name for $localeCode',
                      );
                      return ToggleButtonsOption(
                        localeCode,
                        Text(localeName ?? localeCode),
                      );
                    }),
                  ],
                ),
                SettingsSelection(
                  title: t.settings.prefLabels.appTheme,
                  iconBuilder: (i) {
                    if (i == ThemeMode.system.index)
                      return Icons.brightness_auto;
                    if (i == ThemeMode.light.index) return Icons.light_mode;
                    if (i == ThemeMode.dark.index) return Icons.dark_mode;
                    return null;
                  },
                  pref: _SettingsStows.appTheme,
                  optionsWidth: 60,
                  options: [
                    ToggleButtonsOption(
                      ThemeMode.system.index,
                      Icon(
                        Icons.brightness_auto,
                        semanticLabel: t.settings.themeModes.system,
                      ),
                    ),
                    ToggleButtonsOption(
                      ThemeMode.light.index,
                      Icon(
                        Icons.light_mode,
                        semanticLabel: t.settings.themeModes.light,
                      ),
                    ),
                    ToggleButtonsOption(
                      ThemeMode.dark.index,
                      Icon(
                        Icons.dark_mode,
                        semanticLabel: t.settings.themeModes.dark,
                      ),
                    ),
                  ],
                ),
                SettingsSelection(
                  title: t.settings.prefLabels.platform,
                  iconBuilder: (i) => switch (stows.platform.value) {
                    .iOS || .macOS => Icons.apple,
                    .linux => FontAwesomeIcons.ubuntu,
                    _ => materialIcon,
                  },
                  pref: _SettingsStows.platform,
                  optionsWidth: 60,
                  options: [
                    ToggleButtonsOption(() {
                      if (usesMaterialByDefault)
                        return defaultTargetPlatform.index;
                      return TargetPlatform.android.index;
                    }(), UniIcon(materialIcon, semanticLabel: 'Material')),
                    ToggleButtonsOption(() {
                      // Hack to allow screenshot golden tests
                      if (kDebugMode && stows.platform.value.isCupertino)
                        return stows.platform.value.index;
                      if (usesCupertinoByDefault)
                        return defaultTargetPlatform.index;
                      return TargetPlatform.iOS.index;
                    }(), const Icon(Icons.apple, semanticLabel: 'Cupertino')),
                    ToggleButtonsOption(
                      () {
                        if (usesYaruByDefault)
                          return defaultTargetPlatform.index;
                        return TargetPlatform.linux.index;
                      }(),
                      const UniIcon(
                        FontAwesomeIcons.ubuntu,
                        semanticLabel: 'Yaru',
                      ),
                    ),
                  ],
                ),
                SettingsSelection(
                  title: t.settings.prefLabels.layoutSize,
                  subtitle: switch (stows.layoutSize.value) {
                    .auto => t.settings.layoutSizes.auto,
                    .phone => t.settings.layoutSizes.phone,
                    .tablet => t.settings.layoutSizes.tablet,
                  },
                  afterChange: (_) => setState(() {}),
                  iconBuilder: (i) => switch (LayoutSize.values[i]) {
                    .auto => Icons.aspect_ratio,
                    .phone => Icons.smartphone,
                    .tablet => Icons.tablet,
                  },
                  pref: _SettingsStows.layoutSize,
                  optionsWidth: 60,
                  options: [
                    ToggleButtonsOption(
                      LayoutSize.auto.index,
                      Icon(
                        Icons.aspect_ratio,
                        semanticLabel: t.settings.layoutSizes.auto,
                      ),
                    ),
                    ToggleButtonsOption(
                      LayoutSize.phone.index,
                      Icon(
                        Icons.smartphone,
                        semanticLabel: t.settings.layoutSizes.phone,
                      ),
                    ),
                    ToggleButtonsOption(
                      LayoutSize.tablet.index,
                      Icon(
                        Icons.tablet,
                        semanticLabel: t.settings.layoutSizes.tablet,
                      ),
                    ),
                  ],
                ),
                SettingsColor(
                  title: t.settings.prefLabels.customAccentColor,
                  icon: Icons.colorize,
                  pref: stows.accentColor,
                ),
                SettingsSwitch(
                  title: t.settings.prefLabels.hyperlegibleFont,
                  subtitle: t.settings.prefDescriptions.hyperlegibleFont,
                  iconBuilder: (b) {
                    if (b)
                      return cupertino
                          ? CupertinoIcons.textformat
                          : Icons.font_download;
                    return cupertino
                        ? CupertinoIcons.textformat_alt
                        : Icons.font_download_off;
                  },
                  pref: stows.hyperlegibleFont,
                ),

                SettingsSubtitle(subtitle: t.settings.prefCategories.writing),
                SettingsSwitch(
                  title: t.settings.prefLabels.preferGreyscale,
                  subtitle: t.settings.prefDescriptions.preferGreyscale,
                  iconBuilder: (b) {
                    return b
                        ? Icons.monochrome_photos
                        : Icons.enhance_photo_translate;
                  },
                  pref: stows.preferGreyscale,
                ),
                SettingsSwitch(
                  title: t.settings.prefLabels.autoClearWhiteboardOnExit,
                  subtitle:
                      t.settings.prefDescriptions.autoClearWhiteboardOnExit,
                  icon: Icons.cleaning_services,
                  pref: stows.autoClearWhiteboardOnExit,
                ),
                SettingsSwitch(
                  title: t.settings.prefLabels.disableEraserAfterUse,
                  subtitle: t.settings.prefDescriptions.disableEraserAfterUse,
                  icon: FontAwesomeIcons.eraser,
                  pref: stows.disableEraserAfterUse,
                ),
                ValueListenableBuilder(
                  valueListenable: stows.hideFingerDrawingToggle,
                  builder: (context, _, _) {
                    return SettingsSwitch(
                      title: t.settings.prefLabels.hideFingerDrawingToggle,
                      subtitle: () {
                        if (!stows.hideFingerDrawingToggle.value) {
                          return t
                              .settings
                              .prefDescriptions
                              .hideFingerDrawing
                              .shown;
                        } else if (stows.editorFingerDrawing.value) {
                          return t
                              .settings
                              .prefDescriptions
                              .hideFingerDrawing
                              .fixedOn;
                        } else {
                          return t
                              .settings
                              .prefDescriptions
                              .hideFingerDrawing
                              .fixedOff;
                        }
                      }(),
                      icon: CupertinoIcons.hand_draw_fill,
                      pref: stows.hideFingerDrawingToggle,
                    );
                  },
                ),
                ValueListenableBuilder(
                  valueListenable: stows.hideFingerDrawingToggle,
                  builder: (context, hideFingerDrawing, _) {
                    return Collapsible(
                      collapsed: hideFingerDrawing,
                      axis: CollapsibleAxis.vertical,
                      child: SettingsSwitch(
                        title: t
                            .settings
                            .prefLabels
                            .autoDisableFingerDrawingWhenStylusDetected,
                        subtitle: t
                            .settings
                            .prefDescriptions
                            .autoDisableFingerDrawingWhenStylusDetected,
                        icon: CupertinoIcons.pencil,
                        pref: stows.autoDisableFingerDrawingWhenStylusDetected,
                      ),
                    );
                  },
                ),

                SettingsSubtitle(
                  subtitle: t.settings.prefCategories.aiOutline,
                ),
                // API Key：只存在本机，不写进笔记文件
                SettingsTextInput(
                  title: t.settings.prefLabels.aiApiKey,
                  subtitle: t.settings.prefDescriptions.aiApiKey,
                  icon: Icons.key_outlined,
                  pref: stows.aiApiKey,
                  obscureText: true,
                  hintText: 'sk-...',
                ),
                SettingsTextInput(
                  title: t.settings.prefLabels.aiBaseUrl,
                  subtitle: t.settings.prefDescriptions.aiBaseUrl,
                  icon: Icons.link,
                  pref: stows.aiBaseUrl,
                  keyboardType: TextInputType.url,
                  hintText: Stows.defaultAiBaseUrl,
                ),
                SettingsTextInput(
                  title: t.settings.prefLabels.aiModel,
                  subtitle: t.settings.prefDescriptions.aiModel,
                  icon: Icons.smart_toy_outlined,
                  pref: stows.aiModel,
                  hintText: Stows.defaultAiModel,
                ),
                SettingsTextInput(
                  title: t.settings.prefLabels.aiPagesPerBatch,
                  subtitle: t.settings.prefDescriptions.aiPagesPerBatch,
                  icon: Icons.layers_outlined,
                  pref: _SettingsStows.aiPagesPerBatch,
                  keyboardType: TextInputType.number,
                ),
                SettingsTextInput(
                  title: t.settings.prefLabels.aiRenderLongSide,
                  subtitle: t.settings.prefDescriptions.aiRenderLongSide,
                  icon: Icons.photo_size_select_large_outlined,
                  pref: _SettingsStows.aiRenderLongSide,
                  keyboardType: TextInputType.number,
                ),

                SettingsSubtitle(
                  subtitle: t.settings.prefCategories.infiniteCanvas,
                ),
                // 背景颜色：点开可以选任意颜色（默认米白）
                SettingsColor(
                  title: t.settings.prefLabels.infiniteCanvasColor,
                  icon: Icons.palette_outlined,
                  pref: stows.infiniteCanvasColor,
                ),
                // 背景格式：无 / 方格 / 点阵
                SettingsSelection(
                  title: t.settings.prefLabels.infiniteCanvasPattern,
                  pref: _SettingsStows.infiniteCanvasPattern,
                  optionsWidth: 96,
                  options: [
                    ToggleButtonsOption(
                      CanvasBackgroundPattern.none.index,
                      Text(t.settings.infiniteCanvasPatterns.none),
                    ),
                    ToggleButtonsOption(
                      CanvasBackgroundPattern.grid.index,
                      Text(t.settings.infiniteCanvasPatterns.grid),
                    ),
                    ToggleButtonsOption(
                      CanvasBackgroundPattern.dots.index,
                      Text(t.settings.infiniteCanvasPatterns.dots),
                    ),
                  ],
                ),
                // 背景纹理：光滑 / 纸张
                SettingsSelection(
                  title: t.settings.prefLabels.infiniteCanvasTexture,
                  pref: _SettingsStows.infiniteCanvasTexture,
                  optionsWidth: 96,
                  options: [
                    ToggleButtonsOption(
                      CanvasTexture.smooth.index,
                      Text(t.settings.infiniteCanvasTextures.smooth),
                    ),
                    ToggleButtonsOption(
                      CanvasTexture.paper.index,
                      Text(t.settings.infiniteCanvasTextures.paper),
                    ),
                  ],
                ),
                // 方格／点阵的疏密：数字越小越密
                SettingsSelection<double>(
                  title: t.settings.prefLabels.gridDensity,
                  subtitle: t.settings.prefDescriptions.gridDensity,
                  icon: Icons.grid_on,
                  pref: stows.gridDensity,
                  options: const <ToggleButtonsOption<double>>[
                    ToggleButtonsOption(0.5, Text('0.5×')),
                    ToggleButtonsOption(0.7, Text('0.7×')),
                    ToggleButtonsOption(1.0, Text('1×')),
                    ToggleButtonsOption(1.5, Text('1.5×')),
                  ],
                ),

                SettingsSubtitle(subtitle: t.settings.prefCategories.editor),
                SettingsSelection<double>(
                  title: t.settings.prefLabels.textBoxOpacity,
                  subtitle: t.settings.prefDescriptions.textBoxOpacity,
                  icon: Icons.opacity,
                  pref: stows.textBoxOpacity,
                  options: const <ToggleButtonsOption<double>>[
                    ToggleButtonsOption(0.0, Text('0%')),
                    ToggleButtonsOption(0.3, Text('30%')),
                    ToggleButtonsOption(0.6, Text('60%')),
                    ToggleButtonsOption(0.9, Text('90%')),
                  ],
                ),
                SettingsSelection(
                  title: t.settings.prefLabels.editorToolbarAlignment,
                  subtitle:
                      t.settings.axisDirections[_SettingsStows
                          .editorToolbarAlignment
                          .value],
                  iconBuilder: (num i) {
                    if (i is! int || i >= materialDirectionIcons.length)
                      return null;
                    return cupertino
                        ? cupertinoDirectionIcons[i]
                        : materialDirectionIcons[i];
                  },
                  pref: _SettingsStows.editorToolbarAlignment,
                  optionsWidth: 60,
                  options: [
                    for (final AxisDirection direction in AxisDirection.values)
                      ToggleButtonsOption(
                        direction.index,
                        Icon(
                          cupertino
                              ? cupertinoDirectionIcons[direction.index]
                              : materialDirectionIcons[direction.index],
                          semanticLabel:
                              t.settings.axisDirections[direction.index],
                        ),
                      ),
                  ],
                  afterChange: (_) => setState(() {}),
                ),
                SettingsSwitch(
                  title: t.settings.prefLabels.editorToolbarShowInFullscreen,
                  icon: cupertino
                      ? CupertinoIcons.fullscreen
                      : Icons.fullscreen,
                  pref: stows.editorToolbarShowInFullscreen,
                ),
                SettingsSwitch(
                  title: t.settings.prefLabels.editorAutoInvert,
                  iconBuilder: (b) {
                    return b ? Icons.invert_colors_on : Icons.invert_colors_off;
                  },
                  pref: stows.editorAutoInvert,
                ),
                SettingsSwitch(
                  title: t.settings.prefLabels.editorPromptRename,
                  subtitle: t.settings.prefDescriptions.editorPromptRename,
                  iconBuilder: (b) {
                    if (b)
                      return cupertino
                          ? CupertinoIcons.keyboard
                          : Icons.keyboard;
                    return cupertino
                        ? CupertinoIcons.keyboard_chevron_compact_down
                        : Icons.keyboard_hide;
                  },
                  pref: stows.editorPromptRename,
                ),
                SettingsSwitch(
                  title: t.settings.prefLabels.recentColorsDontSavePresets,
                  icon: Icons.palette,
                  pref: stows.recentColorsDontSavePresets,
                ),
                SettingsSelection(
                  title: t.settings.prefLabels.recentColorsLength,
                  icon: Icons.history,
                  pref: stows.recentColorsLength,
                  options: const [
                    ToggleButtonsOption(5, Text('5')),
                    ToggleButtonsOption(10, Text('10')),
                  ],
                ),
                SettingsSwitch(
                  title: t.settings.prefLabels.printPageIndicators,
                  subtitle: t.settings.prefDescriptions.printPageIndicators,
                  icon: Icons.numbers,
                  pref: stows.printPageIndicators,
                ),
                SettingsSubtitle(
                  subtitle: t.settings.prefCategories.performance,
                ),
                SettingsSelection(
                  title: t.settings.prefLabels.maxImageSize,
                  subtitle: t.settings.prefDescriptions.maxImageSize,
                  icon: Icons.photo_size_select_large,
                  pref: stows.maxImageSize,
                  options: const <ToggleButtonsOption<double>>[
                    ToggleButtonsOption(500, Text('500')),
                    ToggleButtonsOption(1000, Text('1000')),
                    ToggleButtonsOption(2000, Text('2000')),
                  ],
                ),
                SettingsSelection(
                  title: t.settings.prefLabels.autosave,
                  subtitle: t.settings.prefDescriptions.autosave,
                  icon: Icons.save,
                  pref: stows.autosaveDelay,
                  options: [
                    const ToggleButtonsOption(5000, Text('5s')),
                    const ToggleButtonsOption(10000, Text('10s')),
                    ToggleButtonsOption(-1, Text(t.settings.autosaveDisabled)),
                  ],
                ),
                SettingsSelection(
                  title: t.settings.prefLabels.shapeRecognitionDelay,
                  subtitle: t.settings.prefDescriptions.shapeRecognitionDelay,
                  icon: FontAwesomeIcons.shapes,
                  pref: stows.shapeRecognitionDelay,
                  options: [
                    const ToggleButtonsOption(500, Text('0.5s')),
                    const ToggleButtonsOption(1000, Text('1s')),
                    ToggleButtonsOption(
                      -1,
                      Text(t.settings.shapeRecognitionDisabled),
                    ),
                  ],
                  afterChange: (ms) {
                    ShapePen.debounceDuration = ShapePen.getDebounceFromPref();
                  },
                ),
                SettingsSwitch(
                  title: t.settings.prefLabels.autoStraightenLines,
                  subtitle: t.settings.prefDescriptions.autoStraightenLines,
                  icon: Icons.straighten,
                  pref: stows.autoStraightenLines,
                ),
                SettingsSubtitle(subtitle: t.settings.prefCategories.advanced),
                if (isSentryAvailable) const SettingsSentryConsent(),
                if (Platform.isAndroid)
                  SettingsDirectorySelector(
                    title: t.settings.prefLabels.customDataDir,
                    icon: Icons.folder,
                  ),
                if (Platform.isWindows || Platform.isLinux || Platform.isMacOS)
                  SettingsButton(
                    title: t.settings.openDataDir,
                    icon: Icons.folder_open,
                    onPressed: () {
                      if (Platform.isWindows) {
                        Process.run('explorer', [
                          FileManager.documentsDirectory,
                        ]);
                      } else if (Platform.isLinux) {
                        Process.run('xdg-open', [
                          FileManager.documentsDirectory,
                        ]);
                      } else if (Platform.isMacOS) {
                        Process.run('open', [FileManager.documentsDirectory]);
                      }
                    },
                  ),
                if (requiresManualUpdates ||
                    stows.shouldCheckForUpdates.value !=
                        stows.shouldCheckForUpdates.defaultValue) ...[
                  SettingsSwitch(
                    title: t.settings.prefLabels.shouldCheckForUpdates,
                    icon: Icons.system_update,
                    pref: stows.shouldCheckForUpdates,
                    afterChange: (_) => setState(() {}),
                  ),
                  Collapsible(
                    collapsed: !stows.shouldCheckForUpdates.value,
                    axis: CollapsibleAxis.vertical,
                    child: SettingsSwitch(
                      title: t.settings.prefLabels.shouldAlwaysAlertForUpdates,
                      subtitle: t
                          .settings
                          .prefDescriptions
                          .shouldAlwaysAlertForUpdates,
                      icon: Icons.system_security_update_warning,
                      pref: stows.shouldAlwaysAlertForUpdates,
                    ),
                  ),
                ],
                SettingsSwitch(
                  title: t.settings.prefLabels.allowInsecureConnections,
                  subtitle:
                      t.settings.prefDescriptions.allowInsecureConnections,
                  icon: Icons.private_connectivity,
                  pref: stows.allowInsecureConnections,
                ),
                SettingsButton(
                  title: t.logs.viewLogs,
                  subtitle: t.logs.debuggingInfo,
                  icon: Icons.receipt_long,
                  onPressed: () => context.push(RoutePaths.logs),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    stows.locale.removeListener(onChanged);
    UpdateManager.status.removeListener(onChanged);
    super.dispose();
  }
}
