import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'lyrics.dart';
import 'lyrics_publish.dart';
import 'online_lyrics.dart';
import 'search_settings.dart';

const native = MethodChannel('lyrics_float/native');

class Playback {
  Playback(Map<dynamic, dynamic> data)
    : title = (data['title'] ?? '') as String,
      artist = (data['artist'] ?? '') as String,
      album = (data['album'] ?? '') as String,
      source = (data['source'] ?? '') as String,
      positionMs = (data['positionMs'] as num?)?.toInt() ?? 0,
      durationMs = (data['durationMs'] as num?)?.toInt() ?? 0,
      playing = data['isPlaying'] == true,
      sampledAt = DateTime.now();
  final String title, artist, album, source;
  final int positionMs;
  final int durationMs;
  final bool playing;
  final DateTime sampledAt;
  int get currentMs => max(
    0,
    positionMs +
        (playing ? DateTime.now().difference(sampledAt).inMilliseconds : 0),
  );
}

class LyricsFloatApp extends StatelessWidget {
  const LyricsFloatApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'LyricsFloat',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF7567EA),
        brightness: Brightness.dark,
      ),
      useMaterial3: true,
    ),
    home: const HomePage(),
  );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Library? library;
  SearchSettings? searchSettings;
  Playback? playback;
  Timer? timer;
  HttpServer? server;
  String pairingCode = '';
  String localAddresses = '查詢中…';
  final Map<String, int> failedPairings = {};
  String? error;
  String? playbackError;
  bool compact = false;
  bool overlay = false;
  bool mediaAccess = false;
  bool polling = false;
  bool savingLyricOffset = false;
  final OnlineLyricsLookup onlineLookup = OnlineLyricsLookup();
  final LrclibPublisher publisher = LrclibPublisher();
  bool publishing = false;
  final Map<String, DateTime> nextOnlineAttempt = {};
  Timer? onlineSearchTimer;
  String? pendingOnlineKey;
  String? runningOnlineKey;
  String? onlineStatus;
  String? onlineStatusKey;
  Song? previewSong;
  List<OnlineLyrics> manualCandidates = [];
  bool manualSearchOpen = false;
  String? manualSearchKey;
  String manualSearchTitle = '';
  String manualSearchArtist = '';

  @override
  void initState() {
    super.initState();
    if (Platform.isAndroid) {
      native.setMethodCallHandler((call) async {
        if (call.method == 'overlayClosed' && mounted) {
          setState(() => overlay = false);
        }
      });
    }
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      final path = await native.invokeMethod<String>('getStoragePath');
      if (path == null) throw StateError('找不到儲存位置');
      final loaded = Library(File('$path/lyrics.json'));
      await loaded.load();
      final loadedSettings = SearchSettings(File('$path/search_settings.json'));
      await loadedSettings.load();
      final random = Random.secure();
      pairingCode = List.generate(8, (_) => random.nextInt(10)).join();
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      localAddresses = interfaces
          .expand((item) => item.addresses)
          .map((address) => address.address)
          .toSet()
          .join('、');
      if (localAddresses.isEmpty) localAddresses = '請查看裝置的 Wi-Fi 設定';
      try {
        server = await HttpServer.bind(InternetAddress.anyIPv4, 39847);
        server!.listen(_serve);
      } on SocketException {
        error = '同步連接埠 39847 無法使用';
      }
      if (!mounted) return;
      setState(() {
        library = loaded;
        searchSettings = loadedSettings;
      });
      timer = Timer.periodic(const Duration(milliseconds: 500), (_) => _tick());
      await _tick();
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  Future<void> _serve(HttpRequest request) async {
    request.response.headers.contentType = ContentType.json;
    final remote = request.connectionInfo?.remoteAddress.address ?? 'unknown';
    if ((failedPairings[remote] ?? 0) >= 5) {
      request.response.statusCode = HttpStatus.tooManyRequests;
    } else if (request.uri.path != '/v1/sync' ||
        request.uri.queryParameters['code'] != pairingCode ||
        library == null) {
      failedPairings[remote] = (failedPairings[remote] ?? 0) + 1;
      request.response.statusCode = HttpStatus.forbidden;
    } else if (request.method == 'POST') {
      try {
        final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
        await library!.merge(body['songs'] as List<dynamic>);
        if (mounted) setState(() {});
        request.response.write(jsonEncode({'songs': library!.export()}));
      } catch (_) {
        request.response.statusCode = HttpStatus.badRequest;
      }
    } else {
      request.response.statusCode = HttpStatus.methodNotAllowed;
    }
    await request.response.close();
  }

  Future<void> _tick() async {
    if (polling) return;
    polling = true;
    try {
      if (Platform.isAndroid) {
        mediaAccess =
            await native.invokeMethod<bool>('hasMediaAccess') ?? false;
      }
      final data = await native.invokeMapMethod<dynamic, dynamic>(
        'getPlayback',
        {'sourceMode': searchSettings?.playbackSourceMode.name ?? 'both'},
      );
      if (!mounted) return;
      final updated = data == null ? null : Playback(data);
      setState(() {
        playback = updated;
        playbackError = null;
        if (previewSong != null &&
            (updated == null ||
                '${normalized(updated.title)}|${normalizedArtist(updated.artist)}' !=
                    previewSong!.key)) {
          previewSong = null;
        }
      });
      _considerOnlineSearch();
      await _updateOverlay();
    } on PlatformException catch (e) {
      if (mounted) {
        setState(() {
          playback = null;
          playbackError = e.message;
        });
      }
    } finally {
      polling = false;
    }
  }

  Song? get currentSong {
    final p = playback;
    if (p == null || library == null) return null;
    final key = '${normalized(p.title)}|${normalizedArtist(p.artist)}';
    if (previewSong?.key == key) return previewSong;
    for (final song in library!.songs.values) {
      if (!song.id.contains('#conflict#') && song.key == key) return song;
    }
    return null;
  }

  void _considerOnlineSearch() {
    if (manualSearchOpen) return;
    final p = playback;
    if (p == null || currentSong != null) {
      onlineSearchTimer?.cancel();
      pendingOnlineKey = null;
      if (onlineStatus != null) setState(() => onlineStatus = null);
      onlineStatusKey = null;
      return;
    }
    if (searchSettings?.enabledSources.isEmpty ?? true) {
      onlineSearchTimer?.cancel();
      pendingOnlineKey = null;
      if (onlineStatus != '已關閉線上歌詞搜尋') {
        setState(() => onlineStatus = '已關閉線上歌詞搜尋');
      }
      return;
    }
    if (p.title.trim().isEmpty || p.artist.trim().isEmpty) return;
    final key = '${normalized(p.title)}|${normalizedArtist(p.artist)}';
    if (onlineStatusKey != key) {
      onlineStatusKey = key;
      if (onlineStatus != null) setState(() => onlineStatus = null);
    }
    if (pendingOnlineKey == key || runningOnlineKey != null) return;
    final next = nextOnlineAttempt[key];
    if (next != null && DateTime.now().isBefore(next)) return;
    onlineSearchTimer?.cancel();
    pendingOnlineKey = key;
    setState(() => onlineStatus = '即將搜尋動態歌詞…');
    onlineSearchTimer = Timer(
      const Duration(milliseconds: 900),
      () => _searchOnline(p, key),
    );
  }

  Future<void> _searchOnline(Playback track, String key) async {
    pendingOnlineKey = null;
    if (!mounted ||
        manualSearchOpen ||
        currentSong != null ||
        '${normalized(playback?.title ?? '')}|${normalizedArtist(playback?.artist ?? '')}' !=
            key) {
      return;
    }
    runningOnlineKey = key;
    setState(() => onlineStatus = '正在搜尋動態歌詞…');
    try {
      final selectedSources = Set<OnlineLyricsSource>.of(
        searchSettings!.enabledSources,
      );
      final result = await onlineLookup.find(
        title: track.title,
        artist: track.artist,
        durationMs: track.durationMs,
        enabledSources: selectedSources,
      );
      if (!mounted ||
          manualSearchOpen ||
          currentSong != null ||
          '${normalized(playback?.title ?? '')}|${normalizedArtist(playback?.artist ?? '')}' !=
              key) {
        return;
      }
      if (result == null) {
        nextOnlineAttempt[key] = DateTime.now().add(const Duration(hours: 1));
        setState(() => onlineStatus = '沒有找到相符的動態歌詞');
        return;
      }
      if (!searchSettings!.enabledSources.any(
        (source) => source.label == result.source,
      )) {
        return;
      }
      library!.songs[key] = Song(
        id: key,
        title: track.title,
        artist: track.artist,
        lrc: result.lrc,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        source: result.source,
        album: result.album,
        durationMs: result.durationMs,
      );
      await library!.save();
      if (mounted) setState(() => onlineStatus = null);
    } catch (_) {
      nextOnlineAttempt[key] = DateTime.now().add(const Duration(minutes: 5));
      if (mounted && currentSong == null && onlineStatusKey == key) {
        setState(() => onlineStatus = '暫時無法連線搜尋歌詞');
      }
    } finally {
      runningOnlineKey = null;
      if (mounted) _considerOnlineSearch();
    }
  }

  void _retryOnlineSearch() {
    final p = playback;
    if (p == null) return;
    nextOnlineAttempt.remove(
      '${normalized(p.title)}|${normalizedArtist(p.artist)}',
    );
    _considerOnlineSearch();
  }

  Future<void> _manualSearchDialog() async {
    final track = playback;
    if (track == null) return;
    final key = '${normalized(track.title)}|${normalizedArtist(track.artist)}';
    final sameSearch = manualSearchKey == key;
    final title = TextEditingController(
      text: sameSearch ? manualSearchTitle : track.title,
    );
    final artist = TextEditingController(
      text: sameSearch
          ? manualSearchArtist
          : track.artist
                .replaceFirst(
                  RegExp(r'\s*[-–—]\s*Topic\s*$', caseSensitive: false),
                  '',
                )
                .trim(),
    );
    var candidates = sameSearch
        ? List<OnlineLyrics>.of(manualCandidates)
        : <OnlineLyrics>[];
    var searching = false;
    String? status;
    manualSearchOpen = true;
    onlineSearchTimer?.cancel();
    pendingOnlineKey = null;
    final chosen = await showDialog<OnlineLyrics>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, refresh) {
          Future<void> search() async {
            if (searching) return;
            final queryTitle = title.text.trim();
            final queryArtist = artist.text.trim();
            if (queryTitle.isEmpty || queryArtist.isEmpty) {
              refresh(() => status = '請填寫歌名與歌手');
              return;
            }
            final enabled = Set<OnlineLyricsSource>.of(
              searchSettings?.enabledSources ?? defaultOnlineLyricsSources,
            );
            if (enabled.isEmpty) {
              refresh(() => status = '請先在「歌詞搜尋來源」啟用至少一個來源');
              return;
            }
            refresh(() {
              searching = true;
              candidates = [];
              status = '正在搜尋各個來源…';
            });
            final found = await onlineLookup.findAll(
              title: queryTitle,
              artist: queryArtist,
              durationMs: track.durationMs,
              enabledSources: enabled,
            );
            if (!dialogContext.mounted) return;
            refresh(() {
              searching = false;
              candidates = found;
              status = found.isEmpty ? '沒有找到相符的動態歌詞，可修改歌名再試' : null;
            });
            manualSearchKey = key;
            manualSearchTitle = queryTitle;
            manualSearchArtist = queryArtist;
            manualCandidates = found;
          }

          return AlertDialog(
            title: const Text('手動搜尋動態歌詞'),
            content: SizedBox(
              width: 520,
              height: min(MediaQuery.sizeOf(context).height * 0.55, 420),
              child: Column(
                children: [
                  TextField(
                    controller: title,
                    enabled: !searching,
                    decoration: const InputDecoration(labelText: '歌曲名稱'),
                    onSubmitted: (_) => search(),
                    onChanged: (_) => refresh(() {
                      candidates = [];
                      status = null;
                    }),
                  ),
                  TextField(
                    controller: artist,
                    enabled: !searching,
                    decoration: const InputDecoration(labelText: '歌手'),
                    onSubmitted: (_) => search(),
                    onChanged: (_) => refresh(() {
                      candidates = [];
                      status = null;
                    }),
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      onPressed: searching ? null : search,
                      icon: const Icon(Icons.search),
                      label: const Text('搜尋'),
                    ),
                  ),
                  if (status != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(status!, textAlign: TextAlign.center),
                    ),
                  if (searching) const LinearProgressIndicator(),
                  Expanded(
                    child: ListView.builder(
                      itemCount: candidates.length,
                      itemBuilder: (context, index) {
                        final candidate = candidates[index];
                        final seconds = candidate.durationMs ~/ 1000;
                        final duration = seconds > 0
                            ? '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}'
                            : '長度未知';
                        return ListTile(
                          title: Text(candidate.source),
                          subtitle: Text(
                            '${candidate.title} · ${candidate.artist}\n$duration${candidate.album.isEmpty ? '' : ' · ${candidate.album}'}',
                          ),
                          isThreeLine: true,
                          trailing: const Text('試套用'),
                          onTap: () => Navigator.pop(dialogContext, candidate),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('關閉'),
              ),
            ],
          );
        },
      ),
    );
    title.dispose();
    artist.dispose();
    manualSearchOpen = false;
    if (!mounted) return;
    if (chosen != null &&
        '${normalized(playback?.title ?? '')}|${normalizedArtist(playback?.artist ?? '')}' ==
            key) {
      setState(() {
        previewSong = Song(
          id: key,
          title: track.title,
          artist: track.artist,
          lrc: chosen.lrc,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
          source: chosen.source,
          album: chosen.album,
          durationMs: chosen.durationMs,
        );
        onlineStatus = null;
      });
      _updateOverlay();
    } else {
      _considerOnlineSearch();
    }
  }

  Future<void> _confirmPreview() async {
    final candidate = previewSong;
    final store = library;
    if (candidate == null || store == null) return;
    final previous = store.songs[candidate.id];
    store.songs[candidate.id] = candidate;
    try {
      await store.save();
      if (mounted) {
        setState(() => previewSong = null);
        _message('歌詞已儲存');
      }
    } catch (_) {
      if (previous == null) {
        store.songs.remove(candidate.id);
      } else {
        store.songs[candidate.id] = previous;
      }
      if (mounted) _message('歌詞儲存失敗，請再試一次');
    }
  }

  void _cancelPreview() {
    setState(() => previewSong = null);
    _updateOverlay();
  }

  int get currentLine {
    final lines = currentSong?.lines ?? [];
    final at = (playback?.currentMs ?? 0) + (currentSong?.lyricOffsetMs ?? 0);
    var index = -1;
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].timeMs > at) break;
      index = i;
    }
    return index;
  }

  Future<void> _adjustLyricOffset(int changeMs) async {
    if (savingLyricOffset) return;
    final song = currentSong;
    if (song == null) return;
    final nextOffset = (song.lyricOffsetMs + changeMs).clamp(-10000, 10000);
    final updated = song.copyWith(
      lyricOffsetMs: nextOffset,
      updatedAt: max(DateTime.now().millisecondsSinceEpoch, song.updatedAt + 1),
    );
    if (identical(previewSong, song)) {
      setState(() => previewSong = updated);
      await _updateOverlay();
      return;
    }
    final store = library;
    if (store == null) return;
    setState(() {
      savingLyricOffset = true;
      store.songs[song.id] = updated;
    });
    try {
      await store.save();
      await _updateOverlay();
    } catch (_) {
      store.songs[song.id] = song;
      _message('歌詞時間儲存失敗，請再試一次');
    } finally {
      if (mounted) setState(() => savingLyricOffset = false);
    }
  }

  Future<void> _updateOverlay() async {
    if (!overlay) return;
    final pair = karaokeLines(currentSong?.lines ?? [], currentLine);
    try {
      await native.invokeMethod('updateOverlay', {
        'top': pair.top,
        'bottom': pair.bottom,
        'active': pair.active,
      });
    } catch (_) {}
  }

  Future<void> _toggleOverlay() async {
    try {
      final enabled = await native.invokeMethod<bool>('setOverlay', {
        'enabled': !overlay,
      });
      if (!mounted) return;
      setState(() => overlay = enabled == true);
      await _updateOverlay();
    } on PlatformException catch (e) {
      _message(e.message ?? '無法開啟浮窗');
    }
  }

  Future<void> _toggleCompact() async {
    final next = !compact;
    await native.invokeMethod('setCompact', {'enabled': next});
    if (mounted) setState(() => compact = next);
  }

  void _message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> _importSong([Song? existing]) async {
    final title = TextEditingController(
      text: existing?.title ?? playback?.title ?? '',
    );
    final artist = TextEditingController(
      text: existing?.artist ?? playback?.artist ?? '',
    );
    final lrc = TextEditingController(text: existing?.lrc ?? '');
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(existing == null ? '匯入動態歌詞' : '編輯動態歌詞'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: title,
                  decoration: const InputDecoration(labelText: '歌曲名稱'),
                ),
                TextField(
                  controller: artist,
                  decoration: const InputDecoration(labelText: '歌手'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: lrc,
                  minLines: 8,
                  maxLines: 14,
                  decoration: const InputDecoration(
                    labelText: 'LRC 歌詞',
                    hintText: '[00:12.50]第一句歌詞',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('儲存'),
          ),
        ],
      ),
    );
    if (saved != true) return;
    if (title.text.trim().isEmpty || Lrc.parse(lrc.text).isEmpty) {
      _message('請填寫歌名與至少一行含時間標記的 LRC 歌詞');
      return;
    }
    final id = '${normalized(title.text)}|${normalizedArtist(artist.text)}';
    if (existing != null && existing.id != id) {
      library!.songs.remove(existing.id);
    }
    final matchingPlayback =
        playback != null &&
            '${normalized(playback!.title)}|${normalizedArtist(playback!.artist)}' ==
                id
        ? playback
        : null;
    final savedSong = Song(
      id: id,
      title: title.text.trim(),
      artist: artist.text.trim(),
      lrc: lrc.text,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
      album: existing?.album.isNotEmpty == true
          ? existing!.album
          : matchingPlayback?.album ?? '',
      durationMs: existing?.durationMs != null && existing!.durationMs > 0
          ? existing.durationMs
          : matchingPlayback?.durationMs ?? 0,
      lyricOffsetMs: existing?.lyricOffsetMs ?? 0,
    );
    library!.songs[id] = savedSong;
    await library!.save();
    if (mounted) setState(() {});
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('歌詞已儲存到本機'),
          action: SnackBarAction(
            label: '發布到 LRCLIB',
            onPressed: () => _publishSong(savedSong),
          ),
        ),
      );
    }
  }

  Future<void> _publishSong(Song song) async {
    if (publishing || library == null) return;
    final latest = library!.songs[song.id];
    if (latest == null || latest.source != 'manual') {
      _message('請先儲存這首歌的手動歌詞，再發布到 LRCLIB');
      return;
    }
    song = latest;
    final matchingPlayback =
        playback != null &&
            '${normalized(playback!.title)}|${normalizedArtist(playback!.artist)}' ==
                song.key
        ? playback
        : null;
    final album = TextEditingController(
      text: song.album.isNotEmpty ? song.album : matchingPlayback?.album ?? '',
    );
    final durationMs = song.durationMs > 0
        ? song.durationMs
        : matchingPlayback?.durationMs ?? 0;
    final duration = TextEditingController(
      text: durationMs > 0 ? (durationMs / 1000).toStringAsFixed(1) : '',
    );
    String? validation;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, refresh) => AlertDialog(
          title: const Text('發布到 LRCLIB'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('${song.title} · ${song.artist}'),
                  const SizedBox(height: 12),
                  TextField(
                    controller: album,
                    decoration: const InputDecoration(labelText: '專輯名稱'),
                  ),
                  TextField(
                    controller: duration,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: '歌曲長度（秒）',
                      hintText: '例如 213.5',
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '這份歌詞會公開給其他人使用。同一首歌再次發布會新增修訂版本；專輯或長度不同可能建立另一首歌。請確認資料正確，且你有權分享。',
                  ),
                  const SizedBox(height: 8),
                  Container(
                    height: 130,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white24),
                    ),
                    child: SingleChildScrollView(
                      child: SelectableText(song.lrc),
                    ),
                  ),
                  if (validation != null)
                    Text(
                      validation!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final seconds = double.tryParse(duration.text.trim());
                if (album.text.trim().isEmpty ||
                    seconds == null ||
                    !seconds.isFinite ||
                    seconds <= 0 ||
                    Lrc.parse(song.lrc).isEmpty) {
                  refresh(() => validation = '請填寫專輯、有效的歌曲長度與動態歌詞');
                  return;
                }
                Navigator.pop(dialogContext, true);
              },
              child: const Text('確認公開發布'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    final seconds = double.parse(duration.text.trim());
    final updated = Song(
      id: song.id,
      title: song.title,
      artist: song.artist,
      lrc: song.lrc,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
      source: song.source,
      album: album.text.trim(),
      durationMs: (seconds * 1000).round(),
      lyricOffsetMs: song.lyricOffsetMs,
    );
    library!.songs[song.id] = updated;
    await library!.save();
    if (!mounted) return;
    setState(() => publishing = true);
    final cancellation = PublishCancellation();
    final status = ValueNotifier<String>('正在準備投稿…');
    final ready = Completer<BuildContext>();
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        if (!ready.isCompleted) ready.complete(dialogContext);
        return ValueListenableBuilder<String>(
          valueListenable: status,
          builder: (context, message, _) => AlertDialog(
            title: const Text('發布到 LRCLIB'),
            content: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(width: 16),
                Flexible(child: Text(message)),
              ],
            ),
            actions: message == '正在公開發布歌詞…'
                ? null
                : [
                    TextButton(
                      onPressed: () {
                        if (status.value == '正在公開發布歌詞…') return;
                        cancellation.cancel();
                        Navigator.pop(dialogContext);
                      },
                      child: const Text('取消'),
                    ),
                  ],
          ),
        );
      },
    );
    final progressContext = await ready.future;
    try {
      await publisher.publish(
        song: updated,
        album: updated.album,
        durationSeconds: seconds,
        cancellation: cancellation,
        onStatus: (message) => status.value = message,
      );
      if (mounted) _message('歌詞已公開發布到 LRCLIB');
    } on PublishCancelled {
      // The user dismissed the progress dialog before the public request.
    } on PublishException catch (e) {
      if (mounted) _message(e.message);
    } catch (_) {
      if (mounted) _message('無法連線到 LRCLIB，請稍後再試');
    } finally {
      if (progressContext.mounted) Navigator.pop(progressContext);
      status.dispose();
      if (mounted) setState(() => publishing = false);
    }
  }

  Future<void> _libraryDialog() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, refresh) => AlertDialog(
          title: const Text('已匯入歌詞'),
          content: SizedBox(
            width: 500,
            height: 360,
            child: library!.songs.isEmpty
                ? const Center(child: Text('還沒有歌詞，請先匯入 LRC'))
                : ListView(
                    children: library!.songs.values
                        .map(
                          (song) => ListTile(
                            title: Text(
                              song.id.contains('#conflict#')
                                  ? '${song.title}（衝突備份）'
                                  : song.title,
                            ),
                            subtitle: Text(song.artist),
                            onTap: () async {
                              Navigator.pop(dialogContext);
                              await _importSong(song);
                            },
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (song.source == 'manual' &&
                                    !song.id.contains('#conflict#'))
                                  IconButton(
                                    tooltip: '發布到 LRCLIB',
                                    icon: const Icon(Icons.publish),
                                    onPressed: () {
                                      Navigator.pop(dialogContext);
                                      _publishSong(song);
                                    },
                                  ),
                                IconButton(
                                  tooltip: '複製 LRC',
                                  icon: const Icon(Icons.copy),
                                  onPressed: () async {
                                    await Clipboard.setData(
                                      ClipboardData(text: song.lrc),
                                    );
                                    _message('LRC 已複製到剪貼簿');
                                  },
                                ),
                              ],
                            ),
                          ),
                        )
                        .toList(),
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('關閉'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _searchSourcesDialog() async {
    final settings = searchSettings;
    if (settings == null) return;
    final selected = Set<OnlineLyricsSource>.of(settings.enabledSources);
    final updated = await showDialog<Set<OnlineLyricsSource>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, refresh) => AlertDialog(
          title: const Text('歌詞搜尋來源'),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('依下列順序搜尋；找到相符歌詞後就停止。已匯入的歌詞仍會保留。'),
                const SizedBox(height: 8),
                for (final source in OnlineLyricsSource.values)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(source.label),
                    subtitle: switch (source) {
                      OnlineLyricsSource.musixmatch
                          when !onlineLookup.musixmatchConfigured =>
                        const Text('需先設定 MUSIXMATCH_API_KEY'),
                      OnlineLyricsSource.tencentCloud
                          when !onlineLookup.tencentConfigured =>
                        const Text('需先設定騰訊雲音速達憑證與應用資料'),
                      _ => null,
                    },
                    value: selected.contains(source),
                    onChanged:
                        ((source == OnlineLyricsSource.musixmatch &&
                                !onlineLookup.musixmatchConfigured) ||
                            (source == OnlineLyricsSource.tencentCloud &&
                                !onlineLookup.tencentConfigured))
                        ? null
                        : (checked) => refresh(() {
                            if (checked == true) {
                              selected.add(source);
                            } else {
                              selected.remove(source);
                            }
                          }),
                  ),
                const Text('全部取消勾選會停止線上搜尋。付費來源需要自行開通，並可能產生供應商費用。'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, selected),
              child: const Text('儲存'),
            ),
          ],
        ),
      ),
    );
    if (updated == null || !mounted) return;
    final previous = settings.enabledSources;
    settings.enabledSources = updated;
    try {
      await settings.save();
      nextOnlineAttempt.clear();
      onlineSearchTimer?.cancel();
      pendingOnlineKey = null;
      if (mounted) {
        setState(() => onlineStatus = null);
        _considerOnlineSearch();
      }
    } catch (_) {
      settings.enabledSources = previous;
      if (mounted) _message('無法儲存搜尋來源設定');
    }
  }

  Future<void> _playbackSourceDialog() async {
    final settings = searchSettings;
    if (settings == null) return;
    final selected = await showDialog<PlaybackSourceMode>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('抓取播放來源'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final mode in PlaybackSourceMode.values)
                ListTile(
                  title: Text(mode.label),
                  leading: Icon(
                    mode == settings.playbackSourceMode
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                  ),
                  onTap: () => Navigator.pop(dialogContext, mode),
                ),
              const SizedBox(height: 8),
              Text(
                Platform.isMacOS
                    ? 'Mac 版會讀取 Spotify 桌面版，以及 Chrome／Edge 的 YouTube Music 分頁。瀏覽器需開啟「允許 Apple Events 執行 JavaScript」。'
                    : '瀏覽器不提供分頁網址，因此選擇 YouTube 時也會抓取其他瀏覽器媒體。',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
        ],
      ),
    );
    if (selected == null || selected == settings.playbackSourceMode) return;
    final previous = settings.playbackSourceMode;
    settings.playbackSourceMode = selected;
    try {
      await settings.save();
    } catch (_) {
      settings.playbackSourceMode = previous;
      if (mounted) _message('無法儲存播放來源設定');
      return;
    }
    if (!mounted) return;
    onlineSearchTimer?.cancel();
    pendingOnlineKey = null;
    setState(() {
      playback = null;
      onlineStatus = null;
    });
    await _updateOverlay();
    await _tick();
  }

  Future<void> _syncDialog() async {
    final address = TextEditingController();
    final code = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('同一 Wi-Fi 同步歌詞'),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('本機 IP：$localAddresses'),
              Text('本機配對碼：$pairingCode　連接埠：39847'),
              const SizedBox(height: 8),
              const Text('在另一台裝置輸入這台裝置的區域網路 IP 與配對碼。兩台裝置都需開啟本 App。'),
              TextField(
                controller: address,
                decoration: const InputDecoration(labelText: '另一台裝置的 IP'),
              ),
              TextField(
                controller: code,
                decoration: const InputDecoration(labelText: '另一台裝置的八位配對碼'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('關閉'),
          ),
          FilledButton(
            onPressed: () async {
              final host = address.text.trim();
              if (InternetAddress.tryParse(host)?.type !=
                      InternetAddressType.IPv4 ||
                  !RegExp(r'^\d{8}$').hasMatch(code.text.trim())) {
                _message('請輸入有效的 IPv4 位址與八位配對碼');
                return;
              }
              try {
                final client = HttpClient()
                  ..connectionTimeout = const Duration(seconds: 5);
                final request = await client.postUrl(
                  Uri.parse(
                    'http://$host:39847/v1/sync?code=${code.text.trim()}',
                  ),
                );
                request.headers.contentType = ContentType.json;
                request.write(jsonEncode({'songs': library!.export()}));
                final response = await request.close();
                if (response.statusCode != 200) {
                  throw StateError('連線被拒絕，請檢查 IP 與配對碼');
                }
                final data =
                    jsonDecode(await utf8.decoder.bind(response).join()) as Map;
                final count = await library!.merge(
                  data['songs'] as List<dynamic>,
                );
                client.close();
                if (dialogContext.mounted) Navigator.pop(dialogContext);
                if (mounted) setState(() {});
                _message('同步完成，收到 $count 首新歌詞');
              } catch (e) {
                _message('同步失敗：$e');
              }
            },
            child: const Text('立即同步'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    timer?.cancel();
    onlineSearchTimer?.cancel();
    server?.close(force: true);
    if (Platform.isAndroid) native.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final song = currentSong;
    final lines = song?.lines ?? [];
    final index = currentLine;
    if ((Platform.isWindows || Platform.isMacOS) && compact) {
      final pair = karaokeLines(lines, index);
      return Scaffold(
        body: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 8, 8),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      playback == null
                          ? '尚未偵測到歌曲'
                          : '${playback!.title} · ${playback!.artist}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  IconButton(
                    tooltip: '關閉桌面歌詞',
                    onPressed: _toggleCompact,
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      pair.top.isEmpty ? '♪' : pair.top,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: pair.active == 0
                            ? const Color(0xFFFFD85B)
                            : Colors.white70,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      pair.bottom.isEmpty ? ' ' : pair.bottom,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: Colors.white70,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('LyricsFloat'),
        actions: [
          if (Platform.isWindows || Platform.isMacOS)
            IconButton(
              tooltip: compact ? '一般視窗' : '桌面歌詞視窗',
              onPressed: _toggleCompact,
              icon: Icon(
                compact ? Icons.open_in_full : Icons.picture_in_picture_alt,
              ),
            ),
          PopupMenuButton<String>(
            tooltip: '設定',
            icon: const Icon(Icons.settings_outlined),
            onSelected: (value) {
              if (value == 'media') native.invokeMethod('requestMediaAccess');
              if (value == 'overlay') _toggleOverlay();
              if (value == 'sources') _searchSourcesDialog();
              if (value == 'playback') _playbackSourceDialog();
            },
            itemBuilder: (context) => [
              if (Platform.isAndroid) ...[
                const PopupMenuItem(value: 'media', child: Text('授權播放資訊')),
                PopupMenuItem(
                  value: 'overlay',
                  child: Text(overlay ? '關閉歌詞浮窗' : '開啟歌詞浮窗'),
                ),
              ],
              const PopupMenuItem(value: 'sources', child: Text('歌詞搜尋來源')),
              const PopupMenuItem(value: 'playback', child: Text('抓取播放來源')),
            ],
          ),
          IconButton(
            tooltip: '輸入歌名搜尋歌詞',
            onPressed: library == null || playback == null
                ? null
                : _manualSearchDialog,
            icon: const Icon(Icons.search),
          ),
          IconButton(
            tooltip: '同步歌詞',
            onPressed: library == null || server == null ? null : _syncDialog,
            icon: const Icon(Icons.sync),
          ),
          IconButton(
            tooltip: '歌詞庫',
            onPressed: library == null ? null : _libraryDialog,
            icon: const Icon(Icons.library_music),
          ),
          IconButton(
            tooltip: '匯入 LRC',
            onPressed: library == null ? null : () => _importSong(),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: library == null
          ? Center(child: Text(error ?? '載入中…'))
          : Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    Platform.isAndroid && !mediaAccess
                        ? '需要播放資訊權限'
                        : playback == null
                        ? (Platform.isMacOS && playbackError != null
                              ? playbackError!
                              : '尚未偵測到已選來源的歌曲')
                        : '${playback!.title}  ·  ${playback!.artist}',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  if (Platform.isAndroid && !mediaAccess)
                    Center(
                      child: FilledButton.icon(
                        onPressed: () =>
                            native.invokeMethod('requestMediaAccess'),
                        icon: const Icon(Icons.music_note),
                        label: const Text('授權讀取播放資訊'),
                      ),
                    ),
                  if (playback != null)
                    Text(
                      '${playback!.source} · ${playback!.playing ? '播放中' : '已暫停'}',
                      textAlign: TextAlign.center,
                    ),
                  if (song != null && !identical(song, previewSong))
                    Center(
                      child: TextButton.icon(
                        onPressed: () => _importSong(song),
                        icon: const Icon(Icons.edit_note),
                        label: const Text('編輯目前歌詞'),
                      ),
                    ),
                  const SizedBox(height: 20),
                  Expanded(
                    child: Center(
                      child: song == null
                          ? Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  playback == null
                                      ? '播放歌曲後會在這裡顯示歌詞'
                                      : onlineStatus ?? '尚無這首歌的歌詞，可匯入 LRC',
                                  textAlign: TextAlign.center,
                                ),
                                if (playback != null &&
                                    onlineStatus != null &&
                                    !onlineStatus!.contains('正在') &&
                                    !onlineStatus!.contains('即將'))
                                  TextButton(
                                    onPressed: _retryOnlineSearch,
                                    child: const Text('重新搜尋'),
                                  ),
                                if (playback != null)
                                  OutlinedButton.icon(
                                    onPressed: _manualSearchDialog,
                                    icon: const Icon(Icons.search),
                                    label: const Text('輸入歌名搜尋'),
                                  ),
                              ],
                            )
                          : Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (index > 0)
                                  Text(
                                    lines[index - 1].text,
                                    textAlign: TextAlign.center,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(color: Colors.white54),
                                  ),
                                const SizedBox(height: 14),
                                Text(
                                  index >= 0 ? lines[index].text : '♪',
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineMedium
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 14),
                                if (index + 1 < lines.length)
                                  Text(
                                    lines[index + 1].text,
                                    textAlign: TextAlign.center,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(color: Colors.white54),
                                  ),
                              ],
                            ),
                    ),
                  ),
                  if (previewSong != null && song == previewSong)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Wrap(
                          alignment: WrapAlignment.center,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 8,
                          children: [
                            Text('試套用：${previewSong!.source} · 尚未儲存'),
                            TextButton(
                              onPressed: _manualSearchDialog,
                              child: const Text('換一份'),
                            ),
                            TextButton(
                              onPressed: _cancelPreview,
                              child: const Text('取消'),
                            ),
                            FilledButton(
                              onPressed: _confirmPreview,
                              child: const Text('確認儲存'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (song != null)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          tooltip: '歌詞提前 0.5 秒',
                          onPressed: savingLyricOffset
                              ? null
                              : () => _adjustLyricOffset(500),
                          icon: const Icon(Icons.remove_circle_outline),
                        ),
                        Text(
                          song.lyricOffsetMs > 0
                              ? '歌詞已提前 ${(song.lyricOffsetMs / 1000).toStringAsFixed(1)} 秒'
                              : song.lyricOffsetMs < 0
                              ? '歌詞已延後 ${(-song.lyricOffsetMs / 1000).toStringAsFixed(1)} 秒'
                              : '歌詞時間未調整',
                        ),
                        IconButton(
                          tooltip: '歌詞延後 0.5 秒',
                          onPressed: savingLyricOffset
                              ? null
                              : () => _adjustLyricOffset(-500),
                          icon: const Icon(Icons.add_circle_outline),
                        ),
                      ],
                    ),
                  if (song?.source == 'LRCLIB' ||
                      song?.source == 'AMLL' ||
                      song?.source == 'LrcAPI' ||
                      song?.source == 'Musixmatch' ||
                      song?.source == '騰訊雲音速達')
                    Text('歌詞來源：${song!.source}', textAlign: TextAlign.center),
                  if (!compact)
                    Text(
                      '已儲存 ${library!.songs.length} 首歌詞',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
            ),
    );
  }
}
