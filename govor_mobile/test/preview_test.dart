import 'package:govor_mobile/ui/avatar_preview.dart';
import 'package:govor_mobile/ui/group_invitation_dialog.dart';
import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:govor_mobile/app.dart';
import 'package:govor_mobile/core/storage.dart';
import 'package:govor_mobile/features/messenger_controller.dart';
import 'package:govor_mobile/core/models.dart';
import 'package:govor_mobile/ui/message_actions.dart';
import 'package:govor_mobile/ui/user_profile_dialog.dart';
import 'package:govor_mobile/ui/attachment_gallery.dart';
import 'support/fake_attachments.dart';

void main() {
  testWidgets('render desktop, mobile and sign-in previews', (tester) async {
    await tester.runAsync(() async {
      final config =
          jsonDecode(File('.dart_tool/package_config.json').readAsStringSync())
              as Map<String, dynamic>;
      final flutterRoot = Uri.parse(
        config['flutterRoot'] as String,
      ).toFilePath();
      for (final entry in {
        'GovorSans': [
          'assets/fonts/OpenSans-Regular.ttf',
          'assets/fonts/OpenSans-Semibold.ttf',
        ],
        'GovorDisplay': ['assets/fonts/cyrillicold.ttf'],
        'MaterialIcons': [
          '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
        ],
        'Segoe UI Emoji': ['C:/Windows/Fonts/seguiemj.ttf'],
      }.entries) {
        final loader = FontLoader(entry.key);
        var present = false;
        for (final path in entry.value) {
          final file = File(path);
          if (file.existsSync()) {
            present = true;
            loader.addFont(
              Future.value(ByteData.sublistView(file.readAsBytesSync())),
            );
          }
        }
        if (present) await loader.load().timeout(const Duration(seconds: 20));
      }
    });
    final boundary = GlobalKey();
    final c = MessengerController(store: MemorySecretStore())..startDemo();
    addTearDown(c.dispose);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    Future<void> capture(String name, Size size) async {
      tester.view.physicalSize = size;
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: GovorApp(controller: c),
        ),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        for (final asset in MessengerController.wallpapers) {
          await precacheImage(AssetImage(asset), boundary.currentContext!);
          await precacheImage(
            ResizeImage.resizeIfNeeded(360, null, AssetImage(asset)),
            boundary.currentContext!,
          );
        }
      });
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        final image =
            await (boundary.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary)
                .toImage(pixelRatio: 1.5);
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        final dir = Directory('build/previews')..createSync(recursive: true);
        await File(
          '${dir.path}/$name.png',
        ).writeAsBytes(png!.buffer.asUint8List());
        image.dispose();
      });
      expect(tester.takeException(), isNull);
    }

    await c.open(c.conversations.first);
    await capture('desktop', const Size(1440, 940));
    await capture('mobile', const Size(390, 844));
    final menu = showMessageActions(
      tester.element(find.byKey(const Key('message-composer'))),
      c,
      c.messages.last,
      position: const Offset(140, 240),
    );
    await tester.pumpAndSettle();
    await capture('message-menu', const Size(390, 844));
    await tester.tap(find.byKey(const Key('expand-reactions')));
    await tester.pumpAndSettle();
    await capture('reaction-picker', const Size(390, 844));
    Navigator.pop(tester.element(find.byKey(const Key('expand-reactions'))));
    await tester.pumpAndSettle();
    await menu;
    c.media = FakeAttachments(
      File('assets/backgrounds/background_girls.jpg').readAsBytesSync(),
    );
    c.messages.add(
      ChatMessage(
        id: 'preview-photo',
        senderId: 'demo-friend',
        conversationId: c.selected!.id,
        type: 0,
        sentAt: DateTime.now(),
        content: '',
        text: 'Фото из путешествия',
        attachments: const [
          {
            'MediaId': 'preview-media',
            'Key': 'fixture',
            'FileName': 'journey.jpg',
            'MimeType': 'image/jpeg',
          },
        ],
      ),
    );
    await capture('media-chat', const Size(1440, 940));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(AttachmentGallery).last);
    await tester.pumpAndSettle();
    await capture('media-chat', const Size(1440, 940));
    final profileDialog = showUserProfile(
      tester.element(find.byKey(const Key('message-composer'))),
      c,
      'demo-friend',
    );
    await tester.pumpAndSettle();
    await capture('user-profile', const Size(390, 844));
    await tester.tap(find.byTooltip('Закрыть'));
    await tester.pumpAndSettle();
    await profileDialog;
    c.closeChat();
    c.me = Person(
      id: c.me!.id,
      name: c.me!.name,
      description: c.me!.description,
      iconId: 'preview-avatar',
    );
    c.avatarBytes['preview-avatar'] = File(
      'assets/backgrounds/background_girls.jpg',
    ).readAsBytesSync();
    await capture('home', const Size(390, 844));
    await tester.tap(find.byTooltip('Настройки'));
    await tester.pumpAndSettle();
    await capture('profile', const Size(390, 844));
    await capture('profile-desktop', const Size(1440, 940));
    await tester.tap(find.byType(PreviewAvatar).last);
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 150));
    });
    await tester.pumpAndSettle();
    await capture('avatar-preview-desktop', const Size(1440, 940));
    await capture('avatar-preview-mobile', const Size(390, 844));
    await tester.tap(find.byTooltip('Закрыть'));
    await tester.pumpAndSettle();
    final invitation = showDialog<Map<String, dynamic>>(
      context: tester.element(find.byKey(const Key('profile-description'))),
      builder: (_) => GroupInvitationDialog(create: (_) async => {}),
    );
    await tester.pumpAndSettle();
    await capture('invitation-form-mobile', const Size(390, 844));
    await tester.tap(find.text('Закрыть'));
    await tester.pumpAndSettle();
    await invitation;
    c.settings.previewFontSize(22);
    await capture('text-size-desktop', const Size(1440, 940));
    c.settings.previewFontSize(14);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('language-selector')));
    await tester.tap(find.byKey(const Key('language-selector')));
    await tester.pumpAndSettle();
    await capture('language-popup', const Size(1440, 940));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await capture('profile', const Size(390, 844));
    await tester.scrollUntilVisible(
      find.text('Защита переписки'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Защита переписки'));
    await tester.pumpAndSettle();
    await capture('security', const Size(390, 844));
    await tester.tap(find.byTooltip('Назад'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Паки реакций'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Паки реакций'));
    await tester.pumpAndSettle();
    await capture('reactions', const Size(390, 844));
    await tester.tap(find.byTooltip('Назад'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Назад'));
    await tester.pumpAndSettle();
    await c.logout();
    await capture('login', const Size(780, 960));
  });
}
