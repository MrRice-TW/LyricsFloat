import 'dart:convert';
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
    expect(calls, 5); // Each service backs off independently.
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
        enabledSources: {OnlineLyricsSource.lrclib, OnlineLyricsSource.amll},
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
      await lookup.find(
        title: '晴天',
        artist: '周杰倫',
        durationMs: 180000,
        enabledSources: {OnlineLyricsSource.lrclib, OnlineLyricsSource.amll},
      ),
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
        enabledSources: {OnlineLyricsSource.lrclib, OnlineLyricsSource.amll},
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
        enabledSources: {
          OnlineLyricsSource.lrclib,
          OnlineLyricsSource.amll,
          OnlineLyricsSource.lrcApi,
        },
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

  test('Netease Cloud Music finds synced lyrics with noisy YouTube metadata', () async {
    final lookup = OnlineLyricsLookup(
      request: (uri) async {
        if (uri.path == '/api/search/get/web') {
          return const LookupResponse(200, {
            'result': {
              'songs': [
                {
                  'id': 186016,
                  'name': '晴天',
                  'artists': [{'name': '周杰伦'}],
                  'album': {'name': '叶惠美'},
                  'duration': 269000,
                },
              ],
            },
          });
        }
        expect(uri.path, '/api/song/lyric');
        expect(uri.queryParameters['id'], '186016');
        return const LookupResponse(200, {
          'lrc': {
            'lyric': '[00:00.00]晴天 - 周杰伦\n[00:12.50]故事的小黄花\n[04:20.00]从前从前',
          },
        });
      },
    );

    final found = await lookup.find(
      title: '周杰倫 Jay Chou【晴天 Sunny Day】Official MV',
      artist: '周杰倫 & 溫嵐',
      durationMs: 270000,
      enabledSources: {OnlineLyricsSource.netease},
    );
    expect(found?.source, '網易雲音樂');
    expect(found?.providerId, '186016');
    expect(found?.title, '晴天');
    expect(found?.artist, '周杰伦');
    expect(found?.lrc, contains('[00:12.50]故事的小黄花'));
  });

  test('accepts matches within the relaxed duration tolerance (e.g. 7 seconds diff)', () async {
    final lookup = OnlineLyricsLookup(
      request: (uri) async {
        return LookupResponse(200, [
          result(101, 'Example Song', 'Singer', 187, '[00:01.00]Matched with 7s difference'),
        ]);
      },
    );

    final found = await lookup.find(
      title: 'Example Song (Official MV)',
      artist: 'Singer',
      durationMs: 180000,
      enabledSources: {OnlineLyricsSource.lrclib},
    );
    expect(found?.providerId, '101');
    expect(found?.lrc, contains('Matched with 7s difference'));
  });

  test('findAll returns multiple candidates across sources for manual review', () async {
    final lookup = OnlineLyricsLookup(
      request: (uri) async {
        if (uri.host == 'music.163.com') {
          if (uri.path == '/api/search/get/web') {
            return const LookupResponse(200, {
              'result': {
                'songs': [
                  {
                    'id': 1,
                    'name': 'Song',
                    'artists': [{'name': 'Singer'}],
                    'album': {'name': 'Album 1'},
                    'duration': 180000,
                  },
                ],
              },
            });
          }
          return const LookupResponse(200, {
            'lrc': {'lyric': '[00:01.00]Netease lyric'},
          });
        }
        if (uri.host == 'lrclib.net') {
          return LookupResponse(200, [
            result(2, 'Song', 'Singer', 180, '[00:01.00]LRCLIB lyric'),
          ]);
        }
        return const LookupResponse(404, null);
      },
    );

    final candidates = await lookup.findAll(
      title: 'Song',
      artist: 'Singer',
      durationMs: 180000,
      enabledSources: {OnlineLyricsSource.netease, OnlineLyricsSource.lrclib},
    );
    expect(candidates.length, 2);
    expect(candidates[0].source, '網易雲音樂');
    expect(candidates[1].source, 'LRCLIB');
  });

  test('Kugou Music finds synced lyrics with base64 decoding and duration matching', () async {
    final lookup = OnlineLyricsLookup(
      request: (uri) async {
        if (uri.host == 'lyrics.kugou.com') {
          if (uri.path == '/search') {
            return const LookupResponse(200, {
              'status': 200,
              'candidates': [
                {
                  'id': '669844209',
                  'accesskey': '324C7937411FA809A524EC704E029001',
                  'song': '晴天',
                  'singer': '周杰伦',
                  'duration': 270000,
                },
              ],
            });
          }
          if (uri.path == '/download') {
            final lrcContent = '[00:01.00]故事的小黃花\n[00:05.00]從出生那年就飄著\n[00:10.00]童年的蕩鞦韆';
            return LookupResponse(200, {
              'status': 200,
              'content': base64Encode(utf8.encode(lrcContent)),
            });
          }
        }
        return const LookupResponse(404, null);
      },
    );

    final found = await lookup.find(
      title: '晴天',
      artist: '周杰倫',
      durationMs: 270000,
      enabledSources: {OnlineLyricsSource.kugou},
    );
    expect(found?.source, '酷狗音樂');
    expect(found?.providerId, '669844209');
    expect(found?.title, '晴天');
    expect(found?.artist, '周杰伦');
    expect(found?.lrc, contains('[00:01.00]故事的小黃花'));
  });

  test('matches artist alias Joey Yung and 容祖儿', () async {
    final lookup = OnlineLyricsLookup(
      request: (uri) async {
        if (uri.host == 'lrclib.net') {
          return LookupResponse(200, [
            result(8065028, '就让这大雨全都落下', 'Joey Yung', 254, '[00:01.00]就让这大雨全都落下'),
          ]);
        }
        return const LookupResponse(404, null);
      },
    );

    final found = await lookup.find(
      title: '就让这大雨全都落下',
      artist: '容祖兒',
      durationMs: 254000,
      enabledSources: {OnlineLyricsSource.lrclib},
    );
    expect(found?.source, 'LRCLIB');
    expect(found?.providerId, '8065028');
    expect(found?.lrc, contains('就让这大雨全都落下'));
  });

  test('matches when specific long title matches tightly and remote title mentions creator/artist', () async {
    final lookup = OnlineLyricsLookup(
      request: (uri) async {
        if (uri.host == 'lrclib.net') {
          return LookupResponse(200, [
            result(
              36672211,
              '就让这大雨全都落下 (汪苏泷概念创作集《联名》作品)',
              '容祖儿',
              254,
              '[00:01.00]就让这大雨全都落下',
            ),
          ]);
        }
        return const LookupResponse(404, null);
      },
    );

    final found = await lookup.find(
      title: '就让这大雨全都落下',
      artist: '汪苏泷',
      durationMs: 254000,
      enabledSources: {OnlineLyricsSource.lrclib},
    );
    expect(found?.source, 'LRCLIB');
    expect(found?.providerId, '36672211');
    expect(found?.lrc, contains('就让这大雨全都落下'));
  });

  test('findAll with durationMs: 0 returns all title matches without duration filtering', () async {
    final lookup = OnlineLyricsLookup(
      request: (uri) async {
        if (uri.host == 'lrclib.net') {
          if (uri.path == '/api/get') return const LookupResponse(404, null);
          return LookupResponse(200, [
            result(1, '就让这大雨全都落下', '容祖儿', 254, '[00:01.00]Version A'),
            result(2, '就让这大雨全都落下', '郑润泽', 217, '[00:01.00]Version B'),
          ]);
        }
        return const LookupResponse(404, null);
      },
    );

    final candidates = await lookup.findAll(
      title: '就让这大雨全都落下',
      artist: '',
      durationMs: 0,
      enabledSources: {OnlineLyricsSource.lrclib},
    );
    expect(candidates.length, 2);
    expect(candidates.map((c) => c.artist), ['容祖儿', '郑润泽']);
  });

  test('fallback duration proximity matching picks the closest duration candidate', () async {
    final lookup = OnlineLyricsLookup(
      request: (uri) async {
        if (uri.host == 'lrclib.net' && uri.path == '/api/search') {
          if (uri.queryParameters['artist_name'] == 'Channel X') {
            return const LookupResponse(200, []);
          }
          if (uri.queryParameters['q'] == '就让这大雨全都落下') {
            return LookupResponse(200, [
              result(1, '就让这大雨全都落下', '容祖儿', 254, '[00:01.00]Version Joey'),
              result(2, '就让这大雨全都落下', '郑润泽', 217, '[00:01.00]Version Zheng'),
            ]);
          }
        }
        return const LookupResponse(404, null);
      },
    );

    // Initial search with mismatched artist 'Channel X' returns nothing
    final initial = await lookup.find(
      title: '就让这大雨全都落下',
      artist: 'Channel X',
      durationMs: 254000,
      enabledSources: {OnlineLyricsSource.lrclib},
    );
    expect(initial, isNull);

    // Stage 2 fallback with empty artist and duration proximity filtering
    final candidates = await lookup.findAll(
      title: '就让这大雨全都落下',
      artist: '',
      durationMs: 0,
      enabledSources: {OnlineLyricsSource.lrclib},
    );
    final closeMatches = candidates.where((c) {
      if (c.durationMs <= 0) return false;
      return (c.durationMs - 254000).abs() <= 5000;
    }).toList();
    closeMatches.sort((a, b) =>
        (a.durationMs - 254000).abs().compareTo(
            (b.durationMs - 254000).abs()));

    expect(closeMatches, isNotEmpty);
    expect(closeMatches.first.artist, '容祖儿');
    expect(closeMatches.first.lrc, contains('Version Joey'));
  });
}

