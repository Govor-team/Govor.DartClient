import 'media/remote_image_repository.dart';

/// Also recognize standalone media links used by older clients. Code blocks and
/// ordinary links remain literal; standard Markdown handles inline/reference images.
String markdownMedia(String source) {
  String? fence;
  return source
      .split('\n')
      .map((line) {
        final marker = RegExp(r'^\s{0,3}(`{3,}|~{3,})').firstMatch(line)?[1];
        if (marker != null) {
          if (fence == null) {
            fence = marker;
          } else if (marker.startsWith(fence![0]) &&
              marker.length >= fence!.length) {
            fence = null;
          }
          return line;
        }
        if (fence != null || line.startsWith('    ')) return line;
        final trimmed = line.trim();
        final link = RegExp(
          r'^\[([^\]]*)\]\((https?://[^\s)]+)\)$',
        ).firstMatch(trimmed);
        final candidate = link?[2] ?? trimmed;
        final uri = remoteImageUri(candidate);
        if (uri != null &&
            RegExp(
              r'\.(gif|png|jpe?g|webp)$',
              caseSensitive: false,
            ).hasMatch(uri.path)) {
          return '![${link?[1] ?? ''}]($candidate)';
        }
        return line;
      })
      .join('\n');
}
