import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyrics_float/lyrics.dart';

void main() {
  test('artist key ignores a trailing YouTube Topic label', () {
    expect(normalizedArtist('JBMS大熊 - Topic'), normalizedArtist('JBMS大熊'));
  });
  test('LRC accepts multiple timestamps and orders lines by time', () {
    final lines = Lrc.parse('[00:03.25]第二句\n[00:01.5][00:02.50]第一句');
    expect(lines.map((line) => line.timeMs), [1500, 2500, 3250]);
    expect(lines.map((line) => line.text), ['第一句', '第一句', '第二句']);
  });

  test('floating lyrics keep the current line above the next line', () {
    final lines = Lrc.parse(
      '[00:01.00]First\n[00:02.00]Second\n[00:03.00]Third',
    );
    expect(karaokeLines(lines, -1).top, '');
    expect(karaokeLines(lines, -1).bottom, 'First');
    expect(karaokeLines(lines, -1).active, -1);
    expect(karaokeLines(lines, 0).top, 'First');
    expect(karaokeLines(lines, 0).bottom, 'Second');
    expect(karaokeLines(lines, 0).active, 0);
    expect(karaokeLines(lines, 1).top, 'Second');
    expect(karaokeLines(lines, 1).bottom, 'Third');
    expect(karaokeLines(lines, 1).active, 0);
    expect(karaokeLines(lines, 2).top, 'Third');
    expect(karaokeLines(lines, 2).bottom, '');
    expect(karaokeLines(lines, 2).active, 0);
  });

  test('library persists and merges a newer edit', () async {
    final directory = await Directory.systemTemp.createTemp(
      'lyrics_float_test_',
    );
    try {
      final file = File('${directory.path}/lyrics.json');
      final library = Library(file);
      library.songs['song'] = const Song(
        id: 'song',
        title: '歌',
        artist: '人',
        lrc: '[00:01.00]舊',
        updatedAt: 1,
        album: '專輯',
        durationMs: 180500,
        lyricOffsetMs: 500,
      );
      await library.save();
      final loaded = Library(file);
      await loaded.load();
      expect(loaded.songs['song']?.lines.single.text, '舊');
      expect(loaded.songs['song']?.album, '專輯');
      expect(loaded.songs['song']?.durationMs, 180500);
      expect(loaded.songs['song']?.lyricOffsetMs, 500);
      final count = await loaded.merge([
        const Song(
          id: 'song',
          title: '歌',
          artist: '人',
          lrc: '[00:01.00]新',
          updatedAt: 2,
        ).toJson(),
      ]);
      expect(count, 1);
      expect(loaded.songs['song']?.lines.single.text, '新');
      expect(loaded.songs['song#conflict#1']?.lines.single.text, '舊');
      expect(loaded.songs['song#conflict#1']?.album, '專輯');
      expect(loaded.songs['song#conflict#1']?.lyricOffsetMs, 500);
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test('older saved songs default to no lyric offset', () {
    final song = Song.fromJson({
      'id': 'old',
      'title': '歌',
      'artist': '人',
      'lrc': '[00:01.00]一句',
      'updatedAt': 1,
    });
    expect(song.lyricOffsetMs, 0);
    expect(song.copyWith(lyricOffsetMs: 500).toJson()['lyricOffsetMs'], 500);
  });
}
