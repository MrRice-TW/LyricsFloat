import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:url_launcher/url_launcher.dart';

import 'lyrics.dart';

const driveAppDataScope = 'https://www.googleapis.com/auth/drive.appdata';
const _androidServerClientId =
    '454091359529-snkhiiu84hnl8ctu446kqf730olh0e75.apps.googleusercontent.com';
const _macDesktopClientId =
    '454091359529-6nkrqnq6qm4ssbk45us9gma89kmeoni0.apps.googleusercontent.com';
const _windowsClientId =
    '454091359529-o8ir2ehfbcuprovaeoak9cm7697rd78l.apps.googleusercontent.com';
const _macDesktopClientSecret = String.fromEnvironment(
  'GOOGLE_MAC_CLIENT_SECRET',
);
const _windowsClientSecret = String.fromEnvironment(
  'GOOGLE_WINDOWS_CLIENT_SECRET',
);
const _desktopRefreshKey = 'google_drive_refresh_token';

class CloudAuth {
  CloudAuth({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          (Platform.isMacOS
              ? const FlutterSecureStorage(
                  mOptions: MacOsOptions(usesDataProtectionKeychain: false),
                )
              : const FlutterSecureStorage());

  final FlutterSecureStorage _storage;
  GoogleSignInAccount? _account;
  String? _refreshToken;
  String? _accessToken;
  DateTime? _accessTokenExpiry;
  bool _initialized = false;

  bool get connected => Platform.isWindows || Platform.isMacOS
      ? _refreshToken != null
      : _account != null;
  String get accountLabel => Platform.isWindows || Platform.isMacOS
      ? (_refreshToken == null ? '尚未連結' : '已連結 Google 帳號')
      : _account?.email ?? '尚未連結';

  Future<void> initialize() async {
    if (_initialized) return;
    if (Platform.isWindows || Platform.isMacOS) {
      _refreshToken = await _storage.read(key: _refreshKey);
    } else if (Platform.isAndroid) {
      await GoogleSignIn.instance.initialize(
        serverClientId: _androidServerClientId,
      );
      _account = await GoogleSignIn.instance.attemptLightweightAuthentication();
    } else {
      throw UnsupportedError('此平台尚未支援 Google 雲端備份');
    }
    _initialized = true;
  }

  Future<void> connect() async {
    await initialize();
    if (Platform.isWindows || Platform.isMacOS) {
      await _connectDesktop();
      return;
    }
    final account = await GoogleSignIn.instance.authenticate();
    await account.authorizationClient.authorizeScopes([driveAppDataScope]);
    _account = account;
  }

  Future<String> accessToken() async {
    await initialize();
    if (Platform.isWindows || Platform.isMacOS) {
      if (_accessToken != null &&
          _accessTokenExpiry!.isAfter(
            DateTime.now().add(const Duration(minutes: 1)),
          )) {
        return _accessToken!;
      }
      final refreshToken = _refreshToken;
      if (refreshToken == null) throw StateError('請先連結 Google 帳號');
      if (_desktopClientSecret.isEmpty) {
        throw StateError('此版本尚未設定 Google 登入憑證，請使用含 OAuth 設定的版本');
      }
      late final Map<String, dynamic> token;
      try {
        token = await _requestToken({
          'client_id': _desktopClientId,
          'client_secret': _desktopClientSecret,
          'refresh_token': refreshToken,
          'grant_type': 'refresh_token',
        });
      } on StateError catch (error) {
        if ('$error'.contains('invalid_grant')) {
          await disconnect();
          throw StateError('Google 登入已到期，請重新連結帳號');
        }
        rethrow;
      }
      _acceptToken(token);
      return _accessToken!;
    }
    final account = _account;
    if (account == null) throw StateError('請先連結 Google 帳號');
    final authorization = await account.authorizationClient
        .authorizationForScopes([driveAppDataScope]);
    if (authorization == null) {
      throw StateError('Google 授權已到期，請重新連結帳號');
    }
    return authorization.accessToken;
  }

  Future<void> disconnect() async {
    if (Platform.isWindows || Platform.isMacOS) {
      await _storage.delete(key: _refreshKey);
      _refreshToken = null;
      _accessToken = null;
      _accessTokenExpiry = null;
    } else {
      await GoogleSignIn.instance.signOut();
      _account = null;
    }
  }

  String get _desktopClientId =>
      Platform.isMacOS ? _macDesktopClientId : _windowsClientId;
  String get _desktopClientSecret =>
      Platform.isMacOS ? _macDesktopClientSecret : _windowsClientSecret;
  String get _refreshKey => _desktopRefreshKey;

  Future<void> _connectDesktop() async {
    if (_desktopClientSecret.isEmpty) {
      throw StateError('此版本尚未設定 Google 登入憑證，請使用含 OAuth 設定的版本');
    }
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final redirect = 'http://127.0.0.1:${server.port}';
    final verifier = _randomUrlSafe(48);
    final challenge = base64UrlEncode(
      sha256.convert(ascii.encode(verifier)).bytes,
    ).replaceAll('=', '');
    final state = _randomUrlSafe(24);
    final url = Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
      'client_id': _desktopClientId,
      'redirect_uri': redirect,
      'response_type': 'code',
      'scope': driveAppDataScope,
      'code_challenge': challenge,
      'code_challenge_method': 'S256',
      'state': state,
      'access_type': 'offline',
      'prompt': 'consent',
    });
    try {
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        throw StateError('無法開啟 Google 登入網頁');
      }
      final request = await server.first.timeout(const Duration(minutes: 3));
      final parameters = request.uri.queryParameters;
      final valid = request.uri.path == '/' && parameters['state'] == state;
      request.response.headers.contentType = ContentType.html;
      request.response.write(
        valid && parameters['code'] != null
            ? '<p>LyricsFloat 登入完成，可以關閉此視窗。</p>'
            : '<p>LyricsFloat 登入未完成，請回到 App 重試。</p>',
      );
      await request.response.close();
      if (!valid) throw StateError('Google 登入驗證失敗');
      if (parameters['error'] != null) {
        throw StateError('Google 登入遭取消：${parameters['error']}');
      }
      final code = parameters['code'];
      if (code == null) throw StateError('Google 沒有傳回授權碼');
      final token = await _requestToken({
        'client_id': _desktopClientId,
        'client_secret': _desktopClientSecret,
        'code': code,
        'code_verifier': verifier,
        'redirect_uri': redirect,
        'grant_type': 'authorization_code',
      });
      _acceptToken(token);
      final refreshToken = token['refresh_token'] as String?;
      if (refreshToken == null) throw StateError('Google 沒有傳回長期登入憑證');
      await _storage.write(key: _refreshKey, value: refreshToken);
      _refreshToken = refreshToken;
    } finally {
      await server.close(force: true);
    }
  }

  void _acceptToken(Map<String, dynamic> token) {
    _accessToken = token['access_token'] as String?;
    if (_accessToken == null) throw StateError('Google 沒有傳回存取權杖');
    final expiresIn = (token['expires_in'] as num?)?.toInt() ?? 3600;
    _accessTokenExpiry = DateTime.now().add(Duration(seconds: expiresIn));
  }

  Future<Map<String, dynamic>> _requestToken(
    Map<String, String> parameters,
  ) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client.postUrl(
        Uri.https('oauth2.googleapis.com', '/token'),
      );
      request.headers.contentType = ContentType(
        'application',
        'x-www-form-urlencoded',
      );
      request.write(Uri(queryParameters: parameters).query);
      final response = await request.close();
      final body = await utf8.decoder.bind(response).join();
      if (response.statusCode != 200) {
        throw StateError('Google 登入失敗 (${response.statusCode})：$body');
      }
      return Map<String, dynamic>.from(jsonDecode(body) as Map);
    } finally {
      client.close(force: true);
    }
  }
}

String _randomUrlSafe(int bytes) {
  final random = Random.secure();
  return base64UrlEncode(
    List<int>.generate(bytes, (_) => random.nextInt(256)),
  ).replaceAll('=', '');
}

class CloudSyncResult {
  const CloudSyncResult(this.imported, this.total);
  final int imported;
  final int total;
}

class DriveCloudSync {
  DriveCloudSync(this.auth, {Uri? apiBase, Uri? uploadBase})
    : apiBase = apiBase ?? Uri.https('www.googleapis.com', '/drive/v3/'),
      uploadBase =
          uploadBase ?? Uri.https('www.googleapis.com', '/upload/drive/v3/');

  final CloudAuth auth;
  final Uri apiBase;
  final Uri uploadBase;
  static const backupName = 'lyricsfloat-backup-v1.json';

  Future<CloudSyncResult> sync(Library library) async {
    final token = await auth.accessToken();
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final files = await _requestJson(
        client,
        token,
        'GET',
        apiBase
            .resolve('files')
            .replace(
              queryParameters: {
                'spaces': 'appDataFolder',
                'q': "name = '$backupName' and trashed = false",
                'fields': 'files(id,modifiedTime),nextPageToken',
                'pageSize': '100',
              },
            ),
      );
      final candidates =
          (files['files'] as List<dynamic>? ?? [])
              .map((raw) => Map<String, dynamic>.from(raw as Map))
              .toList()
            ..sort(
              (a, b) => (b['modifiedTime'] as String? ?? '').compareTo(
                a['modifiedTime'] as String? ?? '',
              ),
            );
      final fileId = candidates.isEmpty
          ? null
          : candidates.first['id'] as String;
      var imported = 0;
      if (fileId != null) {
        final remote = await _requestJson(
          client,
          token,
          'GET',
          apiBase
              .resolve('files/${Uri.encodeComponent(fileId)}')
              .replace(queryParameters: {'alt': 'media'}),
        );
        if (remote['version'] != 1 || remote['songs'] is! List) {
          throw const FormatException('雲端歌詞備份格式不正確');
        }
        imported = await library.merge(remote['songs'] as List<dynamic>);
      }
      final content = jsonEncode({'version': 1, 'songs': library.export()});
      if (fileId == null) {
        final boundary = 'lyricsfloat-${_randomUrlSafe(12)}';
        final body =
            '--$boundary\r\n'
            'Content-Type: application/json; charset=UTF-8\r\n\r\n'
            '${jsonEncode({
              'name': backupName,
              'parents': ['appDataFolder'],
            })}\r\n'
            '--$boundary\r\n'
            'Content-Type: application/json; charset=UTF-8\r\n\r\n'
            '$content\r\n--$boundary--\r\n';
        await _requestJson(
          client,
          token,
          'POST',
          uploadBase
              .resolve('files')
              .replace(
                queryParameters: {'uploadType': 'multipart', 'fields': 'id'},
              ),
          body: body,
          contentType: ContentType(
            'multipart',
            'related',
            parameters: {'boundary': boundary},
          ),
        );
      } else {
        await _requestJson(
          client,
          token,
          'PATCH',
          uploadBase
              .resolve('files/${Uri.encodeComponent(fileId)}')
              .replace(queryParameters: {'uploadType': 'media'}),
          body: content,
          contentType: ContentType.json,
        );
      }
      return CloudSyncResult(imported, library.songs.length);
    } finally {
      client.close(force: true);
    }
  }

  Future<Map<String, dynamic>> _requestJson(
    HttpClient client,
    String token,
    String method,
    Uri uri, {
    String? body,
    ContentType? contentType,
  }) async {
    final request = await client.openUrl(method, uri);
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    if (body != null) {
      request.headers.contentType = contentType ?? ContentType.json;
      request.add(utf8.encode(body));
    }
    final response = await request.close();
    final text = await utf8.decoder.bind(response).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        'Google Drive 回應 ${response.statusCode}：${text.length > 400 ? text.substring(0, 400) : text}',
      );
    }
    return Map<String, dynamic>.from(jsonDecode(text) as Map);
  }
}
