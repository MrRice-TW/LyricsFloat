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
    await settings.save();
    final reloaded = SearchSettings(file);
    await reloaded.load();
    expect(reloaded.enabledSources, settings.enabledSources);
    expect(reloaded.playbackSourceMode, PlaybackSourceMode.spotify);

    reloaded.enabledSources = {};
    await reloaded.save();
    final disabled = SearchSettings(file);
    await disabled.load();
    expect(disabled.enabledSources, isEmpty);
    expect(disabled.playbackSourceMode, PlaybackSourceMode.spotify);
  });

  test('older settings keep both playback sources enabled', () async {
    final directory = await Directory.systemTemp.createTemp('lyrics-settings-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/search_settings.json');
    await file.writeAsString('{"enabledSources":["lrclib"]}');
    final settings = SearchSettings(file);
    await settings.load();
    expect(settings.playbackSourceMode, PlaybackSourceMode.both);
  });
}
