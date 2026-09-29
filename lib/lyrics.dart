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

/// Removes common video/audio suffixes and noise words from song titles.
String cleanTitle(String value) {
  var text = value;
  // 1. Remove bracketed / parenthesized noise like (Official Music Video), [MV], (Remastered 2021), etc.
  text = text.replaceAll(
    RegExp(
      r'[\(\[\{【『（［]\s*(?:official\s*(?:music\s*)?(?:video|audio|mv)|lyric\s*video|music\s*video|\bmv\b|\bhd\b|\b4k\b|\bhq\b|\baudio\b|remaster(?:ed)?(?:\s*\d+)?|\d{4}\s*remaster|radio\s*edit|(?:feat\.?|ft\.?)\s+[^\)\]\}】』）］]+)\s*[\)\]\}】』）］]',
      caseSensitive: false,
    ),
    ' ',
  );
  // 2. Remove standalone noise words at the end or after separators
  text = text.replaceAll(
    RegExp(
      r'(?:[-–—~|/]\s*)?(?:official\s*(?:music\s*)?(?:video|audio|mv)|lyric\s*video|music\s*video|\bMV\b|\bHD\b|\b4K\b|\bAudio\b|remaster(?:ed)?(?:\s*\d+)?|\d{4}\s*remaster)\s*$',
      caseSensitive: false,
    ),
    ' ',
  );
  // 3. Remove trailing feat./ft. clauses
  text = text.replaceAll(
    RegExp(r'\s*(?:[-–—]\s*)?(?:feat\.?|ft\.?)\s+.*$', caseSensitive: false),
    ' ',
  );
  // 4. Remove empty brackets
  text = text.replaceAll(RegExp(r'[\(\[\{【『（［]\s*[\)\]\}】』）］]'), ' ');
  // 5. Clean extra spaces
  text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  // 6. Clean trailing separators
  text = text.replaceAll(RegExp(r'[\s\-–—~|/]+$'), '').trim();
  return text.isNotEmpty ? text : value.trim();
}

/// Generates an ordered list of candidate search queries for a raw title.
List<String> candidateTitles(String rawTitle) {
  final results = <String>[];
  void add(String s) {
    final t = s.trim();
    if (t.isNotEmpty && !results.contains(t)) results.add(t);
  }

  final trimmed = rawTitle.trim();
  add(trimmed);
  final cleaned = cleanTitle(trimmed);
  add(cleaned);

  // Extract content inside brackets like 【...】, [...], 「...」, etc.
  final bracketMatch =
      RegExp(r'[【「『\[（\(](.*?)[】」』\]）\)]').firstMatch(trimmed);
  if (bracketMatch != null) {
    final inside = bracketMatch.group(1)?.trim() ?? '';
    final cleanedInside = cleanTitle(inside);
    add(cleanedInside);
    add(inside);

    // Split bilingual or compound titles inside brackets, e.g. "晴天 Sunny Day" or "晴天 / Sunny Day"
    final cjkMatches =
        RegExp(r'[\u4e00-\u9fff\u3400-\u4dbf]+').allMatches(inside);
    for (final m in cjkMatches) {
      final s = m.group(0)?.trim() ?? '';
      if (s.isNotEmpty) add(s);
    }
    final latinMatches = RegExp(r'[A-Za-z0-9\s]+').allMatches(inside);
    for (final m in latinMatches) {
      final s = m.group(0)?.trim() ?? '';
      if (s.isNotEmpty && s.length >= 2) add(s);
    }
    final insideDelimited = inside.split(RegExp(r'[\s/|\-]+'));
    for (final part in insideDelimited) {
      final cp = cleanTitle(part);
      if (cp.isNotEmpty) add(cp);
    }

    // Also try outside the bracket
    final outside = cleanTitle(
      trimmed.replaceAll(RegExp(r'[【「『\[（\(].*?[】」』\]）\)]'), ' '),
    );
    add(outside);
  }

  // If title contains " - ", try splitting parts (e.g., "Artist - Title" or "Title - Subtitle")
  if (cleaned.contains(RegExp(r'\s*[-–—]\s*'))) {
    final parts = cleaned.split(RegExp(r'\s*[-–—]\s*'));
    for (final part in parts) {
      add(cleanTitle(part));
    }
  }

  return results;
}

/// Splits multiple artists (e.g., "周杰倫 & 溫嵐", "Ed Sheeran feat. Khalid").
List<String> splitArtists(String raw) {
  final withoutTopic = raw.replaceFirst(
    RegExp(r'\s*[-–—]\s*Topic\s*$', caseSensitive: false),
    '',
  );
  return withoutTopic
      .split(
        RegExp(
          r'\s*(?:,|&|/|、|\bfeat\.?|\bft\.?|\bwith\b)\s*',
          caseSensitive: false,
        ),
      )
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
}

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
