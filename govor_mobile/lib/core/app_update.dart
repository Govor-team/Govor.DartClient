import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'app_info.dart';

class ReleaseVersion implements Comparable<ReleaseVersion> {
  ReleaseVersion(this.parts, this.build);
  final List<int> parts;
  final int build;
  static ReleaseVersion? parse(String text) {
    final m = RegExp(r'^v?(\d+)\.(\d+)\.(\d+)(?:\+(\d+))?$').firstMatch(text);
    return m == null
        ? null
        : ReleaseVersion([
            for (var i = 1; i <= 3; i++) int.parse(m[i]!),
          ], int.parse(m[4] ?? '0'));
  }

  @override
  int compareTo(ReleaseVersion other) {
    for (var i = 0; i < 3; i++) {
      final c = parts[i].compareTo(other.parts[i]);
      if (c != 0) return c;
    }
    return build.compareTo(other.build);
  }
}

class AppUpdate {
  AppUpdate(this.version, this.url, this.size, this.digest);
  final String version, url, digest;
  final int size;
}

class AppUpdateService {
  static const channel = MethodChannel('app.govor.client/updates');
  static const repository = String.fromEnvironment(
    'GOVOR_UPDATE_REPOSITORY',
    defaultValue: 'Govor-team/Govor.DartClient',
  );
  static AppUpdate? select(
    List<dynamic> releases,
    AppInfo installed,
    List<String> abis,
  ) {
    final current = ReleaseVersion.parse(
      '${installed.version}+${installed.buildNumber.isEmpty ? '0' : installed.buildNumber}',
    );
    if (current == null) return null;
    AppUpdate? best;
    var bestVersion = current;
    for (final item in releases.whereType<Map<String, dynamic>>()) {
      if (item['draft'] == true || item['prerelease'] == true) continue;
      final tag = item['tag_name'];
      final version = tag is String ? ReleaseVersion.parse(tag) : null;
      if (version == null || version.compareTo(bestVersion) <= 0) continue;
      final assets = item['assets'];
      if (assets is! List) continue;
      final candidates = <(int, AppUpdate)>[];
      for (final asset in assets.whereType<Map<String, dynamic>>()) {
        final name = (asset['name'] as String? ?? '').toLowerCase();
        if (!name.endsWith('.apk') || name.contains('debug')) continue;
        final arch = [
          'arm64-v8a',
          'armeabi-v7a',
          'x86_64',
        ].where((a) => name.contains(a)).toList();
        if (arch.isNotEmpty && !abis.contains(arch.first)) continue;
        if (name.contains('x86') && arch.isEmpty) continue;
        final url = Uri.tryParse(
          asset['browser_download_url'] as String? ?? '',
        );
        final digest = asset['digest'] as String? ?? '';
        final size = asset['size'];
        if (url == null ||
            url.scheme != 'https' ||
            url.host != 'github.com' ||
            !url.path.startsWith('/$repository/releases/download/') ||
            size is! int ||
            size <= 0 ||
            size > 512 * 1024 * 1024 ||
            !RegExp(r'^sha256:[a-fA-F0-9]{64}$').hasMatch(digest)) {
          continue;
        }
        candidates.add((
          arch.isEmpty ? 100 : abis.indexOf(arch.first),
          AppUpdate(tag as String, url.toString(), size, digest.substring(7)),
        ));
      }
      candidates.sort((a, b) => a.$1.compareTo(b.$1));
      if (candidates.isNotEmpty) {
        best = candidates.first.$2;
        bestVersion = version;
      }
    }
    return best;
  }

  Future<AppUpdate?> check() async {
    final abis = await channel.invokeListMethod<String>('abis') ?? [];
    final info = await AppInfoService().load();
    final client = http.Client();
    try {
      final response = await client
          .get(
            Uri.https('api.github.com', '/repos/$repository/releases', {
              'per_page': '100',
            }),
            headers: {'Accept': 'application/vnd.github+json'},
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body);
      return data is List ? select(data, info, abis) : null;
    } finally {
      client.close();
    }
  }

  Future<void> install(AppUpdate update) => channel.invokeMethod<void>(
    'install',
    {'url': update.url, 'size': update.size, 'digest': update.digest},
  );
}
