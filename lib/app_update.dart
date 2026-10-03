import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:pub_semver/pub_semver.dart';

const releaseRepository = 'MrRice-TW/LyricsFloat';

class AppUpdate {
  const AppUpdate(this.version, this.page);
  final Version version;
  final Uri page;
}

// Beta builds include prereleases; stable builds only offer stable releases.
// Only offer releases whose Windows installer has finished uploading.
AppUpdate? selectWindowsUpdate(List<dynamic> releases, Version current) {
  AppUpdate? newest;
  for (final entry in releases) {
    if (entry is! Map || entry['draft'] != false) continue;
    if (current.preRelease.isEmpty && entry['prerelease'] != false) continue;
    final tag = entry['tag_name'];
    if (tag is! String) continue;
    Version version;
    try {
      version = Version.parse(tag.startsWith('v') ? tag.substring(1) : tag);
    } on FormatException {
      continue;
    }
    if (version <= current) continue;
    if (current.preRelease.isEmpty && version.preRelease.isNotEmpty) continue;
    final assets = entry['assets'];
    if (assets is! List ||
        !assets.any(
          (asset) =>
              asset is Map &&
              asset['name'] == 'LyricsFloat-Windows-x64-Setup.exe' &&
              asset['state'] == 'uploaded' &&
              asset['size'] is num &&
              asset['size'] > 0,
        )) {
      continue;
    }
    if (newest == null || version > newest.version) {
      // Build the URL locally rather than trusting URLs in the response.
      newest = AppUpdate(
        version,
        Uri.https('github.com', '/$releaseRepository/releases/tag/$tag'),
      );
    }
  }
  return newest;
}

class AppUpdateChecker {
  AppUpdateChecker({HttpClient Function()? createClient})
    : _createClient = createClient ?? HttpClient.new;
  final HttpClient Function() _createClient;

  Future<AppUpdate?> check(Version current) async {
    final client = _createClient();
    client.connectionTimeout = const Duration(seconds: 5);
    try {
      return await _fetch(client, current).timeout(const Duration(seconds: 10));
    } finally {
      client.close(force: true);
    }
  }

  Future<AppUpdate?> _fetch(HttpClient client, Version current) async {
    final request = await client.getUrl(
      Uri.https('api.github.com', '/repos/$releaseRepository/releases', {
        'per_page': '100',
      }),
    );
    request.headers.set(
      HttpHeaders.acceptHeader,
      'application/vnd.github+json',
    );
    request.headers.set(HttpHeaders.userAgentHeader, 'LyricsFloat/$current');
    request.headers.set('X-GitHub-Api-Version', '2022-11-28');
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException('Update check failed (${response.statusCode})');
    }
    final bytes = <int>[];
    await for (final chunk in response) {
      bytes.addAll(chunk);
      if (bytes.length > 2 * 1024 * 1024) {
        throw const FormatException('Release response is too large');
      }
    }
    final releases = jsonDecode(utf8.decode(bytes));
    if (releases is! List) throw const FormatException('Invalid release list');
    return selectWindowsUpdate(releases, current);
  }
}
