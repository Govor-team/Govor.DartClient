import 'dart:io';
import 'dart:typed_data';

class PlaybackSource {
  PlaybackSource._(this.uri, this.directory);
  final String uri;
  final Directory directory;
  static Future<PlaybackSource> create(Uint8List bytes, String mime) async {
    final directory = await Directory.systemTemp.createTemp('govor-playback-');
    try {
      final file = File('${directory.path}${Platform.pathSeparator}video.bin');
      await file.writeAsBytes(bytes, flush: true);
      return PlaybackSource._(file.path, directory);
    } catch (_) {
      await directory.delete(recursive: true);
      rethrow;
    }
  }

  Future<void> dispose() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  }
}
