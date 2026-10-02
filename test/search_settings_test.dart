import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyrics_float/online_lyrics.dart';
import 'package:lyrics_float/search_settings.dart';

void main() {
  test('remembers selected sources, including disabling all', () async {
    final directory = await Directory.systemTemp.createTemp('lyrics-settings-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/search_settings.json');
    final settings = SearchSettings(file);
    expect(settings.enabledSources, defaultOnlineLyricsSources);
    expect(settings.playbackSourceMode, PlaybackSourceMode.both);

    settings.enabledSources = {
      OnlineLyricsSource.lrclib,
      OnlineLyricsSource.lrcApi,
    };
    settings.playbackSourceMode = PlaybackSourceMode.spotify;
    settings.lyricsVisibleLines = 7;
    settings.lyricsFontSize = 34;
    await settings.save();
    final reloaded = SearchSettings(file);
    await reloaded.load();
    expect(reloaded.enabledSources, settings.enabledSources);
    expect(reloaded.playbackSourceMode, PlaybackSourceMode.spotify);
    expect(reloaded.lyricsVisibleLines, 7);
    expect(reloaded.lyricsFontSize, 34);

    reloaded.enabledSources = {};
    await reloaded.save();
    final disabled = SearchSettings(file);
    await disabled.load();
    expect(disabled.enabledSources, isEmpty);
    expect(disabled.playbackSourceMode, PlaybackSourceMode.spotify);
    expect(disabled.lyricsVisibleLines, 7);
    expect(disabled.lyricsFontSize, 34);
  });

  test('older settings keep both playback sources enabled', () async {
    final directory = await Directory.systemTemp.createTemp('lyrics-settings-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/search_settings.json');
    await file.writeAsString('{"enabledSources":["lrclib"]}');
    final settings = SearchSettings(file);
    await settings.load();
    expect(settings.playbackSourceMode, PlaybackSourceMode.both);
    expect(settings.lyricsVisibleLines, 3);
    expect(settings.lyricsFontSize, 28);
  });

  test('invalid lyric display settings fall back to defaults', () async {
    final directory = await Directory.systemTemp.createTemp('lyrics-settings-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/search_settings.json');
    await file.writeAsString(
      '{"lyricsVisibleLines":99,"lyricsFontSize":200}',
    );
    final settings = SearchSettings(file);
    await settings.load();
    expect(settings.lyricsVisibleLines, 3);
    expect(settings.lyricsFontSize, 28);
  });
}
