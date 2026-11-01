import 'dart:async';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../attachment_files.dart';
import '../external_links.dart';
import 'image_validation.dart';

/// Markdown images use a separate, unauthenticated client. Never send API tokens
/// or accept local/application URLs. Redirects pass through the same validation.
Uri? remoteImageUri(String value) {
  final uri = externalUri(value);
  if (uri == null) return null;
  final host = uri.host.toLowerCase().replaceAll('[', '').replaceAll(']', '');
  if (host == 'localhost' ||
      host.endsWith('.localhost') ||
      host.endsWith('.local') ||
      host == '::1' ||
      host == '::' ||
      host.startsWith('fc') && host.contains(':') ||
      host.startsWith('fd') && host.contains(':') ||
      host.startsWith('fe80:') ||
      host.contains('::ffff:')) {
    return null;
  }
  final parts = host.split('.').map(int.tryParse).toList();
  if (parts.length == 4 && parts.every((n) => n != null)) {
    final a = parts[0]!, b = parts[1]!;
    if (a == 0 ||
        a == 10 ||
        a == 127 ||
        a >= 224 ||
        a == 169 && b == 254 ||
        a == 172 && b >= 16 && b <= 31 ||
        a == 192 && b == 168) {
      return null;
    }
  }
  return uri;
}

class RemoteImageRepository {
  RemoteImageRepository({http.Client? client})
    : _client = client ?? http.Client();
  final http.Client _client;
  static const maxBytes = 10 * 1024 * 1024;
  Future<Uint8List> load(Uri uri) async {
    final abort = Completer<void>();
    final timer = Timer(const Duration(seconds: 20), () => abort.complete());
    try {
      return await _load(
        uri,
        abort.future,
      ).timeout(const Duration(seconds: 21));
    } finally {
      timer.cancel();
    }
  }

  Future<Uint8List> _load(Uri uri, Future<void> abort) async {
    for (var redirects = 0; redirects <= 3; redirects++) {
      if (remoteImageUri(uri.toString()) == null) {
        throw const FormatException('Image URL');
      }
      final request = http.AbortableRequest('GET', uri, abortTrigger: abort)
        ..followRedirects = false;
      final response = await _client.send(request);
      if ([301, 302, 303, 307, 308].contains(response.statusCode)) {
        final location = response.headers['location'];
        // Cancel the response stream; do not read an unbounded redirect body.
        await response.stream.listen((_) {}).cancel();
        if (location == null) throw const FormatException('Redirect');
        uri = uri.resolve(location);
        continue;
      }
      if (response.statusCode != 200 ||
          (response.contentLength ?? 0) > maxBytes) {
        await response.stream.listen((_) {}).cancel();
        throw const FormatException('Image response');
      }
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response.stream) {
        if (bytes.length + chunk.length > maxBytes) {
          throw const FormatException('Image size');
        }
        bytes.add(chunk);
      }
      final data = bytes.takeBytes();
      if (![
        'image/png',
        'image/jpeg',
        'image/webp',
        'image/gif',
      ].contains(fileMime(data))) {
        throw const FormatException('Image format');
      }
      await validateImageBytes(data);
      return data;
    }
    throw const FormatException('Redirect limit');
  }

  void close() => _client.close();
}
