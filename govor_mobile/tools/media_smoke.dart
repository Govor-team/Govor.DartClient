import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:media_kit/media_kit.dart';
import 'package:govor_mobile/core/media/playback_source_native.dart';

/// Run with the libmpv library path and local video path as arguments.
/// Uses a local temporary source, exactly as the attachment viewer does.
Future<void> main(List<String> args) async {
  if (args.length != 2) throw ArgumentError('Expected libmpv and video paths');
  MediaKit.ensureInitialized(libmpv: File(args[0]).absolute.path);
  final source = await PlaybackSource.create(
    await File(args[1]).readAsBytes(),
    'video/mp4',
  );
  final player = Player(
    configuration: const PlayerConfiguration(
      vo: 'null',
      protocolWhitelist: ['file', 'data', 'crypto'],
    ),
  );
  try {
    final width = player.stream.width
        .firstWhere((value) => value != null && value > 0)
        .timeout(const Duration(seconds: 20));
    final durationReady = player.stream.duration
        .firstWhere((value) => value > Duration.zero)
        .timeout(const Duration(seconds: 20));
    await player.setVolume(0);
    await player.setVideoTrack(VideoTrack.auto());
    await player.open(Media(source.uri), play: true);
    final value = await width;
    final duration = await durationReady;
    stdout.writeln(
      jsonEncode({'width': value, 'durationMs': duration.inMilliseconds}),
    );
  } finally {
    await player.dispose();
    await source.dispose();
  }
  if (await File(source.uri).exists()) {
    throw StateError('Playback source leaked');
  }
  stdout.writeln('Playback source cleaned');
}
