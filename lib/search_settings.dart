import 'dart:convert';
import 'dart:io';

import 'online_lyrics.dart';

enum PlaybackSourceMode {
  spotify('Spotify'),
  youtube('YouTube／瀏覽器媒體'),
  both('Spotify 與 YouTube');

  const PlaybackSourceMode(this.label);
  final String label;
}

class SearchSettings {
  SearchSettings(this.file);

  final File file;
  Set<OnlineLyricsSource> enabledSources = {...defaultOnlineLyricsSources};
  PlaybackSourceMode playbackSourceMode = PlaybackSourceMode.both;

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
      }),
    );
    if (await file.exists()) await file.delete();
    await temp.rename(file.path);
  }
}
