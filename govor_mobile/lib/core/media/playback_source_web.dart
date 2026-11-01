import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;

class PlaybackSource {
  PlaybackSource._(this.uri);
  final String uri;
  static Future<PlaybackSource> create(Uint8List bytes, String mime) async =>
      PlaybackSource._(
        web.URL.createObjectURL(
          web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: mime)),
        ),
      );
  Future<void> dispose() async => web.URL.revokeObjectURL(uri);
}
