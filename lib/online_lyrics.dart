import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

import 'lyrics.dart';

enum OnlineLyricsSource {
  lrclib('LRCLIB'),
  amll('AMLL'),
  lrcApi('LrcAPI'),
  musixmatch('Musixmatch'),
  tencentCloud('騰訊雲音速達');

  const OnlineLyricsSource(this.label);
  final String label;
}

const defaultOnlineLyricsSources = {
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
    Object? lastError;
    for (final source in OnlineLyricsSource.values) {
      if (!enabled.contains(source)) continue;
      try {
        final result = switch (source) {
          OnlineLyricsSource.lrclib => await _findLrclib(
            title,
            artist,
            durationMs,
            characterMap,
          ),
          OnlineLyricsSource.amll => await _findAmll(
            title,
            artist,
            durationMs,
            characterMap,
          ),
          OnlineLyricsSource.lrcApi => await _findLrcApi(
            title,
            artist,
            durationMs,
            characterMap,
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

  /// Returns one validated candidate per enabled provider for manual review.
  Future<List<OnlineLyrics>> findAll({
    required String title,
    required String artist,
    int durationMs = 0,
    Set<OnlineLyricsSource>? enabledSources,
  }) async {
    final enabled = enabledSources ?? defaultOnlineLyricsSources;
    final candidates = <OnlineLyrics>[];
    for (final source in OnlineLyricsSource.values) {
      if (!enabled.contains(source)) continue;
      try {
        final result = await find(
          title: title,
          artist: artist,
          durationMs: durationMs,
          enabledSources: {source},
        );
        if (result != null) candidates.add(result);
      } catch (_) {
        // Other providers can still offer a usable candidate.
      }
    }
    return candidates;
  }

  Future<OnlineLyrics?> _findLrclib(
    String title,
    String artist,
    int durationMs,
    Map<String, String> characterMap,
  ) async {
    if (_backingOff('LRCLIB')) return null;
    final parameters = <String, String>{
      'track_name': title,
      'artist_name': artist,
    };
    if (durationMs > 0) {
      parameters['duration'] = (durationMs / 1000).round().toString();
    }
    final exact = await _request(
      Uri.https('lrclib.net', '/api/get', parameters),
    );
    if (_limited('LRCLIB', exact)) return null;
    if (exact.status == 200 && exact.body is Map) {
      final candidate = _parse(
        exact.body as Map,
        title,
        artist,
        durationMs,
        characterMap,
        'LRCLIB',
      );
      if (candidate != null) return candidate;
    }
    // The service asks clients to leave a short gap between requests.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final reverse = <String, String>{};
    for (final entry in characterMap.entries) {
      reverse.putIfAbsent(entry.value, () => entry.key);
    }
    final traditionalTitle = title.runes.map((rune) {
      final character = String.fromCharCode(rune);
      return reverse[character] ?? character;
    }).join();
    for (final queryTitle in {title, traditionalTitle}) {
      final search = await _request(
        Uri.https('lrclib.net', '/api/search', {
          'track_name': queryTitle,
          'artist_name': artist,
        }),
      );
      if (_limited('LRCLIB', search)) return null;
      if (search.status != 200 || search.body is! List) continue;
      final matches = <_Candidate>[];
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
        if (lyric == null) continue;
        final remoteDuration = (item['duration'] as num?)?.toDouble();
        matches.add(_Candidate(lyric, remoteDuration));
      }
      final chosen = _choose(matches, durationMs, ambiguityWindowMs: 500);
      if (chosen != null) return chosen;
      if (queryTitle != traditionalTitle) {
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
    }
    return null;
  }

  Future<OnlineLyrics?> _findAmll(
    String title,
    String artist,
    int durationMs,
    Map<String, String> characterMap,
  ) async {
    if (_backingOff('AMLL')) return null;
    final response = await _request(
      Uri.https('api.amll.dev', '/v1/lrclib/search', {
        'track_name': title,
        'artist_name': artist,
        'pageSize': '20',
      }),
    );
    if (_limited('AMLL', response) ||
        response.status != 200 ||
        response.body is! List) {
      return null;
    }
    final matches = <_Candidate>[];
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
      if (lyric == null) continue;
      // AMLL's duration is the final lyric timestamp, not the audio length.
      matches.add(_Candidate(lyric, Lrc.parse(lyric.lrc).last.timeMs / 1000));
    }
    return _choose(matches, durationMs, ambiguityWindowMs: 5000);
  }

  Future<OnlineLyrics?> _findLrcApi(
    String title,
    String artist,
    int durationMs,
    Map<String, String> characterMap,
  ) async {
    if (_backingOff('LrcAPI')) return null;
    final response = await _request(
      Uri.https('api.lrc.cx', '/jsonapi', {'title': title, 'artist': artist}),
    );
    if (_limited('LrcAPI', response) ||
        response.status != 200 ||
        response.body is! List) {
      return null;
    }
    final matches = <_Candidate>[];
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
      if (lyric == null) continue;
      final remoteDuration = item['duration'];
      matches.add(
        _Candidate(
          lyric,
          remoteDuration is num
              ? remoteDuration.toDouble()
              : Lrc.parse(lyric.lrc).last.timeMs / 1000,
        ),
      );
    }
    return _choose(matches, durationMs, ambiguityWindowMs: 5000);
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
        _comparable(track['track_name'] as String, characterMap) !=
            _comparable(title, characterMap) ||
        _comparable(track['artist_name'] as String, characterMap) !=
            _comparable(artist, characterMap)) {
      return null;
    }
    final trackLength = track['track_length'];
    if (durationMs > 0 &&
        trackLength is num &&
        trackLength > 0 &&
        (trackLength * 1000 - durationMs).abs() > 3000) {
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
      if (_comparable(item['Name'] as String, characterMap) !=
          _comparable(title, characterMap)) {
        continue;
      }
      final singers = (item['SingerSet'] as List).whereType<String>();
      if (!singers.any(
        (name) =>
            _comparable(name, characterMap) ==
            _comparable(artist, characterMap),
      )) {
        continue;
      }
      if (durationMs > 0 &&
          ((item['Duration'] as num).toDouble() - durationMs).abs() > 3000) {
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
        id is! int && id is! String) {
      return null;
    }
    if (_comparable(remoteTitle, characterMap) !=
            _comparable(title, characterMap) ||
        _comparable(remoteArtist, characterMap) !=
            _comparable(artist, characterMap)) {
      return null;
    }
    final lines = Lrc.parse(lrc);
    if (lines.isEmpty) return null;
    final lyricEndMs = lines.last.timeMs;
    if (durationMs > 0) {
      final remoteDuration = response['duration'];
      if (source == 'AMLL' || (source == 'LrcAPI' && remoteDuration is! num)) {
        final allowedOutroMs = (durationMs * 0.2).round().clamp(45000, 90000);
        if (lyricEndMs > durationMs + 3000 ||
            lyricEndMs < durationMs - allowedOutroMs) {
          return null;
        }
      } else {
        if (remoteDuration is! num ||
            (remoteDuration * 1000 - durationMs).abs() > 3000) {
          return null;
        }
      }
    }
    final album = response['albumName'] ?? response['album'];
    final remoteDuration = response['duration'];
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

  String _comparable(String value, Map<String, String> characterMap) =>
      normalized(
        value.runes.map((rune) {
          final character = String.fromCharCode(rune);
          return characterMap[character] ?? character;
        }).join(),
      );

  static Future<Map<String, String>> _loadCharacterMap() async {
    try {
      final data = await rootBundle.loadString(
        'assets/opencc/TSCharacters.txt',
      );
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
        'LyricsFloat/0.1 (https://github.com)',
      );
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
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
