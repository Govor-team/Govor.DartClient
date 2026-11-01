import 'dart:typed_data';
import 'package:govor_mobile/core/media/attachment_repository.dart';

class FakeAttachments implements AttachmentRepository {
  FakeAttachments(this.bytes);
  final Uint8List bytes;
  @override
  Future<Uint8List> load(Attachment attachment) async => bytes;
  @override
  Future<Attachment> upload(Uint8List bytes, String name) async =>
      throw UnimplementedError();
  @override
  void clear() {}
}
