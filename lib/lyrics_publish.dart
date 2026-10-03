import 'app_language.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';

import 'lyrics.dart';

class PublishException implements Exception {
  const PublishException(this.message);
  final String message;
  @override
  String toString() => message;
}

class PublishCancelled implements Exception {}

class PublishCancellation {
  final Completer<void> _cancelled = Completer<void>();
  bool get isCancelled => _cancelled.isCompleted;
  Future<void> get whenCancelled => _cancelled.future;
  void cancel() {
    if (!isCancelled) _cancelled.complete();
  }

  void check() {
    if (isCancelled) throw PublishCancelled();
  }
}

class PublishResponse {
  const PublishResponse(this.status, this.body);
  final int status;
  final Object? body;
}

typedef PublishPost =
    Future<PublishResponse> Function(
      Uri uri, {
      Map<String, String>? headers,
      Object? body,
    });

typedef ChallengeSolver =
    Future<String> Function(
      String prefix,
      String target,
      PublishCancellation cancellation,
    );

class LrclibPublisher {
  LrclibPublisher({PublishPost? post, ChallengeSolver? solver})
    : _post = post ?? _httpPost,
      _solver = solver ?? solvePublishChallenge;

  final PublishPost _post;
  final ChallengeSolver _solver;

  Future<void> publish({
    required Song song,
    required String album,
    required double durationSeconds,
    required PublishCancellation cancellation,
    void Function(String status)? onStatus,
  }) async {
    if (song.title.trim().isEmpty ||
        song.artist.trim().isEmpty ||
        album.trim().isEmpty ||
        durationSeconds <= 0 ||
        !durationSeconds.isFinite ||
        Lrc.parse(song.lrc).isEmpty) {
      throw PublishException(
        tr(
          '請填齊歌名、歌手、專輯、歌曲長度和有效的 LRC 歌詞',
          'Enter the title, artist, album, duration and valid LRC lyrics',
        ),
      );
    }
    cancellation.check();
    onStatus?.call(tr('正在取得 LRCLIB 投稿驗證…', 'Requesting LRCLIB verification…'));
    final challenge = await _post(
      Uri.https('lrclib.net', '/api/request-challenge'),
    );
    cancellation.check();
    if (challenge.status != 200 || challenge.body is! Map) {
      throw PublishException(
        _errorMessage(
          challenge,
          tr('無法取得投稿驗證', 'Could not get submission verification'),
        ),
      );
    }
    final data = challenge.body as Map;
    final prefix = data['prefix'];
    final target = data['target'];
    if (prefix is! String ||
        target is! String ||
        prefix.isEmpty ||
        !RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(target)) {
      throw PublishException(
        tr('LRCLIB 回傳的投稿驗證格式不正確', 'Invalid verification format from LRCLIB'),
      );
    }
    onStatus?.call(
      tr(
        '正在計算投稿驗證，可能需要一段時間…',
        'Computing verification. This may take a while…',
      ),
    );
    final nonce = await _solver(prefix, target, cancellation);
    cancellation.check();
    onStatus?.call(tr('正在公開發布歌詞…', 'Publishing lyrics…'));
    final response = await _post(
      Uri.https('lrclib.net', '/api/publish'),
      headers: {'X-Publish-Token': '$prefix:$nonce'},
      body: {
        'trackName': song.title.trim(),
        'artistName': song.artist.trim(),
        'albumName': album.trim(),
        'duration': durationSeconds,
        'syncedLyrics': song.lrc,
      },
    );
    cancellation.check();
    if (response.status != 201) {
      throw PublishException(
        _errorMessage(response, tr('LRCLIB 投稿失敗', 'LRCLIB submission failed')),
      );
    }
  }

  static String _errorMessage(PublishResponse response, String fallback) {
    if (response.status == 429) {
      return tr(
        'LRCLIB 請求太頻繁，請稍後再試',
        'Too many LRCLIB requests. Try again later.',
      );
    }
    final body = response.body;
    final message = body is Map ? body['message'] : null;
    if (message is String && message.isNotEmpty) return '$fallback：$message';
    return '$fallback（HTTP ${response.status}）';
  }

  static Future<PublishResponse> _httpPost(
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
  }) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client
          .postUrl(uri)
          .timeout(const Duration(seconds: 10));
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'LyricsFloat/1.0 (https://github.com)',
      );
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      headers?.forEach(request.headers.set);
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(body));
      }
      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      final raw = await utf8.decoder
          .bind(response)
          .join()
          .timeout(const Duration(seconds: 20));
      Object? decoded;
      if (raw.isNotEmpty) {
        try {
          decoded = jsonDecode(raw);
        } on FormatException {
          decoded = null;
        }
      }
      return PublishResponse(response.statusCode, decoded);
    } finally {
      client.close(force: true);
    }
  }
}

Future<String> solvePublishChallenge(
  String prefix,
  String target,
  PublishCancellation cancellation,
) async {
  cancellation.check();
  final receive = ReceivePort();
  final isolate = await Isolate.spawn<List<Object>>(_solveWorker, [
    receive.sendPort,
    prefix,
    target,
  ]);
  try {
    return await Future.any<String>([
      receive.first.then((value) => value as String),
      cancellation.whenCancelled.then((_) => throw PublishCancelled()),
    ]).timeout(
      const Duration(minutes: 4),
      onTimeout: () => throw PublishException(
        tr('投稿驗證逾時，請重試', 'Verification timed out. Please retry'),
      ),
    );
  } finally {
    isolate.kill(priority: Isolate.immediate);
    receive.close();
  }
}

void _solveWorker(List<Object> arguments) {
  final port = arguments[0] as SendPort;
  final prefix = arguments[1] as String;
  final targetHex = arguments[2] as String;
  final target = List<int>.generate(
    32,
    (index) =>
        int.parse(targetHex.substring(index * 2, index * 2 + 2), radix: 16),
  );
  for (var nonce = 0; ; nonce++) {
    final hash = sha256.convert(utf8.encode('$prefix$nonce')).bytes;
    var valid = true;
    for (var index = 0; index < 32; index++) {
      if (hash[index] > target[index]) {
        valid = false;
        break;
      }
      if (hash[index] < target[index]) break;
    }
    if (valid) {
      port.send('$nonce');
      return;
    }
  }
}
