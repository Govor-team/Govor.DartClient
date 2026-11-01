/// Markdown content cannot launch local files, data URLs or application schemes.
Uri? externalUri(String? href) {
  if (href == null ||
      href.length > 8192 ||
      RegExp(r'[\x00-\x20\x7f]').hasMatch(href)) {
    return null;
  }
  final uri = Uri.tryParse(href);
  if (uri == null ||
      !['https', 'http'].contains(uri.scheme) ||
      !uri.hasAuthority ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty) {
    return null;
  }
  return uri;
}
