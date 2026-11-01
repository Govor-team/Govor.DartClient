import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/external_links.dart';
import '../l10n/l10n.dart';
import 'design.dart';
import 'markdown_image.dart';
import '../core/media/remote_image_repository.dart';
import '../core/markdown_media.dart';

/// One renderer for encrypted messages and profile descriptions.
/// Images stay in the Markdown flow, including animated GIFs.
class GovorMarkdown extends StatelessWidget {
  const GovorMarkdown(
    this.data, {
    super.key,
    this.style,
    this.contextMenuBuilder,
    this.openLink,
  });
  static final _syntax = RegExp(
    r'[*_`~#>\[\]|]|https?://|(^|\n)\s*(?:[-+]|[0-9]+[.)])\s|(^|\n)-{3,}(\n|$)',
  );
  static bool hasFormatting(String text) => _syntax.hasMatch(text);
  final String data;
  final TextStyle? style;
  final EditableTextContextMenuBuilder? contextMenuBuilder;
  final Future<bool> Function(Uri)? openLink;
  Future<void> _open(BuildContext context, String? href) async {
    final uri = externalUri(href);
    if (uri == null) return;
    try {
      final opened =
          await (openLink?.call(uri) ??
              launchUrl(uri, mode: LaunchMode.externalApplication));
      if (!opened && context.mounted) {
        ScaffoldMessenger.maybeOf(
          context,
        )?.showSnackBar(SnackBar(content: Text(context.l10n.couldNotOpenLink)));
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.maybeOf(
          context,
        )?.showSnackBar(SnackBar(content: Text(context.l10n.couldNotOpenLink)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!hasFormatting(data)) {
      return SelectableText(
        data,
        style: style,
        contextMenuBuilder:
            contextMenuBuilder ??
            (context, state) => AdaptiveTextSelectionToolbar.editableText(
              editableTextState: state,
            ),
      );
    }
    final textStyle = Theme.of(context).textTheme.bodyMedium!.merge(style);
    final baseSize = textStyle.fontSize ?? 14;
    return MarkdownBody(
      data: markdownMedia(data),
      selectable: true,
      softLineBreak: true,
      fitContent: false,
      contextMenuBuilder:
          contextMenuBuilder ??
          (context, state) => AdaptiveTextSelectionToolbar.editableText(
            editableTextState: state,
          ),
      onTapLink: (text, href, title) => unawaited(_open(context, href)),
      imageBuilder: (uri, title, alt) => remoteImageUri(uri.toString()) == null
          ? const Icon(Icons.broken_image_outlined)
          : MarkdownImage(uri: uri, alt: alt),
      styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
        p: textStyle,
        a: textStyle.copyWith(
          color: accent,
          decoration: TextDecoration.underline,
        ),
        strong: textStyle.copyWith(fontWeight: FontWeight.w600),
        em: textStyle.copyWith(fontStyle: FontStyle.italic),
        h1: textStyle.copyWith(
          fontSize: baseSize * 24 / 14,
          fontWeight: FontWeight.w600,
        ),
        h2: textStyle.copyWith(
          fontSize: baseSize * 1.5,
          fontWeight: FontWeight.w600,
        ),
        h3: textStyle.copyWith(
          fontSize: baseSize * 18 / 14,
          fontWeight: FontWeight.w600,
        ),
        code: textStyle.copyWith(
          fontFamily: 'monospace',
          fontSize: baseSize * 12 / 14,
          backgroundColor: Colors.black12,
        ),
        codeblockDecoration: BoxDecoration(
          color: Colors.black12,
          borderRadius: BorderRadius.circular(8),
        ),
        blockquoteDecoration: BoxDecoration(
          border: Border(left: BorderSide(color: accent, width: 3)),
        ),
        blockquotePadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 4,
        ),
        listBullet: textStyle,
        tableBody: textStyle.copyWith(fontSize: baseSize * 12 / 14),
      ),
    );
  }
}
