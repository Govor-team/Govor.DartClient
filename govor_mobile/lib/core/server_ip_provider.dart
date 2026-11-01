import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'dart:convert';

import 'api_client.dart';

/// Build-time equivalent of MAUI's IServerIpProvider/ServerIpProvider.
/// `flutter build ... --dart-define-from-file=config/production.json`
/// Configuration is public application metadata, never a place for secrets.
class ServerIpProvider {
  const ServerIpProvider({
    this.address = const String.fromEnvironment('GOVOR_SERVER'),
    this.allowLocalHttp = const bool.fromEnvironment('GOVOR_ALLOW_LOCAL_HTTP'),
  });
  final String address;
  final bool allowLocalHttp;
  static Future<ServerIpProvider> load() async {
    const compiled = ServerIpProvider();
    if (compiled.address.isNotEmpty) {
      compiled.server;
      return compiled;
    }
    final json =
        jsonDecode(await rootBundle.loadString('config/production.json'))
            as Map<String, dynamic>;
    final provider = ServerIpProvider(
      address: json['GOVOR_SERVER'] as String,
      allowLocalHttp: json['GOVOR_ALLOW_LOCAL_HTTP'] == true,
    );
    provider.server;
    return provider;
  }

  ServerAddress get server =>
      ServerAddress(address, allowLoopbackHttp: kDebugMode && allowLocalHttp);
}
