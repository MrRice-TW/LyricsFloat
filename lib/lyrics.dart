import 'dart:convert';
import 'dart:io';

class LyricLine {
  const LyricLine(this.timeMs, this.text);
  final int timeMs;
  final String text;
}

class KaraokeLines {
  const KaraokeLines(this.top, this.bottom, this.active);

  final String top;
  final String bottom;
  final int active;
}

KaraokeLines karaokeLines(List<LyricLine> lines, int currentIndex) {
  if (lines.isEmpty) return const KaraokeLines('', '', -1);
  if (currentIndex < 0) {
    return KaraokeLines('', lines[0].text, -1);
  }
  return KaraokeLines(
    lines[currentIndex].text,
    currentIndex + 1 < lines.length ? lines[currentIndex + 1].text : '',
    0,
  );
}

class Lrc {
  static final _stamp = RegExp(r'\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]');

  static List<LyricLine> parse(String source) {
    final lines = <LyricLine>[];
    for (final raw in source.split(RegExp(r'\r?\n'))) {
      final matches = _stamp.allMatches(raw).toList();
      if (matches.isEmpty) continue;
      final text = raw.substring(matches.last.end).trim();
      if (text.isEmpty) continue;
      for (final match in matches) {
        final fraction = (match.group(3) ?? '0')
            .padRight(3, '0')
            .substring(0, 3);
        final ms =
            int.parse(match.group(1)!) * 60000 +
            int.parse(match.group(2)!) * 1000 +
            int.parse(fraction);
        lines.add(LyricLine(ms, text));
      }
    }
    lines.sort((a, b) => a.timeMs.compareTo(b.timeMs));
    return lines;
  }
}

String normalized(String value) => value
    .toLowerCase()
    .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
    .trim();

String normalizedArtist(String value) => normalized(
  value.replaceFirst(RegExp(r'\s*[-–—]\s*Topic\s*$', caseSensitive: false), ''),
);

class Song {
  const Song({
    required this.id,
    required this.title,
    required this.artist,
    required this.lrc,
    required this.updatedAt,
    this.source = 'manual',
    this.album = '',
    this.durationMs = 0,
    this.lyricOffsetMs = 0,
  });
  final String id;
  final String title;
  final String artist;
  final String lrc;
  final int updatedAt;
  final String source;
  final String album;
  final int durationMs;
  final int lyricOffsetMs;
  Song copyWith({int? updatedAt, int? lyricOffsetMs}) => Song(
    id: id,
    title: title,
    artist: artist,
    lrc: lrc,
    updatedAt: updatedAt ?? this.updatedAt,
    source: source,
    album: album,
    durationMs: durationMs,
    lyricOffsetMs: lyricOffsetMs ?? this.lyricOffsetMs,
  );
  String get key => '${normalized(title)}|${normalizedArtist(artist)}';
  List<LyricLine> get lines => Lrc.parse(lrc);
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'artist': artist,
    'lrc': lrc,
    'updatedAt': updatedAt,
    'source': source,
    'album': album,
    'durationMs': durationMs,
    'lyricOffsetMs': lyricOffsetMs,
  };
  factory Song.fromJson(Map<String, dynamic> json) => Song(
    id: json['id'] as String,
    title: json['title'] as String,
    artist: json['artist'] as String,
    lrc: json['lrc'] as String,
    updatedAt: json['updatedAt'] as int,
    source: json['source'] as String? ?? 'manual',
    album: json['album'] as String? ?? '',
    durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
    lyricOffsetMs: (json['lyricOffsetMs'] as num?)?.toInt() ?? 0,
  );
}

class Library {
  Library(this.file);
  final File file;
  final Map<String, Song> songs = {};

  Future<void> load() async {
    final source = await file.exists() ? file : File('${file.path}.bak');
    if (!await source.exists()) return;
    final document =
        jsonDecode(await source.readAsString()) as Map<String, dynamic>;
    for (final raw in document['songs'] as List<dynamic>? ?? []) {
      final song = Song.fromJson(Map<String, dynamic>.from(raw as Map));
      songs[song.id] = song;
    }
  }

  Future<void> save() async {
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(jsonEncode({'version': 1, 'songs': export()}));
    final backup = File('${file.path}.bak');
    if (await backup.exists()) await backup.delete();
    if (await file.exists()) await file.rename(backup.path);
    await temp.rename(file.path);
  }

  Future<int> merge(List<dynamic> incoming) async {
    var changed = 0;
    for (final raw in incoming) {
      final song = Song.fromJson(Map<String, dynamic>.from(raw as Map));
      final old = songs[song.id];
      if (old == null || song.updatedAt > old.updatedAt) {
        if (old != null && old.lrc != song.lrc) {
          final backupId = '${old.id}#conflict#${old.updatedAt}';
          songs[backupId] = Song(
            id: backupId,
            title: old.title,
            artist: old.artist,
            lrc: old.lrc,
            updatedAt: old.updatedAt,
            source: old.source,
            album: old.album,
            durationMs: old.durationMs,
            lyricOffsetMs: old.lyricOffsetMs,
          );
        }
        songs[song.id] = song;
        changed++;
      } else if (song.updatedAt == old.updatedAt && song.lrc != old.lrc) {
        final conflictId = '${song.id}#conflict#${song.updatedAt}';
        songs[conflictId] = Song(
          id: conflictId,
          title: song.title,
          artist: song.artist,
          lrc: song.lrc,
          updatedAt: song.updatedAt,
          source: song.source,
          album: song.album,
          durationMs: song.durationMs,
          lyricOffsetMs: song.lyricOffsetMs,
        );
        changed++;
      }
    }
    if (changed > 0) await save();
    return changed;
  }

  List<dynamic> export() => songs.values.map((s) => s.toJson()).toList();
}
