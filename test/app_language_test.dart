import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyrics_float/app.dart';
import 'package:lyrics_float/app_language.dart';
import 'package:lyrics_float/search_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => appLanguage.value = AppLanguage.system);

  test('system language resolves to Chinese or English fallback', () {
    expect(
      resolveLanguage(AppLanguage.system, const Locale('zh', 'CN')),
      const Locale('zh', 'TW'),
    );
    expect(
      resolveLanguage(AppLanguage.system, const Locale('en', 'US')),
      const Locale('en'),
    );
    expect(
      resolveLanguage(AppLanguage.system, const Locale('ja')),
      const Locale('en'),
    );
    expect(
      resolveLanguage(AppLanguage.en, const Locale('zh')),
      const Locale('en'),
    );
    expect(
      resolveLanguage(AppLanguage.zhTW, const Locale('en')),
      const Locale('zh', 'TW'),
    );
  });

  test(
    'language persists and missing or invalid values follow system',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'lyrics-language-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/settings.json');
      final settings = SearchSettings(file);
      for (final language in AppLanguage.values) {
        settings.language = language;
        await settings.save();
        final loaded = SearchSettings(file);
        await loaded.load();
        expect(loaded.language, language);
      }
      for (final json in ['{}', '{"language":"invalid"}']) {
        await file.writeAsString(json);
        final loaded = SearchSettings(file);
        await loaded.load();
        expect(loaded.language, AppLanguage.system);
      }
    },
  );

  testWidgets('settings switch immediately and save language', (tester) async {
    final directory = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('lyrics-language-ui-'),
    ))!;
    final file = File('${directory.path}/search_settings.json');
    final settings = SearchSettings(file)..language = AppLanguage.en;
    await tester.runAsync(settings.save);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(native, (
      call,
    ) async {
      if (call.method == 'getStoragePath') return directory.path;
      return null;
    });
    addTearDown(() async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        native,
        null,
      );
      await directory.delete(recursive: true);
    });
    await tester.runAsync(() async {
      await tester.pumpWidget(const LyricsFloatApp());
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();
    await tester.runAsync(() async {
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Interface language'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('繁體中文'));
      await tester.pumpAndSettle();
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
    expect(find.byTooltip('設定'), findsOneWidget);
    final reloaded = SearchSettings(file);
    await tester.runAsync(reloaded.load);
    expect(reloaded.language, AppLanguage.zhTW);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
