import 'dart:typed_data';
import 'dart:ui' as ui;
import '../attachment_files.dart';

Future<void> validateImageBytes(
  Uint8List bytes, {
  int maxDimension = 16384,
  int maxPixels = 32000000,
}) async {
  if (!fileMime(bytes).startsWith('image/')) {
    throw const FormatException('Invalid image');
  }
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  try {
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    try {
      if (descriptor.width * descriptor.height > maxPixels ||
          descriptor.width > maxDimension ||
          descriptor.height > maxDimension) {
        throw const FormatException('Image dimensions exceeded');
      }
    } finally {
      descriptor.dispose();
    }
  } finally {
    buffer.dispose();
  }
}
