import 'package:package_info_plus/package_info_plus.dart';

class AppInfo {
  const AppInfo({
    required this.name,
    required this.version,
    required this.buildNumber,
    required this.packageName,
  });
  final String name, version, buildNumber, packageName;
  String get displayVersion =>
      buildNumber.isEmpty ? version : '$version+$buildNumber';
}

/// Reads the built package's metadata (version.json on web). Flutter populates it
/// from pubspec.yaml, including --build-name / --build-number overrides.
class AppInfoService {
  Future<AppInfo>? _cached;
  Future<AppInfo> load() => _cached ??= _load();
  Future<AppInfo> _load() async {
    final info = await PackageInfo.fromPlatform();
    return AppInfo(
      name: info.appName,
      version: info.version,
      buildNumber: info.buildNumber,
      packageName: info.packageName,
    );
  }
}
