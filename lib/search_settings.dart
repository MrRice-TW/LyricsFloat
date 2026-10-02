import 'dart:convert';
import 'dart:io';

import 'online_lyrics.dart';

enum PlaybackSourceMode {
  spotify('Spotify／桌面音樂軟體'),
  youtube('YouTube／瀏覽器媒體'),
  both('所有支援的音樂與瀏覽器');

  const PlaybackSourceMode(this.label);
  final String label;
}

class SearchSettings {
  SearchSettings(this.file);

  final File file;
  Set<OnlineLyricsSource> enabledSources = {...defaultOnlineLyricsSources};
  PlaybackSourceMode playbackSourceMode = PlaybackSourceMode.both;
  int lyricsVisibleLines = 3;
  double lyricsFontSize = 28;

  Future<void> load() async {
    if (!await file.exists()) return;
    try {
      final data = jsonDecode(await file.readAsString());
      if (data is! Map) return;
      if (data['enabledSources'] is List) {
        final names = (data['enabledSources'] as List)
            .whereType<String>()
            .toSet();
        enabledSources = OnlineLyricsSource.values
            .where((source) => names.contains(source.name))
            .toSet();
      }
      final mode = data['playbackSourceMode'];
      for (final candidate in PlaybackSourceMode.values) {
        if (candidate.name == mode) playbackSourceMode = candidate;
      }
      final visibleLines = data['lyricsVisibleLines'];
      if (visibleLines is int && {3, 5, 7}.contains(visibleLines)) {
        lyricsVisibleLines = visibleLines;
      }
      final fontSize = data['lyricsFontSize'];
      if (fontSize is num && fontSize >= 18 && fontSize <= 40) {
        lyricsFontSize = fontSize.toDouble();
      }
    } on FormatException {
      // Keep defaults when a settings file is incomplete or damaged.
    }
  }

  Future<void> save() async {
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(
      jsonEncode({
        'enabledSources': enabledSources.map((source) => source.name).toList(),
        'playbackSourceMode': playbackSourceMode.name,
        'lyricsVisibleLines': lyricsVisibleLines,
        'lyricsFontSize': lyricsFontSize,
      }),
    );
    if (await file.exists()) await file.delete();
    await temp.rename(file.path);
  }
}
