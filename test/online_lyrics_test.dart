import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyrics_float/online_lyrics.dart';

Map<String, Object> result(
  int id,
  String title,
  String artist,
  double duration,
  String lyrics,
) => {
  'id': id,
  'trackName': title,
  'artistName': artist,
  'duration': duration,
  'syncedLyrics': lyrics,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('accepts timed lyrics for the same track and duration', () async {
    final lookup = OnlineLyricsLookup(
      request: (uri) async {
        expect(uri.path, '/api/get');
        expect(uri.queryParameters['duration'], '180');
        return LookupResponse(
          200,
          result(
            12,
            'Example',
            'Singer',
            180.3,
            '[00:01.00]Line one\n[00:03.00]Line two',
          ),
        );
      },
    );

    final found = await lookup.find(
      title: 'Example',
      artist: 'Singer',
      durationMs: 180000,
    );
    expect(found?.providerId, '12');
    expect(found?.lrc, contains('[00:03.00]'));
    expect(found?.source, 'LRCLIB');
  });

  test(
    'finds a Traditional Chinese LRCLIB record for Chrome Topic metadata',
    () async {
      final requests = <Uri>[];
      final lookup = OnlineLyricsLookup(
        request: (uri) async {
          requests.add(uri);
          if (uri.path == '/api/get') return const LookupResponse(404, null);
          if (uri.queryParameters['track_name'] == '路过的风景') {
            return const LookupResponse(200, []);
          }
          expect(uri.queryParameters['track_name'], '路過的風景');
          expect(uri.queryParameters['artist_name'], 'JBMS大熊');
          return LookupResponse(200, [
            result(97, '路過的風景', 'JBMS大熊', 237, '[00:01.00]第一句\n[03:40.00]最後一句'),
          ]);
        },
      );
      final found = await lookup.find(
        title: '路过的风景',
        artist: 'JBMS大熊 - Topic',
        durationMs: 237000,
        enabledSources: {OnlineLyricsSource.lrclib},
      );
      expect(found?.source, 'LRCLIB');
      expect(found?.artist, 'JBMS大熊');
      expect(requests.length, 3);
    },
  );

  test(
    'LRCLIB search runs if exact lookup rejects incomplete metadata',
    () async {
      final lookup = OnlineLyricsLookup(
        request: (uri) async {
          if (uri.path == '/api/get') return const LookupResponse(400, null);
          return LookupResponse(200, [
            result(99, 'Example', 'Singer', 180, '[00:01.00]Found'),
          ]);
        },
      );
      expect(
        (await lookup.find(
          title: 'Example',
          artist: 'Singer',
          durationMs: 180000,
          enabledSources: {OnlineLyricsSource.lrclib},
        ))?.providerId,
        '99',
      );
    },
  );

  test(
    'manual search returns a candidate from each available source',
    () async {
      final lookup = OnlineLyricsLookup(
        request: (uri) async {
          if (uri.path == '/api/get') return const LookupResponse(404, null);
          if (uri.host == 'lrclib.net') {
            return LookupResponse(200, [
              result(1, 'Example', 'Singer', 180, '[00:01.00]LRCLIB'),
            ]);
          }
          return LookupResponse(200, [
            result(2, 'Example', 'Singer', 170, '[00:01.00]AMLL'),
          ]);
        },
      );
      final candidates = await lookup.findAll(
        title: 'Example',
        artist: 'Singer',
        durationMs: 0,
        enabledSources: {OnlineLyricsSource.lrclib, OnlineLyricsSource.amll},
      );
      expect(candidates.map((candidate) => candidate.source), [
        'LRCLIB',
        'AMLL',
      ]);
    },
  );

  test('rejects a different version even if title and artist match', () async {
    final lookup = OnlineLyricsLookup(
      request: (uri) async {
        if (uri.path == '/api/get') {
          return LookupResponse(
            200,
            result(12, 'Example', 'Singer', 225, '[00:01.00]Wrong version'),
          );
        }
        return LookupResponse(200, [
          result(12, 'Example', 'Singer', 225, '[00:01.00]Wrong version'),
          result(13, 'Example (Live)', 'Singer', 180, '[00:01.00]Live'),
        ]);
      },
    );

    expect(
      await lookup.find(title: 'Example', artist: 'Singer', durationMs: 180000),
      isNull,
    );
  });

  test('does not guess between conflicting matches without duration', () async {
    final lookup = OnlineLyricsLookup(
      request: (uri) async {
        if (uri.path == '/api/get') return const LookupResponse(404, null);
        return LookupResponse(200, [
          result(12, 'Example', 'Singer', 180, '[00:01.00]First'),
          result(13, 'Example', 'Singer', 190, '[00:01.00]Second'),
        ]);
      },
    );

    expect(await lookup.find(title: 'Example', artist: 'Singer'), isNull);
  });

  test('backs off after rate limiting', () async {
    var calls = 0;
    final lookup = OnlineLyricsLookup(
      request: (uri) async {
        calls++;
        return const LookupResponse(
          429,
          null,
          retryAfter: Duration(minutes: 1),
        );
      },
    );

    expect(await lookup.find(title: 'Example', artist: 'Singer'), isNull);
    expect(await lookup.find(title: 'Another', artist: 'Singer'), isNull);
    expect(calls, 3); // Each service backs off independently.
  });

  test(
    'uses AMLL after LRCLIB misses, including Traditional Chinese names',
    () async {
      final requestedHosts = <String>[];
      final lookup = OnlineLyricsLookup(
        request: (uri) async {
          requestedHosts.add(uri.host);
          if (uri.host == 'lrclib.net') {
            return uri.path == '/api/get'
                ? const LookupResponse(404, null)
                : const LookupResponse(200, []);
          }
          expect(uri.path, '/v1/lrclib/search');
          expect(uri.queryParameters['track_name'], '晴天');
          return LookupResponse(200, [
            result(42, '晴天', '周杰伦', 155, '[00:01.00]第一句\n[02:35.00]最後一句'),
          ]);
        },
      );

      final found = await lookup.find(
        title: '晴天',
        artist: '周杰倫',
        durationMs: 180000,
      );
      expect(requestedHosts, ['lrclib.net', 'lrclib.net', 'api.amll.dev']);
      expect(found?.source, 'AMLL');
      expect(found?.providerId, '42');
      expect(found?.durationMs, 180000);
    },
  );

  test('does not apply AMLL lyrics from a different version', () async {
    final lookup = OnlineLyricsLookup(
      request: (uri) async {
        if (uri.host == 'lrclib.net') {
          return uri.path == '/api/get'
              ? const LookupResponse(404, null)
              : const LookupResponse(200, []);
        }
        return LookupResponse(200, [
          result(42, '晴天', '周杰伦', 240, '[04:00.00]遠超過歌曲長度'),
        ]);
      },
    );

    expect(
      await lookup.find(title: '晴天', artist: '周杰倫', durationMs: 180000),
      isNull,
    );
  });

  test('tries AMLL when LRCLIB is unavailable', () async {
    final lookup = OnlineLyricsLookup(
      request: (uri) async {
        if (uri.host == 'lrclib.net') throw const SocketException('offline');
        return LookupResponse(200, [
          result(42, 'Example', 'Singer', 155, '[02:35.00]Last line'),
        ]);
      },
    );

    expect(
      (await lookup.find(
        title: 'Example',
        artist: 'Singer',
        durationMs: 180000,
      ))?.source,
      'AMLL',
    );
  });

  test(
    'can search LrcAPI alone and accepts its string ID and LRC field',
    () async {
      final lookup = OnlineLyricsLookup(
        request: (uri) async {
          expect(uri.host, 'api.lrc.cx');
          expect(uri.path, '/jsonapi');
          expect(uri.queryParameters['title'], '晴天');
          return const LookupResponse(200, [
            {
              'id': 'lyric-hash',
              'title': '晴天',
              'artist': '周杰伦',
              'album': '叶惠美',
              'duration': 269.7,
              'lrc': '[00:01.00]第一句\n[04:22.00]最後一句',
            },
          ]);
        },
      );

      final found = await lookup.find(
        title: '晴天',
        artist: '周杰倫',
        durationMs: 270000,
        enabledSources: {OnlineLyricsSource.lrcApi},
      );
      expect(found?.source, 'LrcAPI');
      expect(found?.providerId, 'lyric-hash');
      expect(found?.album, '叶惠美');
    },
  );

  test('falls through LRCLIB and AMLL before trying LrcAPI', () async {
    final hosts = <String>[];
    final lookup = OnlineLyricsLookup(
      request: (uri) async {
        hosts.add(uri.host);
        if (uri.path == '/api/get') return const LookupResponse(404, null);
        if (uri.host != 'api.lrc.cx') return const LookupResponse(200, []);
        return const LookupResponse(200, [
          {
            'id': 'one',
            'title': 'Example',
            'artist': 'Singer',
            'duration': 180,
            'lrc': '[00:01.00]Line',
          },
        ]);
      },
    );

    expect(
      (await lookup.find(
        title: 'Example',
        artist: 'Singer',
        durationMs: 180000,
      ))?.source,
      'LrcAPI',
    );
    expect(hosts, ['lrclib.net', 'lrclib.net', 'api.amll.dev', 'api.lrc.cx']);
  });

  test('skips every online request when all sources are disabled', () async {
    final lookup = OnlineLyricsLookup(
      request: (_) async => throw StateError('Should not request'),
    );
    expect(
      await lookup.find(title: 'Example', artist: 'Singer', enabledSources: {}),
      isNull,
    );
  });

  test(
    'does not choose between conflicting LrcAPI lyrics without duration',
    () async {
      final lookup = OnlineLyricsLookup(
        request: (_) async => const LookupResponse(200, [
          {
            'id': 'a',
            'title': 'Example',
            'artist': 'Singer',
            'lrc': '[00:01.00]First',
          },
          {
            'id': 'b',
            'title': 'Example',
            'artist': 'Singer',
            'lrc': '[00:01.00]Second',
          },
        ]),
      );
      expect(
        await lookup.find(
          title: 'Example',
          artist: 'Singer',
          enabledSources: {OnlineLyricsSource.lrcApi},
        ),
        isNull,
      );
    },
  );

  test('Musixmatch verifies matched track before loading subtitles', () async {
    final paths = <String>[];
    final lookup = OnlineLyricsLookup(
      musixmatchApiKey: 'test-key',
      request: (uri) async {
        paths.add(uri.path);
        expect(uri.queryParameters['apikey'], 'test-key');
        if (uri.path.endsWith('matcher.track.get')) {
          return const LookupResponse(200, {
            'message': {
              'header': {'status_code': 200},
              'body': {
                'track': {
                  'track_id': 123,
                  'track_name': '晴天',
                  'artist_name': '周杰伦',
                  'track_length': 180,
                  'album_name': '叶惠美',
                },
              },
            },
          });
        }
        expect(uri.queryParameters['track_id'], '123');
        return const LookupResponse(200, {
          'message': {
            'header': {'status_code': 200},
            'body': {
              'subtitle': {'subtitle_body': '[00:01.00]第一句\n[02:40.00]最後一句'},
            },
          },
        });
      },
    );
    final found = await lookup.find(
      title: '晴天',
      artist: '周杰倫',
      durationMs: 180000,
      enabledSources: {OnlineLyricsSource.musixmatch},
    );
    expect(found?.source, 'Musixmatch');
    expect(found?.album, '叶惠美');
    expect(paths, ['/ws/1.1/matcher.track.get', '/ws/1.1/track.subtitle.get']);
  });

  test(
    'Musixmatch rejects a mismatched version without fetching lyrics',
    () async {
      var calls = 0;
      final lookup = OnlineLyricsLookup(
        musixmatchApiKey: 'test-key',
        request: (_) async {
          calls++;
          return const LookupResponse(200, {
            'message': {
              'header': {'status_code': 200},
              'body': {
                'track': {
                  'track_id': 123,
                  'track_name': 'Example',
                  'artist_name': 'Singer',
                  'track_length': 225,
                },
              },
            },
          });
        },
      );
      expect(
        await lookup.find(
          title: 'Example',
          artist: 'Singer',
          durationMs: 180000,
          enabledSources: {OnlineLyricsSource.musixmatch},
        ),
        isNull,
      );
      expect(calls, 1);
    },
  );

  test('Tencent Yinsuda converts the authorized VTT lyric', () async {
    final actions = <String>[];
    final lookup = OnlineLyricsLookup(
      tencentConfig: const TencentLyricsConfig(
        secretId: 'id',
        secretKey: 'key',
        appName: 'app',
        userId: 'user',
      ),
      tencentRequest: (action, payload) async {
        actions.add(action);
        expect(payload['AppName'], 'app');
        if (action == 'SearchKTVMusics') {
          return const LookupResponse(200, {
            'Response': {
              'KTVMusicInfoSet': [
                {
                  'MusicId': 'mid-1',
                  'Name': '晴天',
                  'SingerSet': ['周杰伦'],
                  'Duration': 180000,
                  'AlbumInfo': {'Name': '叶惠美'},
                },
              ],
            },
          });
        }
        expect(payload['MusicIds'], ['mid-1']);
        return const LookupResponse(200, {
          'Response': {
            'KTVMusicDetailInfoSet': [
              {
                'KTVMusicBaseInfo': {'MusicId': 'mid-1'},
                'LyricsUrl': 'https://example.com/download?token=abc',
              },
            ],
          },
        });
      },
      request: (uri) async {
        expect(uri.host, 'example.com');
        return const LookupResponse(
          200,
          'WEBVTT\n\n00:00:01.000 --> 00:00:03.000\n第一句\n\n00:02:40.000 --> 00:02:43.000\n最後一句',
        );
      },
    );
    final found = await lookup.find(
      title: '晴天',
      artist: '周杰倫',
      durationMs: 180000,
      enabledSources: {OnlineLyricsSource.tencentCloud},
    );
    expect(found?.source, '騰訊雲音速達');
    expect(found?.lrc, contains('[02:40.000]最後一句'));
    expect(actions, ['SearchKTVMusics', 'BatchDescribeKTVMusicDetails']);
  });
}
