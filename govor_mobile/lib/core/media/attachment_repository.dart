import 'package:flutter/foundation.dart';
import '../api_client.dart';
import '../crypto/e2ee_protocol.dart';
import '../models.dart';
import '../attachment_files.dart';
import '../crypto/primitives.dart';

@immutable
class Attachment {
  const Attachment({
    required this.id,
    required this.key,
    required this.name,
    required this.mime,
  });
  factory Attachment.fromJson(Json json) {
    final name = field(json, 'fileName') as String;
    var mime = field(json, 'mimeType') as String? ?? 'application/octet-stream';
    // Older clients sent video metadata as octet-stream. The extension is only
    // a hint; AttachmentCubit verifies the decrypted header before rendering.
    if (mime == 'application/octet-stream') {
      mime = switch (name.toLowerCase().split('.').last) {
        'mp4' || 'm4v' => 'video/mp4',
        'mov' => 'video/quicktime',
        'webm' => 'video/webm',
        'mkv' => 'video/x-matroska',
        _ => mime,
      };
    }
    return Attachment(
      id: field(json, 'mediaId') as String,
      key: field(json, 'key') as String,
      name: name,
      mime: mime,
    );
  }
  final String id, key, name, mime;
  bool get isImage => const [
    'image/png',
    'image/jpeg',
    'image/webp',
    'image/gif',
  ].contains(mime);
  bool get isVideo => const [
    'video/mp4',
    'video/webm',
    'video/quicktime',
    'video/x-matroska',
  ].contains(mime);
  Json toJson() => {
    'MediaId': id,
    'Key': key,
    'FileName': name,
    'MimeType': mime,
  };
  // Keys are never emitted into diagnostics or persistence.
  @override
  String toString() => 'Attachment($id, $mime)';
}

abstract interface class AttachmentRepository {
  Future<Uint8List> load(Attachment attachment);
  Future<Attachment> upload(Uint8List bytes, String name);
  void clear();
}

/// Authenticated download -> verified decryption -> bounded session-only cache.
class EncryptedAttachmentRepository implements AttachmentRepository {
  EncryptedAttachmentRepository(this.api, {this.maxCacheBytes = 38000000});
  final ApiClient api;
  final int maxCacheBytes;
  final _cache = <(String, String), Uint8List>{};
  final _pending = <(String, String), Future<Uint8List>>{};
  int _bytes = 0, _generation = 0;
  @override
  Future<Uint8List> load(Attachment attachment) {
    final id = (attachment.id, attachment.key);
    final cached = _cache.remove(id);
    if (cached != null) {
      _cache[id] = cached;
      return Future.value(cached);
    }
    return _pending.putIfAbsent(id, () async {
      final generation = _generation;
      try {
        final data = await api.downloadAttachment(
          attachment.id,
          maxBytes: 20000000,
        );
        final plaintext = (await compute(_decrypt, (
          data,
          attachment.key,
        ))).asUnmodifiableView();
        if (generation != _generation) throw StateError('Session ended');
        _remember(id, plaintext);
        return plaintext;
      } finally {
        if (generation == _generation) _pending.remove(id);
      }
    });
  }

  void _remember((String, String) id, Uint8List bytes) {
    if (bytes.length > maxCacheBytes) return;
    final old = _cache.remove(id);
    if (old != null) _bytes -= old.length;
    while (_cache.isNotEmpty && _bytes + bytes.length > maxCacheBytes) {
      _bytes -= _cache.remove(_cache.keys.first)!.length;
    }
    _cache[id] = bytes;
    _bytes += bytes.length;
  }

  @override
  Future<Attachment> upload(Uint8List bytes, String name) async {
    requireCrypto(
      bytes.isNotEmpty && bytes.length <= 19000000,
      'Неверный размер вложения.',
    );
    final generation = _generation;
    final sealed = await compute(_encrypt, bytes);
    if (generation != _generation) throw StateError('Session ended');
    final id = await api.uploadAttachment(sealed.data);
    if (generation != _generation) throw StateError('Session ended');
    final attachment = Attachment(
      id: id,
      key: sealed.key,
      name: safeFileName(name),
      mime: fileMime(bytes),
    );
    _remember((id, sealed.key), Uint8List.fromList(bytes).asUnmodifiableView());
    return attachment;
  }

  @override
  void clear() {
    _generation++;
    _cache.clear();
    _pending.clear();
    _bytes = 0;
  }
}

Uint8List _decrypt((Uint8List, String) value) =>
    E2eeProtocol.decryptAttachment(value.$1, value.$2);

({Uint8List data, String key}) _encrypt(Uint8List value) =>
    E2eeProtocol.encryptAttachment(value);
