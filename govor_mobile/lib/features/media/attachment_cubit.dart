import '../../core/media/image_validation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/attachment_files.dart';
import '../../core/media/attachment_repository.dart';

enum AttachmentStatus { initial, loading, ready, failed }

@immutable
class AttachmentState {
  const AttachmentState(this.status, [this.bytes]);
  final AttachmentStatus status;
  final Uint8List? bytes;
}

class AttachmentCubit extends Cubit<AttachmentState> {
  AttachmentCubit(this.repository, this.attachment)
    : super(const AttachmentState(AttachmentStatus.initial));
  final AttachmentRepository repository;
  final Attachment attachment;
  Future<void> load() async {
    if (state.status == AttachmentStatus.loading ||
        state.status == AttachmentStatus.ready) {
      return;
    }
    emit(const AttachmentState(AttachmentStatus.loading));
    try {
      final bytes = await repository.load(attachment);
      final detected = fileMime(bytes);
      if (attachment.isImage) {
        await validateImageBytes(bytes);
      } else if (attachment.isVideo && !detected.startsWith('video/')) {
        throw const FormatException('Invalid video');
      }
      if (!isClosed) emit(AttachmentState(AttachmentStatus.ready, bytes));
    } catch (_) {
      if (!isClosed) emit(const AttachmentState(AttachmentStatus.failed));
    }
  }
}
