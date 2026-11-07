import 'package:flutter_test/flutter_test.dart';
import 'package:govor_mobile/core/app_update.dart';
import 'package:govor_mobile/core/app_info.dart';

const installed = AppInfo(
  name: 'Govor',
  version: '1.2.3',
  buildNumber: '5',
  packageName: 'app.govor.client',
);
Map<String, dynamic> release(
  String tag,
  List<String> names, {
  bool preview = false,
}) => {
  'tag_name': tag,
  'prerelease': preview,
  'assets': [
    for (final name in names)
      {
        'name': name,
        'size': 1024,
        'digest': 'sha256:${List.filled(64, 'a').join()}',
        'browser_download_url':
            'https://github.com/Govor-team/Govor.DartClient/releases/download/$tag/$name',
      },
  ],
};
void main() {
  test(
    'compares numeric versions and build numbers; rejects prerelease tags',
    () {
      expect(
        ReleaseVersion.parse(
          'v1.10.0',
        )!.compareTo(ReleaseVersion.parse('1.9.9')!),
        greaterThan(0),
      );
      expect(
        ReleaseVersion.parse(
          '1.2.3+6',
        )!.compareTo(ReleaseVersion.parse('1.2.3+5')!),
        greaterThan(0),
      );
      expect(ReleaseVersion.parse('1.2.3-beta'), isNull);
    },
  );
  test('selects highest compatible release and prefers device ABI', () {
    final next = AppUpdateService.select(
      [
        release('v1.3.0', ['app-release.apk']),
        release('v1.4.0', ['app-x86_64-release.apk']),
        release('v1.3.1', ['app-release.apk', 'app-arm64-v8a-release.apk']),
      ],
      installed,
      ['arm64-v8a', 'armeabi-v7a'],
    );
    expect(next!.version, 'v1.3.1');
    expect(next.url, contains('arm64-v8a'));
  });
  test(
    'ignores old, preview, debug, missing, incompatible and untrusted assets',
    () {
      for (final item in [
        release('1.2.3+5', ['app-release.apk']),
        release('2.0.0', ['app-release.apk'], preview: true),
        release('2.0.0', ['app-debug.apk']),
        release('2.0.0', []),
        release('2.0.0', ['app-x86_64-release.apk']),
      ]) {
        expect(
          AppUpdateService.select([item], installed, ['arm64-v8a']),
          isNull,
        );
      }
      final bad = release('2.0.0', ['app-release.apk']);
      (bad['assets'] as List).first['digest'] = '';
      expect(AppUpdateService.select([bad], installed, ['arm64-v8a']), isNull);
      final evil = release('2.0.0', ['app-release.apk']);
      (evil['assets'] as List).first['browser_download_url'] =
          'https://evil.example/app.apk';
      expect(AppUpdateService.select([evil], installed, ['arm64-v8a']), isNull);
    },
  );
}
