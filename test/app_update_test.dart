import 'dart:io';
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyrics_float/app_update.dart';
import 'package:lyrics_float/search_settings.dart';
import 'package:pub_semver/pub_semver.dart';

Map<String, dynamic> release(
  String tag, {
  bool ready = true,
  bool draft = false,
  UpdatePlatform platform = UpdatePlatform.windows,
}) => {
  'tag_name': tag,
  'draft': draft,
  'prerelease': tag.contains('-'),
  'assets': ready
      ? [
          {'name': platform.assetName, 'state': 'uploaded', 'size': 100},
        ]
      : [],
};

void main() {
  test(
    'checks public API and closes client after success or API failure',
    () async {
      for (final status in [200, 403]) {
        final client = _Client(status, jsonEncode([release('v1.2.8')]));
        final checker = AppUpdateChecker(createClient: () => client);
        if (status == 200) {
          expect(
            (await checker.check(
              Version.parse('1.2.7'),
              platform: UpdatePlatform.windows,
            ))!.version.toString(),
            '1.2.8',
          );
        } else {
          await expectLater(
            checker.check(
              Version.parse('1.2.7'),
              platform: UpdatePlatform.windows,
            ),
            throwsA(isA<HttpException>()),
          );
        }
        expect(client.uri!.host, 'api.github.com');
        expect(client.uri!.path, '/repos/MrRice-TW/LyricsFloat/releases');
        expect(client.closed, isTrue);
      }
    },
  );
  test('orders versions numerically and ignores incomplete/draft releases', () {
    final result = selectAppUpdate(
      [
        release('v1.2.9'),
        release('v1.2.10'),
        release('v9.0.0', ready: false),
        release('v8.0.0', draft: true),
        release('not-a-version'),
        null,
      ],
      Version.parse('1.2.8'),
      platform: UpdatePlatform.windows,
    );
    expect(result!.version.toString(), '1.2.10');
    expect(
      result.page.toString(),
      'https://github.com/MrRice-TW/LyricsFloat/releases/tag/v1.2.10',
    );
  });

  test('beta builds see betas; stable builds ignore them', () {
    final releases = [release('v1.3.0-beta.2'), release('v1.2.7')];
    expect(
      selectAppUpdate(
        releases,
        Version.parse('1.2.7-beta'),
        platform: UpdatePlatform.windows,
      )!.version.toString(),
      '1.3.0-beta.2',
    );
    expect(
      selectAppUpdate(
        releases,
        Version.parse('1.2.7'),
        platform: UpdatePlatform.windows,
      ),
      isNull,
    );
    expect(
      selectAppUpdate(
        [release('v1.2.7')],
        Version.parse('1.2.7-beta'),
        platform: UpdatePlatform.windows,
      )!.version.toString(),
      '1.2.7',
    );
  });

  test(
    'same/older versions and invalid assets do not trigger a notification',
    () {
      final broken = release('v2.0.0');
      (broken['assets'] as List).first['state'] = 'new';
      expect(
        selectAppUpdate(
          [release('v1.2.7-beta'), release('v1.2.6'), broken],
          Version.parse('1.2.7-beta'),
          platform: UpdatePlatform.windows,
        ),
        isNull,
      );
    },
  );

  test('each platform requires its own uploaded package', () {
    for (final platform in UpdatePlatform.values) {
      expect(
        selectAppUpdate(
          [
            release('v1.2.10', platform: platform),
            ...UpdatePlatform.values
                .where((other) => other != platform)
                .map((other) => release('v9.0.0', platform: other)),
          ],
          Version.parse('1.2.9'),
          platform: platform,
        )!.version.toString(),
        '1.2.10',
      );
    }
  });

  test('startup preference defaults on and persists opt-out', () async {
    final directory = await Directory.systemTemp.createTemp(
      'lyrics-update-settings-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/settings.json');
    await file.writeAsString('{"enabledSources":["lrclib"]}');
    final settings = SearchSettings(file);
    await settings.load();
    expect(settings.checkUpdatesOnStartup, isTrue);
    settings.checkUpdatesOnStartup = false;
    await settings.save();
    final loaded = SearchSettings(file);
    await loaded.load();
    expect(loaded.checkUpdatesOnStartup, isFalse);
  });
}

class _Client implements HttpClient {
  _Client(this.status, this.body);
  final int status;
  final String body;
  Uri? uri;
  bool closed = false;
  @override
  Duration? connectionTimeout;
  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    uri = url;
    return _Request(status, body);
  }

  @override
  void close({bool force = false}) {
    closed = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Request implements HttpClientRequest {
  _Request(this.status, this.body);
  final int status;
  final String body;
  @override
  HttpHeaders get headers => _Headers();
  @override
  Future<HttpClientResponse> close() async => _Response(status, body);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Headers implements HttpHeaders {
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Response extends Stream<List<int>> implements HttpClientResponse {
  _Response(this.statusCode, this.body);
  @override
  final int statusCode;
  final String body;
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream.value(utf8.encode(body)).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
