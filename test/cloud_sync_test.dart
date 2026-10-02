import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyrics_float/cloud_sync.dart';
import 'package:lyrics_float/lyrics.dart';

class _TestAuth extends CloudAuth {
  @override
  Future<String> accessToken() async => 'test-token';
}

void main() {
  test(
    'first sync uploads, next device merges and updates the backup',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'lyrics-cloud-test-',
      );
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var remoteSongs = <dynamic>[];
      var exists = false;
      var creations = 0;
      var updates = 0;
      server.listen((request) async {
        expect(
          request.headers.value(HttpHeaders.authorizationHeader),
          'Bearer test-token',
        );
        final body = await utf8.decoder.bind(request).join();
        request.response.headers.contentType = ContentType.json;
        if (request.uri.path == '/drive/v3/files') {
          request.response.write(
            jsonEncode({
              'files': exists
                  ? [
                      {
                        'id': 'backup-id',
                        'modifiedTime': '2026-01-01T00:00:00Z',
                      },
                    ]
                  : [],
            }),
          );
        } else if (request.uri.path == '/drive/v3/files/backup-id') {
          request.response.write(
            jsonEncode({'version': 1, 'songs': remoteSongs}),
          );
        } else if (request.uri.path == '/upload/drive/v3/files' &&
            request.method == 'POST') {
          creations++;
          exists = true;
          final match = RegExp(
            r'\{"version":1,"songs":\[.*\]\}',
          ).firstMatch(body);
          expect(match, isNotNull);
          remoteSongs = (jsonDecode(match!.group(0)!) as Map)['songs'] as List;
          request.response.write('{"id":"backup-id"}');
        } else if (request.uri.path == '/upload/drive/v3/files/backup-id' &&
            request.method == 'PATCH') {
          updates++;
          remoteSongs = (jsonDecode(body) as Map)['songs'] as List;
          request.response.write('{}');
        } else {
          request.response.statusCode = HttpStatus.notFound;
          request.response.write('{}');
        }
        await request.response.close();
      });
      addTearDown(() async {
        await server.close(force: true);
        await directory.delete(recursive: true);
      });

      final root = Uri.parse('http://127.0.0.1:${server.port}');
      final sync = DriveCloudSync(
        _TestAuth(),
        apiBase: root.resolve('/drive/v3/'),
        uploadBase: root.resolve('/upload/drive/v3/'),
      );
      final first = Library(File('${directory.path}/first.json'));
      first.songs['one'] = const Song(
        id: 'one',
        title: 'One',
        artist: 'Singer',
        lrc: '[00:01.00]One',
        updatedAt: 100,
      );
      final initial = await sync.sync(first);
      expect(initial.total, 1);
      expect(creations, 1);

      final second = Library(File('${directory.path}/second.json'));
      second.songs['two'] = const Song(
        id: 'two',
        title: 'Two',
        artist: 'Singer',
        lrc: '[00:02.00]Two',
        updatedAt: 200,
      );
      final merged = await sync.sync(second);
      expect(merged.imported, 1);
      expect(second.songs.keys, containsAll(['one', 'two']));
      expect(remoteSongs.length, 2);
      expect(updates, 1);
    },
  );
}
