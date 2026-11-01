import 'package:flutter/material.dart';
import 'app.dart';
import 'package:media_kit/media_kit.dart';
import 'core/server_ip_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  final server = await ServerIpProvider.load();
  runApp(GovorApp(serverProvider: server));
}
