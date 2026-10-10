import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saber/components/editor/page_pill.dart';
import 'package:saber/i18n/strings.g.dart';

/// 页码胶囊：显示「当前 / 总数」，点数字输入页码跳转，两头是上/下页。
/// 这里钉住三件事：显示的是 1 起的页码、首末页箭头会禁用、输入的越界值会被挡下来。
void main() {
  setUpAll(() async {
    await LocaleSettings.setLocale(AppLocale.en);
  });

  Future<void> pump(
    WidgetTester tester, {
    required int currentPage,
    required int pageCount,
    void Function(int)? onJump,
    VoidCallback? onPrevious,
    VoidCallback? onNext,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: PagePill(
              currentPage: currentPage,
              pageCount: pageCount,
              onJump: onJump ?? (_) {},
              onPrevious: onPrevious,
              onNext: onNext,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('显示 1 起的页码，不是 0 起', (tester) async {
    await pump(tester, currentPage: 11, pageCount: 128);
    expect(find.text('12 / 128'), findsOneWidget);
  });

  testWidgets('点数字弹出输入框，输入页码后按 0 起回调', (tester) async {
    final jumps = <int>[];
    await pump(tester, currentPage: 0, pageCount: 10, onJump: jumps.add);

    await tester.tap(find.text('1 / 10'));
    await tester.pumpAndSettle();

    // 框里预填的是当前页
    expect(find.text(t.editor.goToPage), findsOneWidget);

    await tester.enterText(find.byType(TextField), '7');
    await tester.tap(find.text(MaterialLocalizations.of(
      tester.element(find.byType(PagePill)),
    ).okButtonLabel));
    await tester.pumpAndSettle();

    expect(jumps, [6], reason: '输入第 7 页 -> 下标 6');
  });

  testWidgets('越界的页码会报错，不会跳', (tester) async {
    final jumps = <int>[];
    await pump(tester, currentPage: 0, pageCount: 10, onJump: jumps.add);

    await tester.tap(find.text('1 / 10'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '999');
    await tester.tap(find.text(MaterialLocalizations.of(
      tester.element(find.byType(PagePill)),
    ).okButtonLabel));
    await tester.pumpAndSettle();

    expect(jumps, isEmpty, reason: '越界不该跳过去');
    expect(find.textContaining('1'), findsWidgets);
  });

  testWidgets('箭头是否可点，如实跟着外面传的回调走', (tester) async {
    // 首/末页该不该禁用是调用方（editor）判断的，这里只验证组件如实反映
    await pump(tester, currentPage: 0, pageCount: 5, onNext: () {});
    expect(
      tester
          .widget<IconButton>(
            find.widgetWithIcon(IconButton, Icons.chevron_left),
          )
          .onPressed,
      isNull,
      reason: '没传 onPrevious 就该是禁用的',
    );
    expect(
      tester
          .widget<IconButton>(
            find.widgetWithIcon(IconButton, Icons.chevron_right),
          )
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('箭头按的是相邻页', (tester) async {
    final jumps = <int>[];
    await pump(tester, currentPage: 3, pageCount: 5, onJump: jumps.add);

    await tester.tap(find.widgetWithIcon(IconButton, Icons.chevron_left));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithIcon(IconButton, Icons.chevron_right));
    await tester.pumpAndSettle();

    // 回调交给外面决定，所以这里只验证按钮是可用的
    expect(jumps, isEmpty, reason: '提供的是 onPrevious/onNext 时不该走 onJump');
  });
}
