import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:govor_mobile/core/api_client.dart';
import 'package:govor_mobile/core/app_dependencies.dart';
import 'package:govor_mobile/core/auth_service.dart';
import 'package:govor_mobile/core/chat_hub.dart';
import 'package:govor_mobile/core/crypto/primitives.dart';
import 'package:govor_mobile/core/encryption_service.dart';
import 'package:govor_mobile/core/models.dart';
import 'package:govor_mobile/core/preferences_repository.dart';
import 'package:govor_mobile/core/server_ip_provider.dart';
import 'package:govor_mobile/core/storage.dart';
import 'package:govor_mobile/core/wallpapers.dart';
import 'package:govor_mobile/features/messenger_controller.dart';
import 'auth_fixtures.dart' show tokenJson, testUser;

const peer = '22222222-2222-4222-8222-222222222222',
    chat = '33333333-3333-4333-8333-333333333333',
    group = '44444444-4444-4444-8444-444444444444';

class FlowEncryption extends EncryptionService {
  FlowEncryption(super.api);
  int encryptions = 0, initializations = 0;
  @override
  Future<void> initialize({String? recoveryCode}) async {
    initializations++;
  }

  @override
  Future<String> encrypt(
    Conversation chat,
    String text,
    String messageId, {
    String? replyTo,
    bool edit = false,
    List<Json> attachments = const [],
  }) async {
    encryptions++;
    return jsonEncode({
      'id': messageId,
      'text': text,
      'files': attachments,
      'edit': edit,
    });
  }

  @override
  Future<ChatMessage> decrypt(ChatMessage message) async {
    if (message.content == 'bad') {
      throw const CryptoFailure('invalid signature');
    }
    final json = object(jsonDecode(message.content));
    return message.decoded(
      json['text'] as String,
      objects(json['files'] ?? []),
    );
  }

  @override
  Future<void> synchronize() async {}
}

class FlowAuth extends AuthService {
  FlowAuth(super.api);
  @override
  Future<void> login(String name, String password) =>
      api.accept(TokenPair.fromJson(tokenJson('flow')));
  @override
  Future<void> register(String name, String password, String invitation) =>
      login(name, password);
}

class FlowHub extends ChatHub {
  FlowHub(super.api, String path) : super(path: path);
  bool stopped = false, failNextSend = false;
  final commands = <(String, List<Object?>)>[];
  @override
  Future<void> start() async {
    status = ConnectionStatus.connected;
    onStatus?.call(status);
  }

  @override
  Future<void> stop() async {
    stopped = true;
    status = ConnectionStatus.offline;
  }

  @override
  Future<dynamic> invoke(String method, List<Object?> args) async {
    commands.add((method, args));
    if (method == 'Send') {
      if (failNextSend) {
        failNextSend = false;
        throw const ApiFailure(408, 'no acknowledgement');
      }
      final body = object(args.single),
          sealed = object(jsonDecode(body['encryptedContent'] as String));
      return {
        'messageId': sealed['id'],
        'senderId': testUser,
        'recipientId': body['recipientId'],
        'recipientType': body['recipientType'],
        'sentAt': DateTime.now().toUtc().toIso8601String(),
        'encryptedContent': body['encryptedContent'],
        'replyToMessageId': body['replyToMessageId'],
        'forwardedFromMessageId': body['forwardedFromMessageId'],
        'forwardedFromUserId': body['forwardedFromMessageId'] == null
            ? null
            : peer,
        'forwardedFromSentAt': body['forwardedFromMessageId'] == null
            ? null
            : DateTime.utc(2026).toIso8601String(),
      };
    }
    return null;
  }
}

class FlowFixture {
  FlowFixture() {
    api = ApiClient(
      ServerAddress('https://test.example'),
      store,
      client: MockClient((request) async {
        routes.add('${request.method} ${request.url.path}');
        final custom = overrideResponse?.call(request);
        if (custom != null) return custom;
        Object? response;
        switch (request.url.path) {
          case '/api/profile/download/me':
            response = {
              'id': testUser,
              'username': 'Me',
              'description': description,
            };
          case '/api/profile/download/$peer':
            response = {'id': peer, 'username': 'Peer'};
          case '/api/friends':
            response = [
              {'id': peer, 'username': 'Peer', 'isOnline': true},
            ];
          case '/api/user/private-chats':
            response = [
              {'chatId': chat, 'friendId': peer},
            ];
          case '/api/groups/mine':
            response = [
              {
                'id': group,
                'name': 'Group',
                'description': '**Group**',
                'myRole': 2,
                'isChannel': false,
                'canLeave': false,
              },
            ];
          case '/api/friends/requests':
          case '/api/friends/responses':
            response = <Json>[];
          case '/api/user/$peer/private-chat':
            response = chat;
          case '/api/user/$chat/messages':
          case '/api/groups/$group/messages':
            response = history;
          case '/api/friends/search':
            response = [
              {'id': peer, 'username': 'Peer'},
            ];
          default:
            if (request.url.path.endsWith('/unread-count')) {
              response = {'unreadCount': 2};
            } else if (request.url.path.endsWith('/read') ||
                request.method == 'DELETE') {
              return http.Response('', 204);
            } else {
              return http.Response('', 404);
            }
        }
        return http.Response(jsonEncode(response), 200);
      }),
    );
    encryption = FlowEncryption(api);
    controller = MessengerController(
      store: store,
      serverProvider: const ServerIpProvider(address: 'https://test.example'),
      wallpaperRepository: WallpaperRepository(
        read: () async => null,
        write: (_) async {},
      ),
      dependencies: AppDependencies(
        api: (_, _) => api,
        auth: FlowAuth.new,
        encryption: (_) => encryption,
        hub: (api, path) => hubs.putIfAbsent(path, () => FlowHub(api, path)),
        preferences: LocalPreferencesRepository(
          read: () async => null,
          write: (_) async {},
        ),
      ),
    );
  }
  final store = MemorySecretStore();
  late final ApiClient api;
  late final FlowEncryption encryption;
  late final MessengerController controller;
  final hubs = <String, FlowHub>{}, routes = <String>[];
  http.Response? Function(http.Request)? overrideResponse;
  List<Json> history = [];
  String description = '';
  Future<void> boot() async {
    await api.accept(TokenPair.fromJson(tokenJson('flow')));
    await controller.boot();
  }

  Json message(
    String id, {
    String conversation = chat,
    String content = 'hello',
    bool bad = false,
  }) => {
    'id': id,
    'senderId': peer,
    'recipientId': conversation,
    'recipientType': conversation == chat ? 0 : 1,
    'sentAt': DateTime.utc(2026, 10, 1).toIso8601String(),
    'encryptedContent': bad ? 'bad' : jsonEncode({'text': content}),
    'reactions': <Json>[],
    'reactionsVersion': 0,
  };
}
