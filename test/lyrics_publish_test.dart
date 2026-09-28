import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyrics_float/lyrics.dart';
import 'package:lyrics_float/lyrics_publish.dart';

const song = Song(
  id: 'song',
  title: 'Example',
  artist: 'Singer',
  lrc: '[00:01.00]First\n[00:03.00]Second',
  updatedAt: 1,
);

void main() {
  test('challenge solver produces a hash at or below the target', () async {
    const prefix = 'test-prefix';
    final target = sha256.convert(utf8.encode('${prefix}0')).toString();
    final nonce = await solvePublishChallenge(
      prefix,
      target,
      PublishCancellation(),
    );
    expect(nonce, '0');
  });

  test(
    'publishing sends metadata and synced LRC after one challenge',
    () async {
      final paths = <String>[];
      final publisher = LrclibPublisher(
        post: (uri, {headers, body}) async {
          paths.add(uri.path);
          if (uri.path == '/api/request-challenge') {
            return PublishResponse(200, {
              'prefix': 'prefix',
              'target': 'F' * 64,
            });
          }
          expect(headers?['X-Publish-Token'], 'prefix:42');
          final payload = body as Map;
          expect(payload['trackName'], 'Example');
          expect(payload['artistName'], 'Singer');
          expect(payload['albumName'], 'Album');
          expect(payload['duration'], 180.5);
          expect(payload['syncedLyrics'], song.lrc);
          return const PublishResponse(201, null);
        },
        solver: (_, _, _) async => '42',
      );
      await publisher.publish(
        song: song,
        album: 'Album',
        durationSeconds: 180.5,
        cancellation: PublishCancellation(),
      );
      expect(paths, ['/api/request-challenge', '/api/publish']);
    },
  );

  test('cancellation prevents the public publish request', () async {
    final cancel = PublishCancellation();
    var publishCalls = 0;
    final publisher = LrclibPublisher(
      post: (uri, {headers, body}) async {
        if (uri.path == '/api/publish') publishCalls++;
        return PublishResponse(200, {'prefix': 'prefix', 'target': 'F' * 64});
      },
      solver: (_, _, cancellation) async {
        cancellation.cancel();
        return '42';
      },
    );
    await expectLater(
      publisher.publish(
        song: song,
        album: 'Album',
        durationSeconds: 180,
        cancellation: cancel,
      ),
      throwsA(isA<PublishCancelled>()),
    );
    expect(publishCalls, 0);
  });
}
