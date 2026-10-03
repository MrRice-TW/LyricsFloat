import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:url_launcher/url_launcher.dart';

import 'cloud_sync.dart';
import 'lyrics.dart';
import 'lyrics_publish.dart';
import 'online_lyrics.dart';
import 'search_settings.dart';
import 'app_language.dart';
import 'app_update.dart';

const native = MethodChannel('lyrics_float/native');

class Playback {
  Playback(Map<dynamic, dynamic> data)
    : title = (data['title'] ?? '') as String,
      artist = (data['artist'] ?? '') as String,
      album = (data['album'] ?? '') as String,
      source = (data['source'] ?? '') as String,
      positionMs = (data['positionMs'] as num?)?.toInt() ?? 0,
      durationMs = _normalizeDuration(
        (data['durationMs'] as num?)?.toInt() ?? 0,
      ),
      playing = data['isPlaying'] == true,
      sampledAt = DateTime.now();

  static int _normalizeDuration(int durationMs) {
    if (durationMs > 86400000) {
      return durationMs ~/ 1000;
    }
    return durationMs;
  }

  final String title, artist, album, source;
  String get sourceLabel =>
      source.toLowerCase().contains('spotify') ? 'Spotify' : source;
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
  Widget build(BuildContext context) => ValueListenableBuilder<AppLanguage>(
    valueListenable: appLanguage,
    builder: (context, language, _) => MaterialApp(
      locale: appLanguage.locale,
      supportedLocales: const [Locale('zh', 'TW'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      title: 'LyricsFloat',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF7567EA),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: HomePage(),
    ),
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
  String localAddresses = '';
  final Map<String, int> failedPairings = {};
  String? error;
  String? playbackError;
  bool compact = false;
  bool overlay = false;
  bool mediaAccess = false;
  bool polling = false;
  bool savingLyricOffset = false;
  final GlobalKey currentLyricKey = GlobalKey();
  String? lastVisibleLyric;
  final OnlineLyricsLookup onlineLookup = OnlineLyricsLookup();
  final LrclibPublisher publisher = LrclibPublisher();
  final CloudAuth cloudAuth = CloudAuth();
  late final DriveCloudSync driveSync = DriveCloudSync(cloudAuth);
  bool publishing = false;
  bool checkingUpdates = false;
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
        if (!mounted) return;
        if (call.method == 'overlayClosed' || call.method == 'overlayChanged') {
          setState(
            () => overlay =
                call.method == 'overlayChanged' && call.arguments == true,
          );
          await _updateOverlay();
        }
      });
    }
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      final path = await native.invokeMethod<String>('getStoragePath');
      if (path == null) {
        throw StateError(tr('找不到儲存位置', 'Storage location unavailable'));
      }
      final loaded = Library(File('$path/lyrics.json'));
      await loaded.load();
      final loadedSettings = SearchSettings(File('$path/search_settings.json'));
      await loadedSettings.load();
      appLanguage.value = loadedSettings.language;
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
      if (localAddresses.isEmpty) {
        localAddresses = tr(
          '請查看裝置的 Wi-Fi 設定',
          'Check your device\'s Wi-Fi settings',
        );
      }
      try {
        server = await HttpServer.bind(InternetAddress.anyIPv4, 39847);
        server!.listen(_serve);
      } on SocketException {
        error = tr('同步連接埠 39847 無法使用', 'Sync port 39847 is unavailable');
      }
      if (!mounted) return;
      final initialOverlay = Platform.isAndroid
          ? await native.invokeMethod<bool>('getOverlayState') ?? false
          : false;
      if (!mounted) return;
      setState(() {
        library = loaded;
        searchSettings = loadedSettings;
        overlay = initialOverlay;
      });
      timer = Timer.periodic(const Duration(milliseconds: 500), (_) => _tick());
      if (Platform.isWindows && loadedSettings.checkUpdatesOnStartup) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(_checkForUpdates());
        });
      }
      await _tick();
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  Future<void> _checkForUpdates({bool manual = false}) async {
    if (checkingUpdates) {
      if (manual) _message(tr('正在檢查更新', 'Checking for updates'));
      return;
    }
    checkingUpdates = true;
    try {
      if (manual) _message(tr('正在檢查更新…', 'Checking for updates…'));
      final info = await PackageInfo.fromPlatform();
      final current = Version.parse(info.version);
      final update = await AppUpdateChecker().check(current);
      if (!mounted) return;
      if (update == null) {
        if (manual) {
          _message(tr('目前沒有可安裝的新版', 'No newer installer is available'));
        }
        return;
      }
      final download = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(tr('有新版本可用', 'Update available')),
          content: Text(
            tr(
              '目前版本：$current\n新版本：${update.version}\n\n下載新版 Setup.exe，關閉 LyricsFloat 後執行，即可更新並保留歌詞與設定。',
              'Current version: $current\nNew version: ${update.version}\n\nDownload the new Setup.exe, close LyricsFloat, then run the installer. Your lyrics and settings will be kept.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(tr('稍後再說', 'Later')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(tr('前往下載', 'Open download page')),
            ),
          ],
        ),
      );
      if (download == true && mounted) {
        if (!await launchUrl(
          update.page,
          mode: LaunchMode.externalApplication,
        )) {
          if (mounted) {
            _message(
              tr(
                '無法開啟下載頁，請稍後重試',
                'Could not open the download page. Please try again.',
              ),
            );
          }
        }
      }
    } catch (_) {
      // Offline/rate-limited startup checks must not interrupt playback.
      if (manual && mounted) {
        _message(
          tr(
            '無法檢查更新，請確認網路後重試',
            'Could not check for updates. Check your connection and try again.',
          ),
        );
      }
    } finally {
      checkingUpdates = false;
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
      _keepCurrentLyricVisible();
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

  void _keepCurrentLyricVisible({bool force = false}) {
    final song = currentSong;
    if (song == null) return;
    final marker = '${song.id}:$currentLine';
    if (!force && marker == lastVisibleLyric) return;
    lastVisibleLyric = marker;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final lyricContext = currentLyricKey.currentContext;
      if (mounted && lyricContext != null) {
        Scrollable.ensureVisible(
          lyricContext,
          alignment: 0.5,
          duration: const Duration(milliseconds: 180),
        );
      }
    });
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
      if (onlineStatus != tr('已關閉線上歌詞搜尋', 'Online lyrics search is disabled')) {
        setState(
          () => onlineStatus = tr(
            '已關閉線上歌詞搜尋',
            'Online lyrics search is disabled',
          ),
        );
      }
      return;
    }
    if (p.title.trim().isEmpty ||
        (p.artist.trim().isEmpty && p.durationMs <= 0)) {
      return;
    }
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
    setState(
      () => onlineStatus = tr(
        '即將搜尋動態歌詞…',
        'Preparing to search for synced lyrics…',
      ),
    );
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
    setState(
      () => onlineStatus = tr('正在搜尋動態歌詞…', 'Searching for synced lyrics…'),
    );
    try {
      final selectedSources = Set<OnlineLyricsSource>.of(
        searchSettings!.enabledSources,
      );
      var result = await onlineLookup.find(
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
      // Stage 2 fallback: If title+artist match failed, but we have a known playback duration,
      // fallback to searching title only across enabled sources and picking the closest duration match within tolerance.
      if (result == null &&
          track.durationMs > 0 &&
          cleanTitle(track.title).trim().isNotEmpty) {
        final candidates = await onlineLookup.findAll(
          title: cleanTitle(track.title),
          artist: '',
          durationMs: 0,
          enabledSources: selectedSources,
        );
        if (!mounted ||
            manualSearchOpen ||
            currentSong != null ||
            '${normalized(playback?.title ?? '')}|${normalizedArtist(playback?.artist ?? '')}' !=
                key) {
          return;
        }
        final closeMatches = candidates.where((c) {
          if (c.durationMs <= 0) return false;
          return (c.durationMs - track.durationMs).abs() <= 5000;
        }).toList();

        if (closeMatches.isNotEmpty) {
          closeMatches.sort(
            (a, b) => (a.durationMs - track.durationMs).abs().compareTo(
              (b.durationMs - track.durationMs).abs(),
            ),
          );
          result = closeMatches.first;
        }
      }
      final matchedResult = result;
      if (matchedResult == null) {
        nextOnlineAttempt[key] = DateTime.now().add(const Duration(minutes: 5));
        setState(
          () => onlineStatus = tr(
            '沒有找到相符的動態歌詞',
            'No matching synced lyrics found',
          ),
        );
        return;
      }
      if (!searchSettings!.enabledSources.any(
        (source) => source.label == matchedResult.source,
      )) {
        return;
      }
      library!.songs[key] = Song(
        id: key,
        title: track.title,
        artist: track.artist,
        lrc: matchedResult.lrc,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        source: matchedResult.source,
        album: matchedResult.album,
        durationMs: matchedResult.durationMs,
      );
      await library!.save();
      if (mounted) setState(() => onlineStatus = null);
    } catch (_) {
      nextOnlineAttempt[key] = DateTime.now().add(const Duration(minutes: 5));
      if (mounted && currentSong == null && onlineStatusKey == key) {
        setState(
          () => onlineStatus = tr(
            '暫時無法連線搜尋歌詞',
            'Lyrics search is temporarily unavailable',
          ),
        );
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
    final initialTitle = candidateTitles(track.title).length > 1
        ? candidateTitles(track.title)[1]
        : cleanTitle(track.title);
    final initialArtist = sameSearch ? manualSearchArtist : '';

    manualSearchOpen = true;
    onlineSearchTimer?.cancel();
    pendingOnlineKey = null;

    final chosen = await showDialog<OnlineLyrics>(
      context: context,
      builder: (dialogContext) => _ManualSearchDialogWidget(
        track: track,
        onlineLookup: onlineLookup,
        searchSettings: searchSettings,
        initialTitle: sameSearch ? manualSearchTitle : initialTitle,
        initialArtist: sameSearch ? manualSearchArtist : initialArtist,
        initialCandidates: sameSearch ? List.of(manualCandidates) : [],
        onSearchUpdated: (qTitle, qArtist, found) {
          manualSearchKey = key;
          manualSearchTitle = qTitle;
          manualSearchArtist = qArtist;
          manualCandidates = found;
        },
      ),
    );

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
        _message(tr('歌詞已儲存', 'Lyrics saved'));
      }
    } catch (_) {
      if (previous == null) {
        store.songs.remove(candidate.id);
      } else {
        store.songs[candidate.id] = previous;
      }
      if (mounted) {
        _message(
          tr('歌詞儲存失敗，請再試一次', 'Could not save lyrics. Please try again.'),
        );
      }
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
      _message(
        tr('歌詞時間儲存失敗，請再試一次', 'Could not save lyrics timing. Please try again.'),
      );
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
      _message(e.message ?? tr('無法開啟浮窗', 'Could not open the lyrics overlay'));
    }
  }

  Future<void> _quickTileHelpDialog() async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('加入快捷設定', 'Add to Quick Settings')),
        content: Text(
          tr(
            '從畫面頂端向下滑兩次，點選編輯或鉛筆圖示，把「浮動歌詞」拖到快捷設定。之後點一下即可開啟或關閉歌詞浮窗。\n\n第一次使用時，請先授權顯示浮窗與讀取播放資訊。',
            'Swipe down twice, tap Edit or the pencil icon, and drag LyricsFloat into Quick Settings. Tap the tile to toggle the overlay.\n\nAllow overlay and playback access before first use.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr('知道了', 'Got it')),
          ),
        ],
      ),
    );
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
        title: Text(
          existing == null
              ? tr('匯入動態歌詞', 'Import synced lyrics')
              : tr('編輯動態歌詞', 'Edit synced lyrics'),
        ),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: title,
                  decoration: InputDecoration(
                    labelText: tr('歌曲名稱', 'Song title'),
                  ),
                ),
                TextField(
                  controller: artist,
                  decoration: InputDecoration(labelText: tr('歌手', 'Artist')),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: lrc,
                  minLines: 8,
                  maxLines: 14,
                  decoration: InputDecoration(
                    labelText: tr('LRC 歌詞', 'LRC lyrics'),
                    hintText: tr(
                      '[00:12.50]第一句歌詞',
                      '[00:12.50]First lyric line',
                    ),
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
            child: Text(tr('取消', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr('儲存', 'Save')),
          ),
        ],
      ),
    );
    if (saved != true) return;
    if (title.text.trim().isEmpty || Lrc.parse(lrc.text).isEmpty) {
      _message(
        tr(
          '請填寫歌名與至少一行含時間標記的 LRC 歌詞',
          'Enter a song title and at least one timestamped LRC line',
        ),
      );
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
          content: Text(tr('歌詞已儲存到本機', 'Lyrics saved locally')),
          action: SnackBarAction(
            label: tr('發布到 LRCLIB', 'Publish to LRCLIB'),
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
      _message(
        tr(
          '請先儲存這首歌的手動歌詞，再發布到 LRCLIB',
          'Save the song\'s manual lyrics before publishing to LRCLIB',
        ),
      );
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
          title: Text(tr('發布到 LRCLIB', 'Publish to LRCLIB')),
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
                    decoration: InputDecoration(
                      labelText: tr('專輯名稱', 'Album name'),
                    ),
                  ),
                  TextField(
                    controller: duration,
                    keyboardType: TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: tr('歌曲長度（秒）', 'Duration (seconds)'),
                      hintText: tr('例如 213.5', 'e.g. 213.5'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    tr(
                      '這份歌詞會公開給其他人使用。同一首歌再次發布會新增修訂版本；專輯或長度不同可能建立另一首歌。請確認資料正確，且你有權分享。',
                      'These lyrics will be public. Publishing the same song adds a revision; a different album or duration may create another song. Check the details and make sure you have permission to share.',
                    ),
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
              child: Text(tr('取消', 'Cancel')),
            ),
            FilledButton(
              onPressed: () {
                final seconds = double.tryParse(duration.text.trim());
                if (album.text.trim().isEmpty ||
                    seconds == null ||
                    !seconds.isFinite ||
                    seconds <= 0 ||
                    Lrc.parse(song.lrc).isEmpty) {
                  refresh(
                    () => validation = tr(
                      '請填寫專輯、有效的歌曲長度與動態歌詞',
                      'Enter an album, a valid duration and synced lyrics',
                    ),
                  );
                  return;
                }
                Navigator.pop(dialogContext, true);
              },
              child: Text(tr('確認公開發布', 'Confirm public publishing')),
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
    final status = ValueNotifier<String>(
      tr('正在準備投稿…', 'Preparing submission…'),
    );
    final ready = Completer<BuildContext>();
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        if (!ready.isCompleted) ready.complete(dialogContext);
        return ValueListenableBuilder<String>(
          valueListenable: status,
          builder: (context, message, _) => AlertDialog(
            title: Text(tr('發布到 LRCLIB', 'Publish to LRCLIB')),
            content: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                const SizedBox(width: 16),
                Flexible(child: Text(message)),
              ],
            ),
            actions: message == tr('正在公開發布歌詞…', 'Publishing lyrics…')
                ? null
                : [
                    TextButton(
                      onPressed: () {
                        if (status.value ==
                            tr('正在公開發布歌詞…', 'Publishing lyrics…')) {
                          return;
                        }
                        cancellation.cancel();
                        Navigator.pop(dialogContext);
                      },
                      child: Text(tr('取消', 'Cancel')),
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
      if (mounted) {
        _message(tr('歌詞已公開發布到 LRCLIB', 'Lyrics published to LRCLIB'));
      }
    } on PublishCancelled {
      // The user dismissed the progress dialog before the public request.
    } on PublishException catch (e) {
      if (mounted) _message(e.message);
    } catch (_) {
      if (mounted) {
        _message(
          tr(
            '無法連線到 LRCLIB，請稍後再試',
            'Could not connect to LRCLIB. Try again later.',
          ),
        );
      }
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
          title: Text(tr('歌詞庫', 'Lyrics library')),
          content: SizedBox(
            width: 500,
            height: 360,
            child: library!.songs.isEmpty
                ? Center(
                    child: Text(
                      tr(
                        '還沒有歌詞，請先匯入 LRC',
                        'No lyrics yet. Import an LRC file first.',
                      ),
                    ),
                  )
                : ListView(
                    children: library!.songs.values
                        .map(
                          (song) => ListTile(
                            title: Text(
                              song.id.contains('#conflict#')
                                  ? tr(
                                      '${song.title}（衝突備份）',
                                      '${song.title} (conflict backup)',
                                    )
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
                                    tooltip: tr(
                                      '發布到 LRCLIB',
                                      'Publish to LRCLIB',
                                    ),
                                    icon: const Icon(Icons.publish),
                                    onPressed: () {
                                      Navigator.pop(dialogContext);
                                      _publishSong(song);
                                    },
                                  ),
                                IconButton(
                                  tooltip: tr('複製 LRC', 'Copy LRC'),
                                  icon: const Icon(Icons.copy),
                                  onPressed: () async {
                                    await Clipboard.setData(
                                      ClipboardData(text: song.lrc),
                                    );
                                    _message(
                                      tr(
                                        'LRC 已複製到剪貼簿',
                                        'LRC copied to clipboard',
                                      ),
                                    );
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
            TextButton.icon(
              onPressed: () {
                Navigator.pop(dialogContext);
                _cloudDialog();
              },
              icon: const Icon(Icons.cloud_outlined),
              label: Text(tr('雲端同步', 'Cloud sync')),
            ),
            TextButton.icon(
              onPressed: server == null
                  ? null
                  : () {
                      Navigator.pop(dialogContext);
                      _syncDialog();
                    },
              icon: const Icon(Icons.sync),
              label: Text(tr('同步', 'Sync')),
            ),
            TextButton.icon(
              onPressed: () {
                Navigator.pop(dialogContext);
                _importSong();
              },
              icon: const Icon(Icons.add),
              label: Text(tr('匯入 LRC', 'Import LRC')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(tr('關閉', 'Close')),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _settingsSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      constraints: BoxConstraints(maxWidth: 520),
      builder: (sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.8,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                  child: Text(
                    tr('設定', 'Settings'),
                    style: Theme.of(sheetContext).textTheme.headlineSmall,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
                  child: Text(tr('播放與搜尋', 'Playback and search')),
                ),
                ListTile(
                  leading: const Icon(Icons.language),
                  title: Text(tr('介面語言', 'Interface language')),
                  subtitle: Text(languageLabel(appLanguage.value)),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _languageDialog();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.music_note_outlined),
                  title: Text(tr('抓取播放來源', 'Playback sources')),
                  subtitle: Text(
                    sourceLabel(
                      searchSettings?.playbackSourceMode.label ??
                          tr('選擇播放來源', 'Choose playback sources'),
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _playbackSourceDialog();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.travel_explore),
                  title: Text(tr('歌詞搜尋來源', 'Lyrics search sources')),
                  subtitle: Text(
                    tr('選擇自動搜尋的網站', 'Choose websites for automatic search'),
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _searchSourcesDialog();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.cloud_outlined),
                  title: Text(tr('Google 雲端備份', 'Google cloud backup')),
                  subtitle: Text(
                    tr('跨裝置合併歌詞庫', 'Merge your library across devices'),
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _cloudDialog();
                  },
                ),
                Divider(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 4),
                  child: Text(tr('歌詞顯示', 'Lyrics display')),
                ),
                ListTile(
                  leading: const Icon(Icons.format_size),
                  title: Text(tr('App 內歌詞', 'In-app lyrics')),
                  subtitle: Text(
                    tr(
                      '${searchSettings?.lyricsVisibleLines ?? 3} 行 · 字體 ${searchSettings?.lyricsFontSize.round() ?? 28}',
                      '${searchSettings?.lyricsVisibleLines ?? 3} lines · font ${searchSettings?.lyricsFontSize.round() ?? 28}',
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _lyricsDisplayDialog();
                  },
                ),
                if (Platform.isAndroid) ...[
                  Divider(),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 4),
                    child: Text(
                      tr(
                        'Android 權限與快捷設定',
                        'Android permissions and Quick Settings',
                      ),
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.notifications_active_outlined),
                    title: Text(tr('授權讀取播放資訊', 'Allow playback access')),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      native.invokeMethod('requestMediaAccess');
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.tune),
                    title: Text(tr('加入快捷設定開關', 'Add a Quick Settings tile')),
                    subtitle: Text(
                      tr(
                        '從手機頂端下拉，快速開關浮動歌詞',
                        'Swipe down to quickly toggle the lyrics overlay',
                      ),
                    ),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _quickTileHelpDialog();
                    },
                  ),
                ],
                if (Platform.isWindows) ...[
                  const Divider(),
                  SwitchListTile(
                    secondary: const Icon(Icons.system_update_alt),
                    title: Text(tr('啟動時檢查更新', 'Check for updates on startup')),
                    value: searchSettings?.checkUpdatesOnStartup ?? true,
                    onChanged: searchSettings == null
                        ? null
                        : (value) async {
                            final settings = searchSettings!;
                            final previous = settings.checkUpdatesOnStartup;
                            settings.checkUpdatesOnStartup = value;
                            try {
                              await settings.save();
                            } catch (_) {
                              settings.checkUpdatesOnStartup = previous;
                              if (mounted) {
                                _message(
                                  tr(
                                    '無法儲存更新設定',
                                    'Could not save update settings',
                                  ),
                                );
                              }
                            }
                            if (sheetContext.mounted) {
                              Navigator.pop(sheetContext);
                            }
                            if (mounted) setState(() {});
                          },
                  ),
                  ListTile(
                    leading: const Icon(Icons.refresh),
                    title: Text(tr('立即檢查更新', 'Check for updates now')),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      unawaited(_checkForUpdates(manual: true));
                    },
                  ),
                ],
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _languageDialog() async {
    final settings = searchSettings;
    if (settings == null) return;
    final selected = await showDialog<AppLanguage>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(tr('介面語言', 'Interface language')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final language in AppLanguage.values)
              ListTile(
                title: Text(languageLabel(language)),
                trailing: language == settings.language
                    ? const Icon(Icons.check)
                    : null,
                onTap: () => Navigator.pop(dialogContext, language),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(tr('取消', 'Cancel')),
          ),
        ],
      ),
    );
    if (selected == null || selected == settings.language) return;
    final previous = settings.language;
    settings.language = selected;
    try {
      await settings.save();
      if (!mounted) return;
      appLanguage.value = selected;
      setState(() {
        onlineStatus = null;
      });
    } catch (_) {
      settings.language = previous;
      if (mounted) _message(tr('無法儲存語言設定', 'Could not save language settings'));
    }
  }

  Future<void> _searchSourcesDialog() async {
    final settings = searchSettings;
    if (settings == null) return;
    final selected = Set<OnlineLyricsSource>.of(settings.enabledSources);
    final updated = await showDialog<Set<OnlineLyricsSource>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, refresh) => AlertDialog(
          title: Text(tr('歌詞搜尋來源', 'Lyrics search sources')),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr(
                    '依下列順序搜尋；找到相符歌詞後就停止。已匯入的歌詞仍會保留。',
                    'Search in the order below and stop when matching lyrics are found. Imported lyrics are preserved.',
                  ),
                ),
                const SizedBox(height: 8),
                for (final source in OnlineLyricsSource.values)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(sourceLabel(source.label)),
                    subtitle: switch (source) {
                      OnlineLyricsSource.musixmatch
                          when !onlineLookup.musixmatchConfigured =>
                        Text(
                          tr(
                            '需先設定 MUSIXMATCH_API_KEY',
                            'Configure MUSIXMATCH_API_KEY first',
                          ),
                        ),
                      OnlineLyricsSource.tencentCloud
                          when !onlineLookup.tencentConfigured =>
                        Text(
                          tr(
                            '需先設定騰訊雲音速達憑證與應用資料',
                            'Configure Tencent Cloud credentials and application details first',
                          ),
                        ),
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
                Text(
                  tr(
                    '全部取消勾選會停止線上搜尋。付費來源需要自行開通，並可能產生供應商費用。',
                    'Uncheck all sources to disable online search. Paid sources require your own account and may incur provider charges.',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(tr('取消', 'Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, selected),
              child: Text(tr('儲存', 'Save')),
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
      if (mounted) {
        _message(tr('無法儲存搜尋來源設定', 'Could not save search source settings'));
      }
    }
  }

  Future<void> _playbackSourceDialog() async {
    final settings = searchSettings;
    if (settings == null) return;
    final selected = await showDialog<PlaybackSourceMode>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(tr('抓取播放來源', 'Playback sources')),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final mode in PlaybackSourceMode.values)
                ListTile(
                  title: Text(sourceLabel(mode.label)),
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
                    ? tr(
                        'Mac 版會讀取 Spotify 桌面版，以及 Chrome／Edge 的 YouTube Music 分頁。瀏覽器需開啟「允許 Apple Events 執行 JavaScript」。',
                        'On Mac, playback is read from Spotify and YouTube Music tabs in Chrome/Edge. Enable Allow JavaScript from Apple Events in your browser.',
                      )
                    : tr(
                        '瀏覽器不提供分頁網址，因此選擇 YouTube 時也會抓取其他瀏覽器媒體。',
                        'Browsers do not provide tab URLs, so choosing YouTube also includes other browser media.',
                      ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(tr('取消', 'Cancel')),
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
      if (mounted) {
        _message(tr('無法儲存播放來源設定', 'Could not save playback source settings'));
      }
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

  Future<void> _lyricsDisplayDialog() async {
    final settings = searchSettings;
    if (settings == null) return;
    var visibleLines = settings.lyricsVisibleLines;
    var fontSize = settings.lyricsFontSize;
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, refresh) => AlertDialog(
          title: Text(tr('App 內歌詞顯示', 'In-app lyrics display')),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr('畫面顯示行數', 'Visible lines')),
                const SizedBox(height: 8),
                DropdownButton<int>(
                  value: visibleLines,
                  isExpanded: true,
                  items: [3, 5, 7]
                      .map(
                        (count) => DropdownMenuItem(
                          value: count,
                          child: Text(tr('$count 行', '$count lines')),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) refresh(() => visibleLines = value);
                  },
                ),
                const SizedBox(height: 16),
                Text(
                  tr(
                    '目前歌詞字體：${fontSize.round()}',
                    'Current lyrics font: ${fontSize.round()}',
                  ),
                ),
                Slider(
                  value: fontSize,
                  min: 18,
                  max: 40,
                  divisions: 11,
                  label: '${fontSize.round()}',
                  onChanged: (value) => refresh(() => fontSize = value),
                ),
                Text(
                  tr(
                    '其他行會依比例縮小；此設定只影響 App 內畫面。',
                    'Other lines use proportionally smaller text. This setting applies to the in-app display.',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(tr('取消', 'Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(tr('儲存', 'Save')),
            ),
          ],
        ),
      ),
    );
    if (saved != true || !mounted) return;
    final oldLines = settings.lyricsVisibleLines;
    final oldSize = settings.lyricsFontSize;
    settings.lyricsVisibleLines = visibleLines;
    settings.lyricsFontSize = fontSize;
    try {
      await settings.save();
      if (mounted) {
        setState(() {});
        _keepCurrentLyricVisible(force: true);
      }
    } catch (_) {
      settings.lyricsVisibleLines = oldLines;
      settings.lyricsFontSize = oldSize;
      if (mounted) {
        _message(tr('無法儲存歌詞顯示設定', 'Could not save lyrics display settings'));
      }
    }
  }

  Future<void> _syncDialog() async {
    final address = TextEditingController();
    final code = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(tr('同一 Wi-Fi 同步歌詞', 'Sync lyrics on the same Wi-Fi')),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr('本機 IP：$localAddresses', 'Local IP: $localAddresses')),
              Text(
                tr(
                  '本機配對碼：$pairingCode　連接埠：39847',
                  'Local pairing code: $pairingCode  Port: 39847',
                ),
              ),
              const SizedBox(height: 8),
              Text(
                tr(
                  '在另一台裝置輸入這台裝置的區域網路 IP 與配對碼。兩台裝置都需開啟本 App。',
                  'Enter this device\'s local IP and pairing code on the other device. Keep this app open on both devices.',
                ),
              ),
              TextField(
                controller: address,
                decoration: InputDecoration(
                  labelText: tr('另一台裝置的 IP', 'Other device\'s IP'),
                ),
              ),
              TextField(
                controller: code,
                decoration: InputDecoration(
                  labelText: tr(
                    '另一台裝置的八位配對碼',
                    'Other device\'s eight-digit pairing code',
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(tr('關閉', 'Close')),
          ),
          FilledButton(
            onPressed: () async {
              final host = address.text.trim();
              if (InternetAddress.tryParse(host)?.type !=
                      InternetAddressType.IPv4 ||
                  !RegExp(r'^\d{8}$').hasMatch(code.text.trim())) {
                _message(
                  tr(
                    '請輸入有效的 IPv4 位址與八位配對碼',
                    'Enter a valid IPv4 address and eight-digit pairing code',
                  ),
                );
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
                  throw StateError(
                    tr(
                      '連線被拒絕，請檢查 IP 與配對碼',
                      'Connection refused. Check the IP and pairing code.',
                    ),
                  );
                }
                final data =
                    jsonDecode(await utf8.decoder.bind(response).join()) as Map;
                final count = await library!.merge(
                  data['songs'] as List<dynamic>,
                );
                client.close();
                if (dialogContext.mounted) Navigator.pop(dialogContext);
                if (mounted) setState(() {});
                _message(
                  tr(
                    '同步完成，收到 $count 首新歌詞',
                    'Sync complete: $count new lyrics received',
                  ),
                );
              } catch (e) {
                _message(tr('同步失敗：$e', 'Sync failed: $e'));
              }
            },
            child: Text(tr('立即同步', 'Sync now')),
          ),
        ],
      ),
    );
  }

  Future<void> _cloudDialog() async {
    try {
      await cloudAuth.initialize();
    } catch (e) {
      _message(
        tr('無法初始化 Google 登入：$e', 'Could not initialize Google sign-in: $e'),
      );
      return;
    }
    if (!mounted || library == null) return;
    var busy = false;
    String? status;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, refresh) => AlertDialog(
          title: Text(tr('Google 雲端備份', 'Google cloud backup')),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(sourceLabel(cloudAuth.accountLabel)),
                const SizedBox(height: 8),
                Text(
                  tr(
                    '按「合併並同步」會下載雲端歌詞、保留衝突版本，再上傳合併後的歌詞庫。雲端資料存放在此 App 專用的隱藏資料夾。',
                    'Merge and sync downloads cloud lyrics, preserves conflicting versions and uploads the merged library. Cloud data is stored in this app\'s hidden folder.',
                  ),
                ),
                if (status != null) ...[
                  const SizedBox(height: 12),
                  Text(status!),
                ],
                if (busy) ...[
                  const SizedBox(height: 12),
                  LinearProgressIndicator(),
                ],
              ],
            ),
          ),
          actions: [
            if (cloudAuth.connected)
              TextButton(
                onPressed: busy
                    ? null
                    : () async {
                        refresh(() => busy = true);
                        try {
                          await cloudAuth.disconnect();
                          if (dialogContext.mounted) {
                            refresh(
                              () => status = tr(
                                '已中斷 Google 連結',
                                'Google disconnected',
                              ),
                            );
                          }
                        } catch (e) {
                          if (dialogContext.mounted) {
                            refresh(
                              () => status = tr(
                                '中斷連結失敗：$e',
                                'Disconnect failed: $e',
                              ),
                            );
                          }
                        } finally {
                          if (dialogContext.mounted) {
                            refresh(() => busy = false);
                          }
                        }
                      },
                child: Text(tr('中斷連結', 'Disconnect')),
              ),
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(dialogContext),
              child: Text(tr('關閉', 'Close')),
            ),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      refresh(() {
                        busy = true;
                        status = null;
                      });
                      try {
                        if (!cloudAuth.connected) {
                          await cloudAuth.connect();
                          if (dialogContext.mounted) {
                            refresh(
                              () => status = tr(
                                '已連結 Google 帳號',
                                'Google account connected',
                              ),
                            );
                          }
                        } else {
                          final result = await driveSync.sync(library!);
                          if (mounted) setState(() {});
                          if (dialogContext.mounted) {
                            refresh(
                              () => status = tr(
                                '同步完成：從雲端合併 ${result.imported} 首，歌詞庫共 ${result.total} 首',
                                'Sync complete: ${result.imported} merged from cloud, ${result.total} total',
                              ),
                            );
                          }
                        }
                      } catch (e) {
                        if (dialogContext.mounted) {
                          refresh(
                            () =>
                                status = tr('操作失敗：$e', 'Operation failed: $e'),
                          );
                        }
                      } finally {
                        if (dialogContext.mounted) refresh(() => busy = false);
                      }
                    },
              child: Text(
                cloudAuth.connected
                    ? tr('合併並同步', 'Merge and sync')
                    : tr('連結 Google', 'Connect Google'),
              ),
            ),
          ],
        ),
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
    final visibleLines = searchSettings?.lyricsVisibleLines ?? 3;
    final fontSize = searchSettings?.lyricsFontSize ?? 28;
    final windowSize = min(visibleLines, lines.length);
    final windowStart = index < 0 || windowSize == 0
        ? 0
        : (index - windowSize ~/ 2).clamp(0, lines.length - windowSize);
    final windowEnd = index < 0
        ? min(lines.length, visibleLines - 1)
        : windowStart + windowSize;
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
                          ? tr('尚未偵測到歌曲', 'No song detected')
                          : '${playback!.title} · ${playback!.artist}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  IconButton(
                    tooltip: tr('關閉桌面歌詞', 'Close desktop lyrics'),
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
        title: Text(
          'LyricsFloat',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (Platform.isAndroid)
            IconButton(
              tooltip: overlay
                  ? tr('關閉歌詞浮窗', 'Close lyrics overlay')
                  : tr('開啟歌詞浮窗', 'Open lyrics overlay'),
              onPressed: _toggleOverlay,
              icon: Icon(
                overlay
                    ? Icons.layers_clear_outlined
                    : Icons.picture_in_picture_alt,
              ),
            ),
          if (Platform.isWindows || Platform.isMacOS)
            IconButton(
              tooltip: compact
                  ? tr('一般視窗', 'Normal window')
                  : tr('桌面歌詞視窗', 'Desktop lyrics window'),
              onPressed: _toggleCompact,
              icon: Icon(
                compact ? Icons.open_in_full : Icons.picture_in_picture_alt,
              ),
            ),
          IconButton(
            tooltip: tr('輸入歌名搜尋歌詞', 'Search lyrics by song title'),
            onPressed: library == null || playback == null
                ? null
                : _manualSearchDialog,
            icon: const Icon(Icons.search),
          ),
          IconButton(
            tooltip: tr('歌詞庫', 'Lyrics library'),
            onPressed: library == null ? null : _libraryDialog,
            icon: const Icon(Icons.library_music),
          ),
          IconButton(
            tooltip: tr('設定', 'Settings'),
            onPressed: _settingsSheet,
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: library == null
          ? Center(child: Text(error ?? tr('載入中…', 'Loading…')))
          : Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    Platform.isAndroid && !mediaAccess
                        ? tr('需要播放資訊權限', 'Playback access required')
                        : playback == null
                        ? (Platform.isMacOS && playbackError != null
                              ? playbackError!
                              : tr(
                                  '尚未偵測到已選來源的歌曲',
                                  'No song detected from the selected sources',
                                ))
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
                        label: Text(tr('授權讀取播放資訊', 'Allow playback access')),
                      ),
                    ),
                  if (playback != null)
                    Text(
                      '${playback!.sourceLabel} · ${playback!.playing ? tr('播放中', 'Playing') : tr('已暫停', 'Paused')}',
                      textAlign: TextAlign.center,
                    ),
                  if (song != null && !identical(song, previewSong))
                    Center(
                      child: TextButton.icon(
                        onPressed: () => _importSong(song),
                        icon: const Icon(Icons.edit_note),
                        label: Text(tr('編輯目前歌詞', 'Edit current lyrics')),
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
                                      ? tr(
                                          '播放歌曲後會在這裡顯示歌詞',
                                          'Play a song to see its lyrics here',
                                        )
                                      : onlineStatus ??
                                            tr(
                                              '尚無這首歌的歌詞，可匯入 LRC',
                                              'No lyrics for this song yet. Import an LRC file.',
                                            ),
                                  textAlign: TextAlign.center,
                                ),
                                if (playback != null &&
                                    onlineStatus != null &&
                                    runningOnlineKey == null &&
                                    pendingOnlineKey == null)
                                  TextButton(
                                    onPressed: _retryOnlineSearch,
                                    child: Text(tr('重新搜尋', 'Search again')),
                                  ),
                                if (playback != null)
                                  OutlinedButton.icon(
                                    onPressed: _manualSearchDialog,
                                    icon: const Icon(Icons.search),
                                    label: Text(
                                      tr('輸入歌名搜尋', 'Search by song title'),
                                    ),
                                  ),
                              ],
                            )
                          : LayoutBuilder(
                              builder: (context, constraints) =>
                                  SingleChildScrollView(
                                    key: ValueKey('${song.id}:$windowStart'),
                                    child: ConstrainedBox(
                                      constraints: BoxConstraints(
                                        minHeight: constraints.maxHeight,
                                      ),
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          if (index < 0)
                                            Text(
                                              '♪',
                                              key: currentLyricKey,
                                              style: TextStyle(
                                                fontSize: fontSize,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          for (
                                            var i = windowStart;
                                            i < windowEnd;
                                            i++
                                          ) ...[
                                            if (i > windowStart || index < 0)
                                              const SizedBox(height: 12),
                                            Text(
                                              lines[i].text,
                                              key: i == index
                                                  ? currentLyricKey
                                                  : null,
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                fontSize: i == index
                                                    ? fontSize
                                                    : fontSize * 0.7,
                                                color: i == index
                                                    ? Colors.white
                                                    : Colors.white54,
                                                fontWeight: i == index
                                                    ? FontWeight.bold
                                                    : FontWeight.normal,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ),
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
                            Text(
                              tr(
                                '試套用：${previewSong!.source} · 尚未儲存',
                                'Preview: ${sourceLabel(previewSong!.source)} · Not saved',
                              ),
                            ),
                            TextButton(
                              onPressed: _manualSearchDialog,
                              child: Text(tr('換一份', 'Try another')),
                            ),
                            TextButton(
                              onPressed: _cancelPreview,
                              child: Text(tr('取消', 'Cancel')),
                            ),
                            FilledButton(
                              onPressed: _confirmPreview,
                              child: Text(tr('確認儲存', 'Confirm and save')),
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
                          tooltip: tr(
                            '歌詞提前 0.5 秒',
                            'Show lyrics 0.5 seconds earlier',
                          ),
                          onPressed: savingLyricOffset
                              ? null
                              : () => _adjustLyricOffset(500),
                          icon: const Icon(Icons.remove_circle_outline),
                        ),
                        Text(
                          song.lyricOffsetMs > 0
                              ? tr(
                                  '歌詞已提前 ${(song.lyricOffsetMs / 1000).toStringAsFixed(1)} 秒',
                                  'Lyrics ${(song.lyricOffsetMs / 1000).toStringAsFixed(1)} seconds earlier',
                                )
                              : song.lyricOffsetMs < 0
                              ? tr(
                                  '歌詞已延後 ${(-song.lyricOffsetMs / 1000).toStringAsFixed(1)} 秒',
                                  'Lyrics ${(-song.lyricOffsetMs / 1000).toStringAsFixed(1)} seconds later',
                                )
                              : tr('歌詞時間未調整', 'Lyrics timing unchanged'),
                        ),
                        IconButton(
                          tooltip: tr(
                            '歌詞延後 0.5 秒',
                            'Show lyrics 0.5 seconds later',
                          ),
                          onPressed: savingLyricOffset
                              ? null
                              : () => _adjustLyricOffset(-500),
                          icon: const Icon(Icons.add_circle_outline),
                        ),
                      ],
                    ),
                  if (song?.source != null &&
                      song?.source != 'manual' &&
                      song!.source.isNotEmpty)
                    Text(
                      tr(
                        '歌詞來源：${song.source}',
                        'Lyrics source: ${sourceLabel(song.source)}',
                      ),
                      textAlign: TextAlign.center,
                    ),
                  if (!compact)
                    Text(
                      tr(
                        '已儲存 ${library!.songs.length} 首歌詞',
                        '${library!.songs.length} lyrics saved',
                      ),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
            ),
    );
  }
}

class _ManualSearchDialogWidget extends StatefulWidget {
  final Playback track;
  final OnlineLyricsLookup onlineLookup;
  final SearchSettings? searchSettings;
  final String initialTitle;
  final String initialArtist;
  final List<OnlineLyrics> initialCandidates;
  final void Function(
    String title,
    String artist,
    List<OnlineLyrics> candidates,
  )
  onSearchUpdated;

  const _ManualSearchDialogWidget({
    required this.track,
    required this.onlineLookup,
    required this.searchSettings,
    required this.initialTitle,
    required this.initialArtist,
    required this.initialCandidates,
    required this.onSearchUpdated,
  });

  @override
  State<_ManualSearchDialogWidget> createState() =>
      _ManualSearchDialogWidgetState();
}

class _ManualSearchDialogWidgetState extends State<_ManualSearchDialogWidget> {
  late final TextEditingController _titleController;
  late final TextEditingController _artistController;
  late List<OnlineLyrics> _candidates;
  bool _searching = false;
  String? _status;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.initialTitle);
    _artistController = TextEditingController(text: widget.initialArtist);
    _candidates = List.of(widget.initialCandidates);
    if (_candidates.isEmpty && widget.initialTitle.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _search();
      });
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _artistController.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    if (_searching) return;
    final queryTitle = _titleController.text.trim();
    final queryArtist = _artistController.text.trim();
    if (queryTitle.isEmpty) {
      setState(() => _status = tr('請填寫歌名', 'Enter a song title'));
      return;
    }
    final enabled = Set<OnlineLyricsSource>.of(
      widget.searchSettings?.enabledSources ?? defaultOnlineLyricsSources,
    );
    if (enabled.isEmpty) {
      setState(
        () => _status = tr(
          '請先在「歌詞搜尋來源」啟用至少一個來源',
          'Enable at least one source in Lyrics search sources first',
        ),
      );
      return;
    }
    setState(() {
      _searching = true;
      _candidates = [];
      _status = tr('正在搜尋各個來源…', 'Searching sources…');
    });

    final found = await widget.onlineLookup.findAll(
      title: queryTitle,
      artist: queryArtist,
      durationMs: 0,
      enabledSources: enabled,
    );
    if (!mounted) return;

    if (widget.track.durationMs > 0) {
      found.sort((a, b) {
        final diffA = a.durationMs > 0
            ? (a.durationMs - widget.track.durationMs).abs()
            : 999999;
        final diffB = b.durationMs > 0
            ? (b.durationMs - widget.track.durationMs).abs()
            : 999999;
        return diffA.compareTo(diffB);
      });
    }

    setState(() {
      _searching = false;
      _candidates = found;
      _status = found.isEmpty
          ? tr(
              '沒有找到相符的動態歌詞，可修改歌名再試',
              'No matching synced lyrics. Try changing the song title.',
            )
          : null;
    });

    widget.onSearchUpdated(queryTitle, queryArtist, found);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(tr('手動搜尋動態歌詞', 'Search synced lyrics manually')),
      content: SizedBox(
        width: 520,
        height: min(MediaQuery.sizeOf(context).height * 0.55, 420),
        child: Column(
          children: [
            TextField(
              controller: _titleController,
              enabled: !_searching,
              decoration: InputDecoration(labelText: tr('歌曲名稱', 'Song title')),
              onSubmitted: (_) => _search(),
              onChanged: (_) {
                if (_candidates.isNotEmpty || _status != null) {
                  setState(() {
                    _candidates = [];
                    _status = null;
                  });
                }
              },
            ),
            TextField(
              controller: _artistController,
              enabled: !_searching,
              decoration: InputDecoration(
                labelText: tr(
                  '歌手（選填，留空以純歌名搜尋）',
                  'Artist (optional; leave blank to search by title)',
                ),
                hintText:
                    splitArtists(widget.track.artist).firstOrNull ??
                    widget.track.artist,
              ),
              onSubmitted: (_) => _search(),
              onChanged: (_) {
                if (_candidates.isNotEmpty || _status != null) {
                  setState(() {
                    _candidates = [];
                    _status = null;
                  });
                }
              },
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _searching ? null : _search,
                icon: const Icon(Icons.search),
                label: Text(tr('搜尋', 'Search')),
              ),
            ),
            if (_status != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(_status!, textAlign: TextAlign.center),
              ),
            if (_searching) LinearProgressIndicator(),
            Expanded(
              child: ListView.builder(
                itemCount: _candidates.length,
                itemBuilder: (context, index) {
                  final candidate = _candidates[index];
                  final seconds = candidate.durationMs ~/ 1000;
                  final duration = seconds > 0
                      ? '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}'
                      : tr('長度未知', 'Unknown duration');
                  String durationInfo = duration;
                  if (widget.track.durationMs > 0 && candidate.durationMs > 0) {
                    final diffSeconds =
                        ((candidate.durationMs - widget.track.durationMs)
                            .abs()) ~/
                        1000;
                    if (diffSeconds <= 2) {
                      durationInfo = tr(
                        '$duration (長度相符 · 推薦)',
                        '$duration (matching duration · recommended)',
                      );
                    } else {
                      durationInfo = tr(
                        '$duration (相差 $diffSeconds 秒)',
                        '$duration ($diffSeconds seconds difference)',
                      );
                    }
                  }
                  return ListTile(
                    title: Text(sourceLabel(candidate.source)),
                    subtitle: Text(
                      '${candidate.title} · ${candidate.artist}\n$durationInfo${candidate.album.isEmpty ? '' : ' · ${candidate.album}'}',
                    ),
                    isThreeLine: true,
                    trailing: Text(tr('試套用', 'Preview')),
                    onTap: () => Navigator.pop(context, candidate),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(tr('關閉', 'Close')),
        ),
      ],
    );
  }
}
