import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

import 'lyrics.dart';

enum OnlineLyricsSource {
  netease('網易雲音樂'),
  kugou('酷狗音樂'),
  lrclib('LRCLIB'),
  amll('AMLL'),
  lrcApi('LrcAPI'),
  musixmatch('Musixmatch'),
  tencentCloud('騰訊雲音速達');

  const OnlineLyricsSource(this.label);
  final String label;
}

const defaultOnlineLyricsSources = {
  OnlineLyricsSource.netease,
  OnlineLyricsSource.kugou,
  OnlineLyricsSource.lrclib,
  OnlineLyricsSource.amll,
  OnlineLyricsSource.lrcApi,
};

class OnlineLyrics {
  const OnlineLyrics({
    required this.lrc,
    required this.providerId,
    required this.title,
    required this.artist,
    required this.album,
    required this.durationMs,
    required this.source,
  });
  final String lrc;
  final String providerId;
  final String title;
  final String artist;
  final String album;
  final int durationMs;
  final String source;
}

class LookupResponse {
  const LookupResponse(this.status, this.body, {this.retryAfter});
  final int status;
  final Object? body;
  final Duration? retryAfter;
}

typedef LyricsRequest = Future<LookupResponse> Function(Uri uri);
typedef TencentRequest =
    Future<LookupResponse> Function(String action, Map<String, Object> payload);

class TencentLyricsConfig {
  const TencentLyricsConfig({
    required this.secretId,
    required this.secretKey,
    required this.appName,
    required this.userId,
  });

  final String secretId;
  final String secretKey;
  final String appName;
  final String userId;

  static TencentLyricsConfig? fromEnvironment() {
    final environment = Platform.environment;
    final values = [
      environment['TENCENT_SECRET_ID'] ?? '',
      environment['TENCENT_SECRET_KEY'] ?? '',
      environment['TENCENT_YINSUDA_APP_NAME'] ?? '',
      environment['TENCENT_YINSUDA_USER_ID'] ?? '',
    ];
    if (values.any((value) => value.trim().isEmpty)) return null;
    return TencentLyricsConfig(
      secretId: values[0],
      secretKey: values[1],
      appName: values[2],
      userId: values[3],
    );
  }
}

/// Looks up line-synced lyrics only. A missing or ambiguous match stays manual.
class OnlineLyricsLookup {
  OnlineLyricsLookup({
    LyricsRequest? request,
    String? musixmatchApiKey,
    TencentLyricsConfig? tencentConfig,
    TencentRequest? tencentRequest,
  }) : _request = request ?? _httpRequest,
       _musixmatchApiKey =
           musixmatchApiKey ?? Platform.environment['MUSIXMATCH_API_KEY'] ?? '',
       _tencentConfig = tencentConfig ?? TencentLyricsConfig.fromEnvironment(),
       _tencentRequest = tencentRequest;

  final LyricsRequest _request;
  final String _musixmatchApiKey;
  final TencentLyricsConfig? _tencentConfig;
  final TencentRequest? _tencentRequest;
  bool get musixmatchConfigured => _musixmatchApiKey.trim().isNotEmpty;
  bool get tencentConfigured => _tencentConfig != null;
  final Map<String, DateTime> _retryAfter = {};
  late final Future<Map<String, String>> _characterMap = _loadCharacterMap();
  late final Future<Map<String, String>> _reverseMap = _loadReverseMap();

  Future<OnlineLyrics?> find({
    required String title,
    required String artist,
    int durationMs = 0,
    Set<OnlineLyricsSource>? enabledSources,
  }) async {
    if (title.trim().isEmpty || normalizedArtist(artist).isEmpty) return null;
    artist = artist
        .replaceFirst(RegExp(r'\s*[-–—]\s*Topic\s*$', caseSensitive: false), '')
        .trim();
    final enabled = enabledSources ?? defaultOnlineLyricsSources;
    if (enabled.isEmpty) return null;
    final characterMap = await _characterMap;
    final reverseMap = await _reverseMap;
    Object? lastError;
    for (final source in OnlineLyricsSource.values) {
      if (!enabled.contains(source)) continue;
      try {
        final result = switch (source) {
          OnlineLyricsSource.netease => await _findNetease(
            title,
            artist,
            durationMs,
            characterMap,
            reverseMap,
          ),
          OnlineLyricsSource.kugou => await _findKugou(
            title,
            artist,
            durationMs,
            characterMap,
            reverseMap,
          ),
          OnlineLyricsSource.lrclib => await _findLrclib(
            title,
            artist,
            durationMs,
            characterMap,
            reverseMap,
          ),
          OnlineLyricsSource.amll => await _findAmll(
            title,
            artist,
            durationMs,
            characterMap,
            reverseMap,
          ),
          OnlineLyricsSource.lrcApi => await _findLrcApi(
            title,
            artist,
            durationMs,
            characterMap,
            reverseMap,
          ),
          OnlineLyricsSource.musixmatch => await _findMusixmatch(
            title,
            artist,
            durationMs,
            characterMap,
          ),
          OnlineLyricsSource.tencentCloud => await _findTencent(
            title,
            artist,
            durationMs,
            characterMap,
          ),
        };
        if (result != null) return result;
        lastError = null;
      } catch (error) {
        // A temporary failure in one service must not block the next source.
        lastError = error;
      }
    }
    if (lastError != null) throw lastError;
    return null;
  }

  /// Returns validated candidates from enabled providers for manual review.
  Future<List<OnlineLyrics>> findAll({
    required String title,
    required String artist,
    int durationMs = 0,
    Set<OnlineLyricsSource>? enabledSources,
  }) async {
    final enabled = enabledSources ?? defaultOnlineLyricsSources;
    final candidates = <OnlineLyrics>[];
    final characterMap = await _characterMap;
    final reverseMap = await _reverseMap;
    for (final source in OnlineLyricsSource.values) {
      if (!enabled.contains(source)) continue;
      try {
        final list = switch (source) {
          OnlineLyricsSource.netease => await _searchNetease(
            title,
            artist,
            durationMs,
            characterMap,
            reverseMap,
          ),
          OnlineLyricsSource.kugou => await _searchKugou(
            title,
            artist,
            durationMs,
            characterMap,
            reverseMap,
          ),
          OnlineLyricsSource.lrclib => await _searchLrclib(
            title,
            artist,
            durationMs,
            characterMap,
            reverseMap,
          ),
          OnlineLyricsSource.amll => await _searchAmll(
            title,
            artist,
            durationMs,
            characterMap,
            reverseMap,
          ),
          OnlineLyricsSource.lrcApi => await _searchLrcApi(
            title,
            artist,
            durationMs,
            characterMap,
            reverseMap,
          ),
          OnlineLyricsSource.musixmatch => switch (await _findMusixmatch(
                title,
                artist,
                durationMs,
                characterMap,
              )) {
            final item? => <OnlineLyrics>[item],
            null => const <OnlineLyrics>[],
          },
          OnlineLyricsSource.tencentCloud => switch (await _findTencent(
                title,
                artist,
                durationMs,
                characterMap,
              )) {
            final item? => <OnlineLyrics>[item],
            null => const <OnlineLyrics>[],
          },
        };
        candidates.addAll(list);
      } catch (_) {
        // Other providers can still offer a usable candidate.
      }
    }
    return candidates;
  }

  Future<List<OnlineLyrics>> _searchNetease(
    String title,
    String artist,
    int durationMs,
    Map<String, String> characterMap,
    Map<String, String> reverseMap,
  ) async {
    if (_backingOff('網易雲音樂')) return const [];

    final queryVariants = <String>{};
    final primaryArtist = splitArtists(artist).firstOrNull ?? artist;
    for (final cand in candidateTitles(title)) {
      queryVariants.add('$cand $artist'.trim());
      queryVariants.add('$cand $primaryArtist'.trim());
      queryVariants.add(
        '${toSimplified(cand, characterMap)} ${toSimplified(primaryArtist, characterMap)}'.trim(),
      );
      queryVariants.add(cand);
      if (queryVariants.length >= 4) break;
    }

    final candidates = <OnlineLyrics>[];
    final seenIds = <String>{};

    for (final query in queryVariants) {
      final searchUri = Uri.https('music.163.com', '/api/search/get/web', {
        'csrf_token': '',
        'type': '1',
        'offset': '0',
        'limit': '5',
        's': query,
      });
      final response = await _request(searchUri);
      if (_limited('網易雲音樂', response)) break;
      if (response.status != 200 || response.body is! Map) continue;
      final result = (response.body as Map)['result'];
      if (result is! Map || result['songs'] is! List) continue;

      for (final song in result['songs'] as List) {
        if (song is! Map) continue;
        final songId = song['id']?.toString() ?? '';
        if (songId.isEmpty || seenIds.contains(songId)) continue;
        final songTitle = song['name']?.toString() ?? '';
        final artistsList = (song['artists'] as List? ?? [])
            .whereType<Map>()
            .map((a) => a['name']?.toString() ?? '')
            .where((n) => n.isNotEmpty)
            .toList();
        final artists = artistsList.join(' / ');
        final albumName = (song['album'] as Map?)?['name']?.toString() ?? '';
        final songDurationMs = (song['duration'] as num?)?.toInt() ?? 0;

        if (!_titlesMatch(songTitle, title, characterMap) ||
            !_artistsMatch(
              artists,
              artist,
              characterMap,
              remoteTitle: songTitle,
              queryTitle: title,
              durationMs: durationMs,
              remoteDurationMs: songDurationMs,
            )) {
          continue;
        }

        if (durationMs > 0 && songDurationMs > 0) {
          final tolerance = _durationTolerance(durationMs);
          if ((songDurationMs - durationMs).abs() > tolerance) continue;
        }

        final lyricUri = Uri.https('music.163.com', '/api/song/lyric', {
          'os': 'pc',
          'id': songId,
          'lv': '-1',
          'kv': '-1',
          'tv': '-1',
        });
        final lyricResponse = await _request(lyricUri);
        if (lyricResponse.status != 200 || lyricResponse.body is! Map) continue;
        final lyricBody = lyricResponse.body as Map;
        final lrc = (lyricBody['lrc'] as Map?)?['lyric']?.toString() ?? '';
        if (lrc.trim().isEmpty || Lrc.parse(lrc).isEmpty) continue;

        seenIds.add(songId);
        candidates.add(
          OnlineLyrics(
            lrc: lrc,
            providerId: songId,
            title: songTitle,
            artist: artists,
            album: albumName,
            durationMs: songDurationMs > 0 ? songDurationMs : durationMs,
            source: '網易雲音樂',
          ),
        );
        if (candidates.length >= 3) break;
      }
      if (candidates.isNotEmpty) break;
    }

    return candidates;
  }

  Future<OnlineLyrics?> _findNetease(
    String title,
    String artist,
    int durationMs,
    Map<String, String> characterMap,
    Map<String, String> reverseMap,
  ) async {
    final list = await _searchNetease(
      title,
      artist,
      durationMs,
      characterMap,
      reverseMap,
    );
    if (list.isEmpty) return null;
    final candidateList = list
        .map((l) => _Candidate(l, l.durationMs > 0 ? l.durationMs / 1000 : null))
        .toList();
    return _choose(candidateList, durationMs, ambiguityWindowMs: 500);
  }

  Future<List<OnlineLyrics>> _searchKugou(
    String title,
    String artist,
    int durationMs,
    Map<String, String> characterMap,
    Map<String, String> reverseMap,
  ) async {
    if (_backingOff('酷狗音樂')) return const [];

    final queryVariants = <String>{};
    final primaryArtist = splitArtists(artist).firstOrNull ?? artist;
    for (final cand in candidateTitles(title)) {
      queryVariants.add(
        '${toSimplified(primaryArtist, characterMap)} - ${toSimplified(cand, characterMap)}'.trim(),
      );
      queryVariants.add(toSimplified(cand, characterMap));
      queryVariants.add('$primaryArtist - $cand'.trim());
      queryVariants.add(cand);
      if (queryVariants.length >= 4) break;
    }

    final candidates = <OnlineLyrics>[];
    final seenIds = <String>{};

    for (final query in queryVariants) {
      final searchUri = Uri.https('lyrics.kugou.com', '/search', {
        'ver': '1',
        'man': 'yes',
        'client': 'pc',
        'keyword': query,
        'duration': '',
        'hash': '',
      });
      final response = await _request(searchUri);
      if (_limited('酷狗音樂', response)) break;
      if (response.status != 200 || response.body is! Map) continue;
      final body = response.body as Map;
      final rawCandidates = body['candidates'];
      if (rawCandidates is! List) continue;

      for (final raw in rawCandidates) {
        if (raw is! Map) continue;
        final candidateId = raw['id']?.toString() ?? '';
        final accessKey = raw['accesskey']?.toString() ?? '';
        if (candidateId.isEmpty ||
            accessKey.isEmpty ||
            seenIds.contains(candidateId)) {
          continue;
        }
        final songTitle = raw['song']?.toString() ?? '';
        final singer = raw['singer']?.toString() ?? '';
        final rawDuration = (raw['duration'] as num?)?.toInt() ?? 0;
        final songDurationMs =
            rawDuration > 0 && rawDuration < 1000
                ? rawDuration * 1000
                : rawDuration;

        if (!_titlesMatch(songTitle, title, characterMap) ||
            !_artistsMatch(
              singer,
              artist,
              characterMap,
              remoteTitle: songTitle,
              queryTitle: title,
              durationMs: durationMs,
              remoteDurationMs: songDurationMs,
            )) {
          continue;
        }

        if (durationMs > 0 && songDurationMs > 0) {
          final tolerance = _durationTolerance(durationMs);
          if ((songDurationMs - durationMs).abs() > tolerance) continue;
        }

        final downloadUri = Uri.https('lyrics.kugou.com', '/download', {
          'ver': '1',
          'client': 'pc',
          'id': candidateId,
          'accesskey': accessKey,
          'fmt': 'lrc',
          'charset': 'utf8',
        });
        final downloadResponse = await _request(downloadUri);
        if (downloadResponse.status != 200 || downloadResponse.body is! Map) {
          continue;
        }
        final downloadBody = downloadResponse.body as Map;
        final contentBase64 = downloadBody['content']?.toString() ?? '';
        if (contentBase64.isEmpty) continue;

        String lrc;
        try {
          lrc = utf8.decode(base64.decode(contentBase64));
        } catch (_) {
          continue;
        }
        if (lrc.trim().isEmpty || Lrc.parse(lrc).isEmpty) continue;

        seenIds.add(candidateId);
        candidates.add(
          OnlineLyrics(
            lrc: lrc,
            providerId: candidateId,
            title: songTitle,
            artist: singer,
            album: '',
            durationMs: songDurationMs > 0 ? songDurationMs : durationMs,
            source: '酷狗音樂',
          ),
        );
        if (candidates.length >= 3) break;
      }
      if (candidates.isNotEmpty) break;
    }

    return candidates;
  }

  Future<OnlineLyrics?> _findKugou(
    String title,
    String artist,
    int durationMs,
    Map<String, String> characterMap,
    Map<String, String> reverseMap,
  ) async {
    final list = await _searchKugou(
      title,
      artist,
      durationMs,
      characterMap,
      reverseMap,
    );
    if (list.isEmpty) return null;
    final candidateList = list
        .map((l) => _Candidate(l, l.durationMs > 0 ? l.durationMs / 1000 : null))
        .toList();
    return _choose(candidateList, durationMs, ambiguityWindowMs: 500);
  }

  Future<List<OnlineLyrics>> _searchLrclib(
    String title,
    String artist,
    int durationMs,
    Map<String, String> characterMap,
    Map<String, String> reverseMap,
  ) async {
    if (_backingOff('LRCLIB')) return const [];
    final candidates = <OnlineLyrics>[];

    for (final candTitle in candidateTitles(title)) {
      final parameters = <String, String>{
        'track_name': candTitle,
        'artist_name': artist,
      };
      if (durationMs > 0) {
        parameters['duration'] = (durationMs / 1000).round().toString();
      }
      final exact = await _request(
        Uri.https('lrclib.net', '/api/get', parameters),
      );
      if (_limited('LRCLIB', exact)) return candidates;
      if (exact.status == 200 && exact.body is Map) {
        final lyric = _parse(
          exact.body as Map,
          title,
          artist,
          durationMs,
          characterMap,
          'LRCLIB',
        );
        if (lyric != null) {
          candidates.add(lyric);
          return candidates;
        }
      }
      break;
    }

    await Future<void>.delayed(const Duration(milliseconds: 300));

    final titlesToTry = <String>{};
    for (final cand in candidateTitles(title)) {
      titlesToTry.add(cand);
      titlesToTry.add(toSimplified(cand, characterMap));
      titlesToTry.add(toTraditional(cand, reverseMap));
    }

    final seenIds = <String>{};
    for (final candTitle in titlesToTry) {
      final search = await _request(
        artist.isNotEmpty
            ? Uri.https('lrclib.net', '/api/search', {
                'track_name': candTitle,
                'artist_name': artist,
              })
            : Uri.https('lrclib.net', '/api/search', {'q': candTitle}),
      );
      if (_limited('LRCLIB', search)) return candidates;
      if (search.status != 200 || search.body is! List) continue;
      for (final item in search.body as List) {
        if (item is! Map) continue;
        final lyric = _parse(
          item,
          title,
          artist,
          durationMs,
          characterMap,
          'LRCLIB',
        );
        if (lyric != null && seenIds.add(lyric.providerId)) {
          candidates.add(lyric);
        }
      }
      if (candidates.isNotEmpty) return candidates;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    return candidates;
  }

  Future<OnlineLyrics?> _findLrclib(
    String title,
    String artist,
    int durationMs,
    Map<String, String> characterMap,
    Map<String, String> reverseMap,
  ) async {
    final list = await _searchLrclib(
      title,
      artist,
      durationMs,
      characterMap,
      reverseMap,
    );
    if (list.isEmpty) return null;
    final candidateList = list
        .map((l) => _Candidate(l, l.durationMs > 0 ? l.durationMs / 1000 : null))
        .toList();
    return _choose(candidateList, durationMs, ambiguityWindowMs: 500);
  }

  Future<List<OnlineLyrics>> _searchAmll(
    String title,
    String artist,
    int durationMs,
    Map<String, String> characterMap,
    Map<String, String> reverseMap,
  ) async {
    if (_backingOff('AMLL')) return const [];
    final candidates = <OnlineLyrics>[];
    final titlesToTry = <String>{};
    for (final cand in candidateTitles(title)) {
      titlesToTry.add(cand);
      titlesToTry.add(toSimplified(cand, characterMap));
    }
    final primaryArtist = splitArtists(artist).firstOrNull ?? artist;
    final artistsToTry = <String>{
      artist,
      primaryArtist,
      toSimplified(artist, characterMap),
      toSimplified(primaryArtist, characterMap),
    };

    final seen = <String>{};
    for (final candTitle in titlesToTry) {
      for (final candArtist in artistsToTry) {
        final response = await _request(
          Uri.https('api.amll.dev', '/v1/lrclib/search', {
            'track_name': candTitle,
            'artist_name': candArtist,
            'pageSize': '20',
          }),
        );
        if (_limited('AMLL', response) ||
            response.status != 200 ||
            response.body is! List) {
          continue;
        }
        for (final item in response.body as List) {
          if (item is! Map) continue;
          final lyric = _parse(
            item,
            title,
            artist,
            durationMs,
            characterMap,
            'AMLL',
          );
          if (lyric != null && seen.add(lyric.providerId)) {
            candidates.add(lyric);
          }
        }
        if (candidates.isNotEmpty) return candidates;
      }
    }
    return candidates;
  }

  Future<OnlineLyrics?> _findAmll(
    String title,
    String artist,
    int durationMs,
    Map<String, String> characterMap,
    Map<String, String> reverseMap,
  ) async {
    final list = await _searchAmll(
      title,
      artist,
      durationMs,
      characterMap,
      reverseMap,
    );
    if (list.isEmpty) return null;
    final candidateList = list
        .map((l) => _Candidate(l, Lrc.parse(l.lrc).last.timeMs / 1000))
        .toList();
    return _choose(candidateList, durationMs, ambiguityWindowMs: 5000);
  }

  Future<List<OnlineLyrics>> _searchLrcApi(
    String title,
    String artist,
    int durationMs,
    Map<String, String> characterMap,
    Map<String, String> reverseMap,
  ) async {
    if (_backingOff('LrcAPI')) return const [];
    final candidates = <OnlineLyrics>[];
    final titlesToTry = <String>{};
    for (final cand in candidateTitles(title)) {
      titlesToTry.add(cand);
      titlesToTry.add(toSimplified(cand, characterMap));
    }
    final primaryArtist = splitArtists(artist).firstOrNull ?? artist;
    final artistsToTry = <String>{
      artist,
      primaryArtist,
      toSimplified(artist, characterMap),
      toSimplified(primaryArtist, characterMap),
    };

    final seen = <String>{};
    for (final candTitle in titlesToTry) {
      for (final candArtist in artistsToTry) {
        final response = await _request(
          Uri.https('api.lrc.cx', '/jsonapi', {
            'title': candTitle,
            'artist': candArtist,
          }),
        );
        if (_limited('LrcAPI', response) ||
            response.status != 200 ||
            response.body is! List) {
          continue;
        }
        for (final item in response.body as List) {
          if (item is! Map) continue;
          final lyric = _parse(
            item,
            title,
            artist,
            durationMs,
            characterMap,
            'LrcAPI',
          );
          if (lyric != null && seen.add(lyric.providerId)) {
            candidates.add(lyric);
          }
        }
        if (candidates.isNotEmpty) return candidates;
      }
    }
    return candidates;
  }

  Future<OnlineLyrics?> _findLrcApi(
    String title,
    String artist,
    int durationMs,
    Map<String, String> characterMap,
    Map<String, String> reverseMap,
  ) async {
    final list = await _searchLrcApi(
      title,
      artist,
      durationMs,
      characterMap,
      reverseMap,
    );
    if (list.isEmpty) return null;
    final candidateList = list
        .map(
          (l) => _Candidate(
            l,
            l.durationMs > 0
                ? l.durationMs / 1000
                : Lrc.parse(l.lrc).last.timeMs / 1000,
          ),
        )
        .toList();
    return _choose(candidateList, durationMs, ambiguityWindowMs: 5000);
  }

  Future<OnlineLyrics?> _findMusixmatch(
    String title,
    String artist,
    int durationMs,
    Map<String, String> characterMap,
  ) async {
    if (!musixmatchConfigured || _backingOff('Musixmatch')) return null;
    final match = await _request(
      Uri.https('api.musixmatch.com', '/ws/1.1/matcher.track.get', {
        'apikey': _musixmatchApiKey,
        'q_track': title,
        'q_artist': artist,
      }),
    );
    if (_limited('Musixmatch', match) || match.status != 200) return null;
    final track = _musixmatchBody(match.body)?['track'];
    if (track is! Map ||
        track['track_id'] is! num ||
        track['track_name'] is! String ||
        track['artist_name'] is! String ||
        !_titlesMatch(track['track_name'] as String, title, characterMap) ||
        !_artistsMatch(track['artist_name'] as String, artist, characterMap)) {
      return null;
    }
    final trackLength = track['track_length'];
    if (durationMs > 0 &&
        trackLength is num &&
        trackLength > 0 &&
        (trackLength * 1000 - durationMs).abs() > _durationTolerance(durationMs)) {
      return null;
    }
    final subtitle = await _request(
      Uri.https('api.musixmatch.com', '/ws/1.1/track.subtitle.get', {
        'apikey': _musixmatchApiKey,
        'track_id': (track['track_id'] as num).toInt().toString(),
        'subtitle_format': 'lrc',
      }),
    );
    if (_limited('Musixmatch', subtitle) || subtitle.status != 200) return null;
    final data = _musixmatchBody(subtitle.body)?['subtitle'];
    if (data is! Map || data['restricted'] == 1) return null;
    final lrc = data['subtitle_body'];
    if (lrc is! String || Lrc.parse(lrc).isEmpty) return null;
    if (durationMs > 0) {
      final lastTimeMs = Lrc.parse(lrc).last.timeMs;
      final allowedOutroMs = (durationMs * 0.2).round().clamp(45000, 90000);
      if (lastTimeMs > durationMs + 3000 ||
          lastTimeMs < durationMs - allowedOutroMs) {
        return null;
      }
    }
    return OnlineLyrics(
      lrc: lrc,
      providerId: (track['track_id'] as num).toInt().toString(),
      title: track['track_name'] as String,
      artist: track['artist_name'] as String,
      album: track['album_name'] is String ? track['album_name'] as String : '',
      durationMs: durationMs > 0
          ? durationMs
          : trackLength is num
          ? (trackLength * 1000).round()
          : 0,
      source: 'Musixmatch',
    );
  }

  Map? _musixmatchBody(Object? raw) {
    if (raw is! Map) return null;
    final message = raw['message'];
    if (message is! Map ||
        message['header'] is! Map ||
        (message['header'] as Map)['status_code'] != 200) {
      return null;
    }
    return message['body'] is Map ? message['body'] as Map : null;
  }

  Future<OnlineLyrics?> _findTencent(
    String title,
    String artist,
    int durationMs,
    Map<String, String> characterMap,
  ) async {
    final config = _tencentConfig;
    if (config == null || _backingOff('Tencent')) return null;
    final search = await _callTencent('SearchKTVMusics', {
      'AppName': config.appName,
      'UserId': config.userId,
      'KeyWord': title,
      'Limit': 20,
      'MaterialFilters': ['Lyrics'],
    });
    if (_limited('Tencent', search) ||
        search.status != 200 ||
        search.body is! Map) {
      return null;
    }
    final response = (search.body as Map)['Response'];
    if (response is! Map ||
        response['Error'] != null ||
        response['KTVMusicInfoSet'] is! List) {
      return null;
    }
    final candidates = <Map>[];
    for (final item in response['KTVMusicInfoSet'] as List) {
      if (item is! Map ||
          item['MusicId'] is! String ||
          item['Name'] is! String ||
          item['SingerSet'] is! List ||
          item['Duration'] is! num) {
        continue;
      }
      if (!_titlesMatch(item['Name'] as String, title, characterMap)) {
        continue;
      }
      final singers = (item['SingerSet'] as List).whereType<String>();
      if (!singers.any(
        (name) => _artistsMatch(name, artist, characterMap),
      )) {
        continue;
      }
      if (durationMs > 0 &&
          ((item['Duration'] as num).toDouble() - durationMs).abs() >
              _durationTolerance(durationMs)) {
        continue;
      }
      candidates.add(item);
    }
    if (candidates.isEmpty) return null;
    if (durationMs > 0) {
      candidates.sort(
        (a, b) => ((a['Duration'] as num) - durationMs).abs().compareTo(
          ((b['Duration'] as num) - durationMs).abs(),
        ),
      );
      if (candidates.length > 1 &&
          (((candidates[1]['Duration'] as num) - durationMs).abs() -
                  ((candidates[0]['Duration'] as num) - durationMs).abs()) <
              500) {
        return null;
      }
    } else if (candidates.length != 1) {
      return null;
    }
    final item = candidates.first;
    final detail = await _callTencent('BatchDescribeKTVMusicDetails', {
      'AppName': config.appName,
      'UserId': config.userId,
      'MusicIds': [item['MusicId'] as String],
    });
    if (_limited('Tencent', detail) ||
        detail.status != 200 ||
        detail.body is! Map) {
      return null;
    }
    final details = (detail.body as Map)['Response'];
    if (details is! Map ||
        details['Error'] != null ||
        details['KTVMusicDetailInfoSet'] is! List) {
      return null;
    }
    final matches = (details['KTVMusicDetailInfoSet'] as List)
        .whereType<Map>()
        .where(
          (entry) =>
              entry['KTVMusicBaseInfo'] is Map &&
              (entry['KTVMusicBaseInfo'] as Map)['MusicId'] == item['MusicId'],
        );
    if (matches.length != 1) return null;
    final url = Uri.tryParse(matches.single['LyricsUrl']?.toString() ?? '');
    if (url == null || url.scheme != 'https' || url.host.isEmpty) return null;
    final lyricResponse = await _request(url);
    if (lyricResponse.status != 200 || lyricResponse.body is! String) {
      return null;
    }
    final lrc = _vttToLrc(lyricResponse.body as String);
    if (Lrc.parse(lrc).isEmpty) return null;
    if (durationMs > 0 && Lrc.parse(lrc).last.timeMs > durationMs + 3000) {
      return null;
    }
    final album = item['AlbumInfo'];
    return OnlineLyrics(
      lrc: lrc,
      providerId: item['MusicId'] as String,
      title: item['Name'] as String,
      artist: (item['SingerSet'] as List).whereType<String>().join('、'),
      album: album is Map && album['Name'] is String
          ? album['Name'] as String
          : '',
      durationMs: (item['Duration'] as num).round(),
      source: '騰訊雲音速達',
    );
  }

  Future<LookupResponse> _callTencent(
    String action,
    Map<String, Object> payload,
  ) {
    final override = _tencentRequest;
    return override != null
        ? override(action, payload)
        : _tencentHttpRequest(_tencentConfig!, action, payload);
  }

  String _vttToLrc(String vtt) {
    final lines = <String>[];
    final cues = vtt.replaceAll('\r\n', '\n').split(RegExp(r'\n\s*\n'));
    final stamp = RegExp(r'(?:(\d{2}):)?(\d{2}):(\d{2})[.,](\d{3})\s+-->');
    for (final cue in cues) {
      final parts = cue.split('\n');
      final index = parts.indexWhere((part) => stamp.hasMatch(part));
      if (index < 0 || index + 1 >= parts.length) continue;
      final match = stamp.firstMatch(parts[index])!;
      final text = parts
          .skip(index + 1)
          .join(' ')
          .replaceAll(RegExp(r'<[^>]*>'), '')
          .trim();
      if (text.isEmpty) continue;
      final minutes =
          int.parse(match.group(1) ?? '0') * 60 + int.parse(match.group(2)!);
      lines.add(
        '[${minutes.toString().padLeft(2, '0')}:${match.group(3)}.${match.group(4)}]$text',
      );
    }
    return lines.join('\n');
  }

  OnlineLyrics? _choose(
    List<_Candidate> matches,
    int durationMs, {
    required int ambiguityWindowMs,
  }) {
    if (matches.isEmpty) return null;
    // Multiple records with identical timed text are the same usable result.
    final unique = <String, _Candidate>{};
    for (final match in matches) {
      unique.putIfAbsent(match.lyric.lrc, () => match);
    }
    matches = unique.values.toList();
    if (durationMs <= 0) {
      return matches.length == 1 ? matches.single.lyric : null;
    }
    matches.sort(
      (a, b) => ((a.durationSeconds ?? 0) * 1000 - durationMs).abs().compareTo(
        ((b.durationSeconds ?? 0) * 1000 - durationMs).abs(),
      ),
    );
    if (matches.length > 1) {
      final firstDifference =
          ((matches[0].durationSeconds ?? 0) * 1000 - durationMs).abs();
      final nextDifference =
          ((matches[1].durationSeconds ?? 0) * 1000 - durationMs).abs();
      if (nextDifference - firstDifference < ambiguityWindowMs &&
          matches[0].lyric.lrc != matches[1].lyric.lrc) {
        return null;
      }
    }
    return matches.first.lyric;
  }

  bool _backingOff(String source) {
    final until = _retryAfter[source];
    return until != null && DateTime.now().isBefore(until);
  }

  bool _limited(String source, LookupResponse response) {
    if (response.status != 429 && response.status != 503) return false;
    _retryAfter[source] = DateTime.now().add(
      response.retryAfter ?? const Duration(minutes: 2),
    );
    return true;
  }

  OnlineLyrics? _parse(
    Map response,
    String title,
    String artist,
    int durationMs,
    Map<String, String> characterMap,
    String source,
  ) {
    if (response['instrumental'] == true) return null;
    final remoteTitle =
        response['trackName'] ?? response['name'] ?? response['title'];
    final remoteArtist = response['artistName'] ?? response['artist'];
    final lrc =
        response['syncedLyrics'] ?? response['lrc'] ?? response['lyrics'];
    final id = response['id'];
    if (remoteTitle is! String ||
        remoteArtist is! String ||
        lrc is! String ||
        (id is! int && id is! String)) {
      return null;
    }
    final remoteDuration = response['duration'];
    final remoteDurationMs =
        remoteDuration is num ? (remoteDuration * 1000).round() : 0;
    if (!_titlesMatch(remoteTitle, title, characterMap) ||
        !_artistsMatch(
          remoteArtist,
          artist,
          characterMap,
          remoteTitle: remoteTitle,
          queryTitle: title,
          durationMs: durationMs,
          remoteDurationMs: remoteDurationMs,
        )) {
      return null;
    }
    final lines = Lrc.parse(lrc);
    if (lines.isEmpty) return null;
    final lyricEndMs = lines.last.timeMs;
    if (durationMs > 0) {
      final toleranceMs = _durationTolerance(durationMs);
      if (source == 'AMLL' || (source == 'LrcAPI' && remoteDuration is! num)) {
        final allowedOutroMs = (durationMs * 0.2).round().clamp(45000, 90000);
        if (lyricEndMs > durationMs + toleranceMs ||
            lyricEndMs < durationMs - allowedOutroMs) {
          return null;
        }
      } else {
        if (remoteDuration is! num ||
            (remoteDuration * 1000 - durationMs).abs() > toleranceMs) {
          return null;
        }
      }
    }
    final album = response['albumName'] ?? response['album'];
    return OnlineLyrics(
      lrc: lrc,
      providerId: id.toString(),
      title: remoteTitle,
      artist: remoteArtist,
      album: album is String ? album : '',
      durationMs:
          source == 'AMLL' || (source == 'LrcAPI' && remoteDuration is! num)
          ? durationMs
          : remoteDuration is num
          ? (remoteDuration * 1000).round()
          : 0,
      source: source,
    );
  }

  static String toSimplified(String value, Map<String, String> characterMap) =>
      value.runes.map((rune) {
        final character = String.fromCharCode(rune);
        return characterMap[character] ?? character;
      }).join();

  static String toTraditional(String value, Map<String, String> reverseMap) =>
      value.runes.map((rune) {
        final character = String.fromCharCode(rune);
        return reverseMap[character] ?? character;
      }).join();

  static int _durationTolerance(int durationMs) {
    if (durationMs <= 0) return 10000;
    return (durationMs * 0.05).round().clamp(8000, 15000);
  }

  static bool _titlesMatch(
    String remoteTitle,
    String queryTitle,
    Map<String, String> characterMap,
  ) {
    final isQueryLive = RegExp(r'\b(?:live|acoustic)\b', caseSensitive: false)
        .hasMatch(queryTitle);
    final isRemoteLive = RegExp(r'\b(?:live|acoustic)\b', caseSensitive: false)
        .hasMatch(remoteTitle);
    if (!isQueryLive && isRemoteLive) return false;

    final compRemote = _comparableStatic(remoteTitle, characterMap);
    final compQuery = _comparableStatic(queryTitle, characterMap);
    if (compRemote == compQuery) return true;

    final cleanRemote =
        _comparableStatic(cleanTitle(remoteTitle), characterMap);
    final cleanQuery = _comparableStatic(cleanTitle(queryTitle), characterMap);
    if (cleanRemote == cleanQuery) return true;

    for (final cand in candidateTitles(queryTitle)) {
      final compCand = _comparableStatic(cand, characterMap);
      if (compCand == compRemote || compCand == cleanRemote) return true;
    }

    for (final cand in candidateTitles(remoteTitle)) {
      final compCand = _comparableStatic(cand, characterMap);
      if (compCand == compQuery || compCand == cleanQuery) return true;
    }

    return false;
  }

  static const _knownArtistAliases = <String, Set<String>>{
    '容祖儿': {'容祖兒', 'joey yung', 'joey'},
    '周杰伦': {'周杰倫', 'jay chou', 'jay'},
    '汪苏泷': {'汪蘇瀧', 'silence wang', 'silence'},
    '陈奕迅': {'陳奕迅', 'eason chan', 'eason'},
    '林俊杰': {'林俊傑', 'jj lin', 'jj'},
    '邓紫棋': {'鄧紫棋', 'gem', 'g.e.m.'},
    '五月天': {'mayday'},
    '蔡依林': {'jolin tsai', 'jolin'},
    '王心凌': {'cyndi wang', 'cyndi'},
    '张惠妹': {'張惠妹', 'a-mei', 'amei'},
    '田馥甄': {'hebe tien', 'hebe'},
    '孙燕姿': {'孫燕姿', 'stefanie sun'},
    '梁静茹': {'梁靜茹', 'fish leong'},
    '韦礼安': {'韋禮安', 'weibird', 'william wei'},
    '告五人': {'accusefive'},
    '草东没有派对': {'草東沒有派對', 'no party for cao dong'},
    '落日飞车': {'落日飛車', 'sunset rollercoaster'},
    '陶喆': {'david tao'},
    '李荣浩': {'李榮浩', 'ronghao li'},
    '薛之谦': {'薛之謙', 'joker xue'},
    '王菲': {'faye wong'},
    '张学友': {'張學友', 'jacky cheung'},
    '刘德华': {'劉德華', 'andy lau'},
  };

  static bool _artistsMatch(
    String remoteArtist,
    String queryArtist,
    Map<String, String> characterMap, {
    String remoteTitle = '',
    String queryTitle = '',
    int durationMs = 0,
    int remoteDurationMs = 0,
  }) {
    if (queryArtist.trim().isEmpty || remoteArtist.trim().isEmpty) return true;

    final compRemote = _comparableStatic(remoteArtist, characterMap);
    final compQuery = _comparableStatic(queryArtist, characterMap);
    if (compRemote == compQuery) return true;

    for (final entry in _knownArtistAliases.entries) {
      final key = _comparableStatic(entry.key, characterMap);
      final aliases = entry.value
          .map((a) => _comparableStatic(a, characterMap))
          .toSet();
      aliases.add(key);
      if (aliases.contains(compRemote) && aliases.contains(compQuery)) {
        return true;
      }
    }

    final remoteParts = splitArtists(remoteArtist)
        .map((a) => _comparableStatic(a, characterMap))
        .where((a) => a.isNotEmpty)
        .toList();
    final queryParts = splitArtists(queryArtist)
        .map((a) => _comparableStatic(a, characterMap))
        .where((a) => a.isNotEmpty)
        .toList();

    for (final r in remoteParts) {
      for (final q in queryParts) {
        if (r == q ||
            (r.length >= 2 &&
                q.length >= 2 &&
                (r.contains(q) || q.contains(r)))) {
          return true;
        }
        for (final entry in _knownArtistAliases.entries) {
          final key = _comparableStatic(entry.key, characterMap);
          final aliases = entry.value
              .map((a) => _comparableStatic(a, characterMap))
              .toSet();
          aliases.add(key);
          if (aliases.contains(r) && aliases.contains(q)) return true;
        }
      }
    }

    if (compRemote.length >= 2 && compQuery.length >= 2) {
      if (compRemote.contains(compQuery) || compQuery.contains(compRemote)) {
        return true;
      }
    }

    if (remoteTitle.isNotEmpty && compQuery.length >= 2) {
      final compTitle = _comparableStatic(remoteTitle, characterMap);
      if (compTitle.contains(compQuery)) return true;
    }

    final cleanT = cleanTitle(queryTitle.isNotEmpty ? queryTitle : remoteTitle);
    if (cleanT.length >= 5 && durationMs > 0 && remoteDurationMs > 0) {
      if ((remoteDurationMs - durationMs).abs() <= 6000) {
        return true;
      }
    }

    return false;
  }

  static String _comparableStatic(
    String value,
    Map<String, String> characterMap,
  ) =>
      normalized(toSimplified(value, characterMap));

  static Future<Map<String, String>> _loadReverseMap() async {
    final map = await _loadCharacterMap();
    final reverse = <String, String>{};
    for (final entry in map.entries) {
      reverse.putIfAbsent(entry.value, () => entry.key);
    }
    return reverse;
  }

  static Future<Map<String, String>> _loadCharacterMap() async {
    try {
      String data;
      try {
        data = await rootBundle.loadString(
          'assets/opencc/TSCharacters.txt',
        );
      } catch (_) {
        final file = File('assets/opencc/TSCharacters.txt');
        if (file.existsSync()) {
          data = await file.readAsString();
        } else {
          return const {};
        }
      }
      final mapping = <String, String>{};
      for (final line in const LineSplitter().convert(data)) {
        if (line.startsWith('#') || line.trim().isEmpty) continue;
        final columns = line.trim().split(RegExp(r'\s+'));
        if (columns.length >= 2) {
          mapping[columns[0]] = String.fromCharCode(columns[1].runes.first);
        }
      }
      return mapping;
    } catch (_) {
      return const {};
    }
  }

  static Future<LookupResponse> _httpRequest(Uri uri) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 10));
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36 LyricsFloat/0.1',
      );
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      if (uri.host.contains('163.com')) {
        request.headers.set(
          HttpHeaders.cookieHeader,
          'os=pc; appver=2.7.1.198277',
        );
      }
      final response = await request.close().timeout(
        const Duration(seconds: 10),
      );
      final retrySeconds = int.tryParse(
        response.headers.value('retry-after') ?? '',
      );
      if (response.statusCode != 200) {
        await response.drain<void>();
        return LookupResponse(
          response.statusCode,
          null,
          retryAfter: retrySeconds == null
              ? null
              : Duration(seconds: retrySeconds),
        );
      }
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response.timeout(const Duration(seconds: 10))) {
        bytes.add(chunk);
        if (bytes.length > 512 * 1024) {
          throw const FormatException('Lyrics response too large');
        }
      }
      final body = utf8.decode(bytes.takeBytes());
      if (uri.path.endsWith('.vtt') ||
          response.headers.contentType?.mimeType == 'text/vtt') {
        return LookupResponse(response.statusCode, body);
      }
      try {
        return LookupResponse(response.statusCode, jsonDecode(body));
      } on FormatException {
        return LookupResponse(response.statusCode, body);
      }
    } finally {
      client.close(force: true);
    }
  }

  static Future<LookupResponse> _tencentHttpRequest(
    TencentLyricsConfig config,
    String action,
    Map<String, Object> payload,
  ) async {
    const host = 'yinsuda.tencentcloudapi.com';
    const service = 'yinsuda';
    const contentType = 'application/json; charset=utf-8';
    final now = DateTime.now().toUtc();
    final timestamp = now.millisecondsSinceEpoch ~/ 1000;
    final date =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final body = jsonEncode(payload);
    final canonical =
        'POST\n/\n\ncontent-type:$contentType\nhost:$host\n\ncontent-type;host\n${sha256.convert(utf8.encode(body))}';
    final scope = '$date/$service/tc3_request';
    final toSign =
        'TC3-HMAC-SHA256\n$timestamp\n$scope\n${sha256.convert(utf8.encode(canonical))}';
    List<int> sign(List<int> key, String value) =>
        Hmac(sha256, key).convert(utf8.encode(value)).bytes;
    final dateKey = sign(utf8.encode('TC3${config.secretKey}'), date);
    final serviceKey = sign(dateKey, service);
    final signingKey = sign(serviceKey, 'tc3_request');
    final signature = Hmac(sha256, signingKey).convert(utf8.encode(toSign));
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client
          .postUrl(Uri.https(host, '/'))
          .timeout(const Duration(seconds: 10));
      request.headers.set(HttpHeaders.contentTypeHeader, contentType);
      request.headers.set('X-TC-Action', action);
      request.headers.set('X-TC-Version', '2022-05-27');
      request.headers.set('X-TC-Timestamp', timestamp.toString());
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'TC3-HMAC-SHA256 Credential=${config.secretId}/$scope, SignedHeaders=content-type;host, Signature=$signature',
      );
      request.add(utf8.encode(body));
      final response = await request.close().timeout(
        const Duration(seconds: 10),
      );
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response.timeout(const Duration(seconds: 10))) {
        bytes.add(chunk);
        if (bytes.length > 512 * 1024) {
          throw const FormatException('Lyrics response too large');
        }
      }
      return LookupResponse(
        response.statusCode,
        jsonDecode(utf8.decode(bytes.takeBytes())),
      );
    } finally {
      client.close(force: true);
    }
  }
}

class _Candidate {
  const _Candidate(this.lyric, this.durationSeconds);
  final OnlineLyrics lyric;
  final double? durationSeconds;
}
