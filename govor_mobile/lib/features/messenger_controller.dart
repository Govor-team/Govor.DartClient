import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../core/api_client.dart';
import '../core/auth_service.dart';
import '../core/api_pagination.dart';
import '../core/chat_pins.dart';
import '../core/app_dependencies.dart';
import '../core/media/attachment_repository.dart';
import 'settings/settings_cubit.dart';
import 'settings/appearance_cubit.dart';
import '../core/app_info.dart';
import '../core/attachment_files.dart';
import '../core/chat_hub.dart';
import '../core/crypto/primitives.dart';
import '../core/encryption_service.dart';
import '../core/models.dart';
import '../core/group_invitation.dart';
import '../core/user_benefits.dart';
import '../core/user_benefits_repository.dart';
import '../core/user_profile_repository.dart';
import '../core/storage.dart';
import '../core/server_ip_provider.dart';
import '../core/wallpapers.dart';

part 'messenger_features.dart';

class PendingSend {
  const PendingSend(
    this.id,
    this.text,
    this.envelope,
    this.reply,
    this.attachments, [
    this.forwardedFrom,
  ]);
  final String id, text, envelope;
  final String? reply, forwardedFrom;
  final List<Json> attachments;
}

class MessengerController extends ChangeNotifier {
  MessengerController({
    SecretStore? store,
    AppDependencies? dependencies,
    this.serverProvider = const ServerIpProvider(),
    AppInfoService? appInfoService,
    WallpaperRepository? wallpaperRepository,
  }) : dependencies = dependencies ?? AppDependencies(),
       store = store ?? platformSecretStore(),
       appInfoService = appInfoService ?? AppInfoService(),
       wallpaperRepository = wallpaperRepository ?? WallpaperRepository() {
    _appearanceSubscription = appearance.stream.listen((_) => _notify());
    benefits.addListener(_notify);
  }
  final AppDependencies dependencies;
  late final settings = SettingsCubit(dependencies.preferences);
  late final appearance = AppearanceCubit(wallpaperRepository);
  late final StreamSubscription<WallpaperSettings> _appearanceSubscription;
  AttachmentRepository? media;
  final SecretStore store;
  final ServerIpProvider serverProvider;
  final AppInfoService appInfoService;
  final WallpaperRepository wallpaperRepository;
  AppInfo? appInfo;
  String get versionLabel => appInfo == null
      ? 'Govor Flutter'
      : 'Govor Flutter • ${appInfo!.displayVersion}';
  Future<void> loadAppInfo() async {
    try {
      appInfo = await appInfoService.load();
    } catch (_) {
      /* Package metadata must not prevent sign-in. */
    }
    _notify();
  }

  ApiClient? api;
  EncryptionService? encryption;
  ChatHub? hub, friendsHub, presenceHub, profileHub;
  bool booting = true,
      busy = false,
      ready = false,
      demo = false,
      needsRecovery = false,
      loadingMessages = false,
      sending = false,
      hasOlder = true,
      uploading = false;
  String? error;
  bool legacyMigrationRequired = false;
  Person? me;
  final benefits = UserBenefitsCache();
  final _visibleBenefits = <String, int>{};
  final _benefitsLoading = <String>{};
  final _people = <String, Future<Person>>{};
  String? profileDescriptionDraft;
  Conversation? selected;
  List<Conversation> conversations = [];
  List<Person> friends = [];
  List<Json> requests = [];
  List<Json> outgoingRequests = [];
  final Map<String, Uint8List> avatarBytes = {};
  final Set<String> _avatarDownloads = {};
  final Map<String, Json> reactionStates = {};
  final channelPolicyVersions = <String, int>{};
  final Set<String> _reacting = {};
  final Map<String, Future<Json>> _reactionDefinitions = {};
  final Map<String, Future<Uint8List>> _reactionImages = {};
  int replyRevision = 0;
  List<ChatMessage> messages = [];
  final Map<String, List<ChatMessage>> _cache = {};
  final Map<String, PendingSend> _pending = {};
  final Map<String, String> drafts = {};
  final Map<String, int> unread = {};
  final _activity = <String, DateTime>{};
  final _legacyActivity = <String>{};
  final _activityChanges = <String, int>{};
  int _activityVersion = 0;
  final _pinned = <String>{};
  Future<void> _pinWrites = Future.value();
  String? historyAnchorId;
  bool hasNewer = false;
  final _autoReadBoundary = <String, (DateTime, String)>{};
  final _reading = <String>{};
  final _readChanges = <String, int>{};
  int _readVersion = 0;

  bool isPinned(Conversation chat) => _pinned.contains(chat.key);
  String get _pinScope => '${api!.server.scope}/$userId';

  List<Conversation> get orderedConversations =>
      [...conversations]..sort((a, b) {
        final pinned = (isPinned(b) ? 1 : 0).compareTo(isPinned(a) ? 1 : 0);
        if (pinned != 0) return pinned;
        final date = (_activity[b.key]?.millisecondsSinceEpoch ?? -1).compareTo(
          _activity[a.key]?.millisecondsSinceEpoch ?? -1,
        );
        if (date != 0) return date;
        final title = a.title.toLowerCase().compareTo(b.title.toLowerCase());
        return title != 0 ? title : a.key.compareTo(b.key);
      });

  Future<void> togglePin(Conversation chat) {
    final generation = _generation;
    final task = _pinWrites.then((_) async {
      if (generation != _generation ||
          !conversations.any((c) => c.key == chat.key)) {
        return;
      }
      final pins = {..._pinned};
      if (!pins.remove(chat.key)) {
        if (pins.length >= ChatPinsRepository.maxPins) {
          throw const ApiFailure(0, 'Достигнут лимит закреплённых чатов.');
        }
        pins.add(chat.key);
      }
      if (!demo) await dependencies.chatPins.save(_pinScope, pins);
      if (generation != _generation) return;
      _pinned
        ..clear()
        ..addAll(pins);
      _notify();
    });
    _pinWrites = task.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return task;
  }

  void _setActivity(String key, DateTime? date, {bool newestOnly = false}) {
    if (date == null) {
      if (!newestOnly) _activity.remove(key);
    } else if (!newestOnly || _activity[key]?.isAfter(date) != true) {
      _activity[key] = date;
    }
  }

  void _recordActivity(String key, DateTime date) {
    _activityChanges[key] = ++_activityVersion;
    _setActivity(key, date, newestOnly: true);
  }

  void _clearChatPreferences() {
    historyAnchorId = null;
    hasNewer = false;
    _activity.clear();
    _activityChanges.clear();
    _legacyActivity.clear();
    _pinned.clear();
    _autoReadBoundary.clear();
    _reading.clear();
    _readChanges.clear();
  }

  final Map<String, List<Json>> attachments = {};
  List<Json> get selectedAttachments =>
      selected == null ? [] : attachments[selected!.key] ?? [];
  ConnectionStatus connection = ConnectionStatus.offline;
  Timer? _events;
  int _generation = 0, _selection = 0;
  int get sessionRevision => _generation;
  bool _disposed = false, _refreshing = false, _refreshAgain = false;
  String get lastServer => serverProvider.address;
  String? get wallpaper => appearance.state.selected;
  bool get darkTheme => appearance.state.dark;
  List<CustomWallpaper> get customWallpapers => appearance.state.custom;
  Uint8List? get customWallpaperBytes {
    for (final item in customWallpapers) {
      if (item.id == wallpaper) return item.bytes;
    }
    return null;
  }

  static const wallpapers = AppearanceCubit.wallpapers;
  Future<void> setAppearance({
    String? background,
    bool? dark,
    bool useGradient = false,
  }) => appearance.update(
    background: background,
    dark: dark,
    useGradient: useGradient,
  );
  Future<void> loadAppearance() => appearance.load();

  Future<void> importWallpaper() async {
    final picked = await pickAttachment(
      maxBytes: WallpaperRepository.maxBytes,
      title: 'Выбрать фон — PNG, JPEG или WebP',
    );
    if (picked != null) await addWallpaper(picked.data, picked.name);
  }

  Future<void> addWallpaper(Uint8List data, String name) =>
      appearance.add(data, name);
  Future<void> removeWallpaper(String id) => appearance.remove(id);

  bool get hasSession => api?.tokens != null;
  String? get sessionId => api?.tokens?.session;
  String? get recoveryCode => encryption?.recoveryCode;
  String? get accountFingerprint {
    final identity = encryption?.ownDevice?.accountIdentity;
    return identity == null
        ? null
        : hex(sha256(utf('govor-account-v1\n$identity')));
  }

  Future<void> changePassword(String current, String replacement) =>
      encryption!.changePassword(current, replacement);
  Future<void> resetEncryption(String password) async {
    await encryption!.resetEncryption(password);
    await encryption!.initialize();
    media?.clear();
    _cache.clear();
    closeChat();
    await refresh();
  }

  String get userId => me?.id ?? '';
  PendingSend? get pending => selected == null ? null : _pending[selected!.key];
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void clearError() {
    error = null;
    _notify();
  }

  String safeError(Object e) =>
      e is ApiFailure || e is CryptoFailure || e is RecoveryCodeRequired
      ? e.toString()
      : 'Не удалось выполнить действие. Проверьте соединение и повторите попытку.';

  Future<void> boot() async {
    await settings.load();
    await loadAppInfo();
    try {
      try {
        await loadAppearance();
      } catch (_) {
        // Appearance storage may be unavailable in private browser sessions.
      }
      final legacyAppearance = await store.read('govor-appearance');
      if (legacyAppearance != null) {
        final data = object(jsonDecode(legacyAppearance));
        await appearance.migrate(data);
        await store.remove('govor-appearance');
      }
      if (lastServer.isNotEmpty) {
        api = dependencies.createApi(serverProvider.server, store);
        await api!.restore();
        if (api!.tokens != null) {
          encryption = dependencies.createEncryption(api!);
          await _activate();
        }
      }
    } catch (e) {
      if (e is RecoveryCodeRequired) needsRecovery = true;
      error = safeError(e);
    } finally {
      booting = false;
      _notify();
    }
  }

  Future<void> signIn(
    String name,
    String password, {
    String? invitation,
  }) async {
    if (busy) return;
    busy = true;
    error = null;
    legacyMigrationRequired = false;
    _notify();
    try {
      final address = serverProvider.server;
      await _disconnect();
      api?.close();
      api = dependencies.createApi(address, store);
      demo = false;
      final auth = dependencies.createAuth(api!);
      if (invitation == null) {
        await auth.login(name, password);
      } else {
        await auth.register(name, password, invitation);
      }
      encryption = dependencies.createEncryption(api!);
      await _activate();
    } catch (e) {
      if (e is LegacyAccountMigrationRequired) {
        legacyMigrationRequired = true;
      } else {
        if (e is RecoveryCodeRequired) needsRecovery = true;
        error = safeError(e);
      }
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> migrateLegacyAccount(
    String name,
    String oldPassword,
    String newPassword,
  ) async {
    if (busy || api == null) return;
    busy = true;
    legacyMigrationRequired = false;
    error = null;
    _notify();
    try {
      final auth = dependencies.createAuth(api!);
      await auth.migrateLegacyAccount(name, oldPassword, newPassword);
      encryption = dependencies.createEncryption(api!);
      await _activate();
    } catch (e) {
      if (e is RecoveryCodeRequired) needsRecovery = true;
      error = safeError(e);
    } finally {
      busy = false;
      _notify();
    }
  }

  void dismissLegacyMigration() {
    legacyMigrationRequired = false;
    _notify();
  }

  Future<void> recover(String code) async {
    if (busy) return;
    busy = true;
    error = null;
    _notify();
    try {
      await encryption!.initialize(recoveryCode: code);
      needsRecovery = false;
      await _activate();
    } catch (e) {
      error = safeError(e);
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> retryActivation() async {
    if (busy || api?.tokens == null) return;
    busy = true;
    error = null;
    _notify();
    try {
      await _activate();
    } catch (e) {
      if (e is RecoveryCodeRequired) needsRecovery = true;
      error = safeError(e);
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> _activate() async {
    final generation = ++_generation;
    media?.clear();
    media = dependencies.createAttachments(api!);
    await encryption!.initialize();
    me = Person.fromJson(
      object(await api!.request('GET', '/api/profile/download/me')),
    );
    requireCrypto(
      me!.id == api!.tokens!.user,
      'Профиль не совпадает с сессией.',
    );
    if (generation != _generation) return;
    _clearChatPreferences();
    try {
      final pins = await dependencies.chatPins.load(_pinScope);
      if (generation != _generation) return;
      _pinned.addAll(pins);
    } catch (_) {
      // Local pins must not prevent sign-in.
    }
    if (generation != _generation) return;
    await _disconnect();
    if (generation != _generation) return;
    hub = dependencies.createHub(api!, '/hubs/chats')
      ..onStatus = (status) {
        if (generation == _generation) {
          connection = status;
          _notify();
        }
      }
      ..onEvent = (event, args) {
        if (generation == _generation) _onEvent(event, args);
      }
      ..onReconnected = refresh;
    friendsHub = dependencies.createHub(api!, '/hubs/friends')
      ..onEvent = (_, _) {
        _queueRefresh();
      }
      ..onReconnected = refresh;
    presenceHub = dependencies.createHub(api!, '/hubs/presence')
      ..onEvent = (_, _) {
        _queueRefresh();
      }
      ..onReconnected = refresh;
    profileHub = dependencies.createHub(api!, '/hubs/profiles')
      ..onEvent = (event, args) {
        if (generation != _generation) return;
        if (event == 'UserBenefitsUpdated' &&
            args.isNotEmpty &&
            args.first is Map) {
          final payload = object(args.first);
          final id = payload['userId'] as String;
          if (id != userId &&
              !_visibleBenefits.containsKey(id) &&
              benefits[id] == null) {
            return;
          }
          benefits.apply(
            id,
            UserBenefits.fromJson(object(payload['benefits'])),
          );
        } else {
          _queueRefresh();
        }
      }
      ..onReconnected = () async {
        await refresh();
        await refreshVisibleBenefits();
      };
    // Attach handlers first, connect, then fetch snapshots to close the subscription race.
    await Future.wait([
      for (final h in [hub!, friendsHub!, presenceHub!, profileHub!])
        h.start().catchError((Object _) {}),
    ]);
    if (generation != _generation) return;
    await _loadConversations();
    ready = true;
    needsRecovery = false;
    _notify();
  }

  Future<void> _loadConversations({bool reconcileActivity = true}) async {
    if (demo) return;
    final generation = _generation;
    final response = await Future.wait([
      api!.request('GET', '/api/friends'),
      api!.request('GET', '/api/user/private-chats'),
      loadApiPages(api!, '/api/groups/mine'),
      api!.request('GET', '/api/friends/requests'),
      api!.request('GET', '/api/friends/responses'),
      api!.request('GET', '/api/profile/download/me'),
    ]);
    if (generation != _generation) return;
    friends = objects(response[0]).map(Person.fromJson).toList();
    for (final p in friends) {
      benefits.apply(p.id, p.benefits);
    }
    requests = objects(response[3]);
    outgoingRequests = objects(response[4]);
    me = Person.fromJson(object(response[5]));
    benefits.apply(me!.id, me!.benefits);
    final users = {for (final f in friends) f.id: f};
    conversations = [
      for (final c in objects(response[1]))
        Conversation(
          id: c['chatId'] as String,
          peerId: c['friendId'] as String,
          title: users[c['friendId']]?.name ?? 'Собеседник',
          subtitle: 'Личная переписка',
          canPost: ![...requests, ...outgoingRequests].any(
            (r) =>
                r['status'] == 3 &&
                (r['requesterId'] == c['friendId'] ||
                    r['addresseeId'] == c['friendId']),
          ),
          online: users[c['friendId']]?.online ?? false,
          iconId: users[c['friendId']]?.iconId,
        ),
      for (final g in objects(response[2]))
        Conversation(
          id: g['id'] as String,
          title: g['name'] as String,
          type: 1,
          subtitle: g['description'] as String? ?? '',
          isChannel: g['isChannel'] == true,
          canPost: g['isChannel'] != true || [1, 2].contains(g['myRole']),
          role: g['myRole'] as int?,
          iconId: g['imageId'] as String?,
          canLeave: g['canLeave'] == true,
        ),
    ];
    for (final id in [
      me?.iconId,
      ...friends.map((f) => f.iconId),
      ...conversations.map((g) => g.iconId),
    ]) {
      if (validId(id)) unawaited(loadAvatar(id!));
    }
    // Bound concurrent requests; unread counts are authoritative HTTP snapshots.
    for (var i = 0; i < conversations.length; i += 8) {
      await Future.wait(
        conversations.skip(i).take(8).map((c) async {
          final activityVersion = _activityChanges[c.key];
          final readVersion = _readChanges[c.key];
          try {
            final value = object(
              await api!.request(
                'GET',
                '/api/chats/${c.id}/unread-count',
                query: {
                  'recipientType': '${c.type}',
                  'includeActivity': 'true',
                },
              ),
            );
            if (generation != _generation) return;
            if (_readChanges[c.key] == readVersion &&
                value['unreadCount'] is int) {
              unread[c.key] = value['unreadCount'] as int;
            }
            DateTime? date;
            if (value.containsKey('lastMessageAt')) {
              date = DateTime.tryParse(value['lastMessageAt'] as String? ?? '');
            } else if (reconcileActivity || !_legacyActivity.contains(c.key)) {
              // Compatibility with servers that don't return activity metadata.
              final route = c.type == 0
                  ? '/api/user/${c.id}/messages'
                  : '/api/groups/${c.id}/messages';
              final tail = objects(
                await api!.request(
                  'GET',
                  route,
                  query: {'Before': '1', 'After': '0'},
                ),
              );
              if (generation != _generation) return;
              final item = tail.lastOrNull;
              if (item != null &&
                  (item['recipientId'] != c.id ||
                      item['recipientType'] != c.type)) {
                return;
              }
              date = DateTime.tryParse(item?['sentAt'] as String? ?? '');
              _legacyActivity.add(c.key);
            } else {
              return;
            }
            if (_activityChanges[c.key] == activityVersion) {
              _setActivity(c.key, date);
            }
          } catch (_) {
            // A single missing or inaccessible chat cannot break the list.
          }
        }),
      );
    }
    if (generation != _generation) return;
    if (selected != null) {
      final matches = conversations.where((c) => c.key == selected!.key);
      if (matches.isEmpty) {
        selected = null;
        messages = [];
        _selection++;
      } else {
        selected = matches.first;
      }
    }
    _notify();
  }

  String preview(Conversation chat) {
    final cached = _cache[chat.key];
    if (cached != null && cached.isNotEmpty) {
      return cached.last.text ?? 'Зашифрованное сообщение';
    }
    return chat.subtitle.isEmpty ? 'Открыть переписку' : chat.subtitle;
  }

  void _onEvent(String event, List<dynamic> args) {
    if (args.isNotEmpty && args.first is Map) {
      final payload = object(args.first);
      if (event == 'ChannelReactionPolicyChanged') {
        final id = payload['groupId'] as String;
        final version = payload['version'] as int;
        if (version > (channelPolicyVersions[id] ?? -1)) {
          channelPolicyVersions[id] = version;
          _notify();
        }
        return;
      }
      if (event == 'MessageReactionsChanged') {
        applyReactions(payload);
        return;
      }
      if (event == 'ChatRead' && payload['readerId'] == userId) {
        final key = '${payload['recipientType']}/${payload['chatId']}';
        final count = payload['unreadCount'];
        if (!_reading.contains(key) && count is int) {
          _readChanges[key] = ++_readVersion;
          unread[key] = count;
          _notify();
        }
        return;
      }
      if (event == 'MessageRemoved') {
        final key = '${payload['recipientType']}/${payload['recipientId']}';
        _legacyActivity.remove(key);
        _activityChanges[key] = ++_activityVersion;
        replyRevision++;
        final id = payload['messageId'];
        for (final key in _cache.keys.toList()) {
          _cache[key] = _cache[key]!.where((m) => m.id != id).toList();
        }
        messages = messages.where((m) => m.id != id).toList();
        _notify();
      }
      if (event == 'ReceiveMessage' || event == 'MessageSent') {
        final key = '${payload['recipientType']}/${payload['recipientId']}';
        final date = DateTime.tryParse(payload['sentAt'] as String? ?? '');
        if (date != null) {
          _recordActivity(key, date);
          _notify();
        }
        _acknowledge(key, payload['messageId'] as String);
      }
    }
    _queueRefresh();
  }

  void _queueRefresh() {
    _events?.cancel();
    _events = Timer(
      const Duration(milliseconds: 200),
      () => unawaited(refresh(reconcileActivity: false)),
    );
  }

  Future<void> refresh({bool reconcileActivity = true}) async {
    if (demo || !ready) return;
    if (_refreshing) {
      _refreshAgain = true;
      return;
    }
    _refreshing = true;
    final generation = _generation;
    try {
      do {
        _refreshAgain = false;
        await _loadConversations(reconcileActivity: reconcileActivity);
        if (generation != _generation) return;
        if (selected != null && !hasNewer && !loadingMessages) {
          await _loadMessages(selected!, fresh: true);
        }
      } while (_refreshAgain && generation == _generation);
    } catch (e) {
      if (generation == _generation) {
        error = safeError(e);
        _notify();
      }
    } finally {
      _refreshing = false;
    }
  }

  Future<void> open(Conversation chat) async {
    selected = chat;
    _autoReadBoundary.remove(chat.key);
    final selection = ++_selection, generation = _generation;
    historyAnchorId = null;
    hasNewer = false;
    error = null;
    loadingMessages = !demo;
    messages = demo ? _cache[chat.key] ?? [] : [];
    hasOlder = true;
    _notify();
    if (demo) return;
    try {
      String? anchor;
      var anchorWasRead = false;
      var inferPosition = false;
      if ((unread[chat.key] ?? 0) > 0) {
        try {
          final activity = object(
            await api!.request(
              'GET',
              '/api/chats/${chat.id}/unread-count',
              query: {
                'recipientType': '${chat.type}',
                'includeActivity': 'true',
                'includeReadPosition': 'true',
              },
            ),
          );
          if (generation != _generation || selection != _selection) return;
          final count = activity['unreadCount'];
          if (count is int) unread[chat.key] = count;
          if ((unread[chat.key] ?? 0) > 0) {
            final lastRead = activity['lastReadMessageId'];
            final firstUnread = activity['firstUnreadMessageId'];
            if (validId(lastRead)) {
              anchor = lastRead as String;
              anchorWasRead = true;
            } else if (validId(firstUnread)) {
              anchor = firstUnread as String;
            } else {
              inferPosition = true;
            }
          }
        } catch (_) {
          inferPosition = true;
        }
      }
      if (generation != _generation || selection != _selection) return;
      await _loadMessages(
        chat,
        fresh: true,
        initial: true,
        anchor: anchor,
        anchorWasRead: anchorWasRead,
        inferPosition: inferPosition,
      );
    } catch (e) {
      if (generation == _generation && selection == _selection) {
        error = safeError(e);
        _notify();
      }
    }
  }

  void closeChat() {
    selected = null;
    messages = [];
    historyAnchorId = null;
    hasNewer = false;
    loadingMessages = false;
    _selection++;
    _notify();
  }

  Future<void> _loadMessages(
    Conversation chat, {
    required bool fresh,
    bool initial = false,
    String? anchor,
    bool anchorWasRead = false,
    bool inferPosition = false,
    bool newer = false,
  }) async {
    final selection = _selection, generation = _generation;
    final activityVersion = _activityChanges[chat.key];
    loadingMessages = true;
    _notify();
    try {
      final previous = _cache[chat.key] ?? [];
      final query = {
        'Before': newer ? '0' : '40',
        'After': anchor != null || newer ? '40' : '0',
      };
      if (anchor != null) {
        query['StartMessageId'] = anchor;
      } else if (!fresh && previous.isNotEmpty) {
        query['StartMessageId'] = newer ? previous.last.id : previous.first.id;
      }
      final route = chat.type == 0
          ? '/api/user/${chat.id}/messages'
          : '/api/groups/${chat.id}/messages';
      var raw = objects(await api!.request('GET', route, query: query));
      if (anchor != null && raw.isEmpty && generation == _generation) {
        // The anchor may have been deleted between the two requests.
        anchor = null;
        inferPosition = true;
        raw = objects(
          await api!.request(
            'GET',
            route,
            query: {'Before': '40', 'After': '0'},
          ),
        );
      }
      if (newer &&
          raw.isEmpty &&
          generation == _generation &&
          selection == _selection) {
        await _loadMessages(
          chat,
          fresh: true,
          initial: true,
          inferPosition: true,
        );
        return;
      }
      final decoded = <ChatMessage>[];
      for (final value in raw) {
        if (generation != _generation || selection != _selection) return;
        final m = ChatMessage.fromJson(value);
        applyHistoryReactions(value);
        requireCrypto(
          m.conversationId == chat.id && m.type == chat.type,
          'Сервер вернул сообщение из другого чата.',
        );
        try {
          decoded.add(await encryption!.decrypt(m));
        } catch (e) {
          decoded.add(m.rejected(safeError(e)));
        }
      }
      if (generation != _generation || selection != _selection) return;
      // A refreshed snapshot replaces the tail, including messages deleted while offline.
      final retained = initial
          ? const <ChatMessage>[]
          : fresh
          ? previous.where(
              (m) =>
                  decoded.isNotEmpty &&
                  (m.sentAt.isBefore(decoded.first.sentAt) ||
                      (m.sentAt == decoded.first.sentAt &&
                          m.id.compareTo(decoded.first.id) < 0)),
            )
          : previous;
      _cache[chat.key] = mergeMessages(retained, decoded);
      if (fresh &&
          anchor == null &&
          _activityChanges[chat.key] == activityVersion) {
        _setActivity(chat.key, decoded.lastOrNull?.sentAt);
      }
      for (final m in decoded) {
        _acknowledge(chat.key, m.id);
      }
      if (selection == _selection && selected?.key == chat.key) {
        messages = _cache[chat.key]!;
        if (initial) {
          final anchorIndex = anchor == null
              ? -1
              : decoded.indexWhere((m) => m.id == anchor);
          historyAnchorId = anchorIndex < 0 ? null : anchor;
          if (anchorIndex >= 0 && anchorWasRead) {
            final read = decoded[anchorIndex];
            _autoReadBoundary[chat.key] = (read.sentAt, read.id);
          }
          hasNewer = anchorIndex >= 0 && decoded.length - anchorIndex - 1 >= 40;
          hasOlder = anchorIndex < 0 ? raw.length >= 40 : anchorIndex >= 40;
          if (inferPosition && historyAnchorId == null) {
            final firstUnread = raw.indexWhere(
              (item) =>
                  item['senderId'] != userId &&
                  !(item['messageViews'] is List &&
                      (item['messageViews'] as List).any(
                        (v) => v is Map && v['userId'] == userId,
                      )),
            );
            if (firstUnread >= 0) {
              final marker = decoded[firstUnread == 0 ? 0 : firstUnread - 1];
              historyAnchorId = marker.id;
              if (firstUnread > 0) {
                _autoReadBoundary[chat.key] = (marker.sentAt, marker.id);
              }
            }
          }
        } else if (newer) {
          hasNewer =
              decoded.where((m) => m.id != previous.last.id).length >= 40;
        } else if (!fresh || previous.isEmpty) {
          hasOlder = fresh ? raw.length >= 40 : raw.length > 40;
        }
      }
    } finally {
      if (selection == _selection && generation == _generation) {
        loadingMessages = false;
        _notify();
      }
    }
  }

  void _acknowledge(String key, String messageId) {
    if (_pending[key]?.id != messageId) return;
    final pending = _pending.remove(key);
    if (pending?.forwardedFrom == null) {
      attachments.remove(key);
      drafts.remove(key);
    }
  }

  Future<void> loadOlder() async {
    if (selected == null || loadingMessages || !hasOlder || demo) return;
    try {
      await _loadMessages(selected!, fresh: false);
    } catch (e) {
      error = safeError(e);
      _notify();
    }
  }

  Future<void> loadNewer() async {
    final chat = selected;
    if (chat == null || loadingMessages || !hasNewer || demo) return;
    try {
      await _loadMessages(chat, fresh: false, newer: true);
    } catch (e) {
      if (selected?.key == chat.key) {
        error = safeError(e);
        _notify();
      }
    }
  }

  Future<bool> send(String text, {String? replyTo}) => _sendTo(
    selected,
    text,
    replyTo: replyTo,
    forwardedFrom: pending?.forwardedFrom,
  );

  Future<bool> _sendTo(
    Conversation? chat,
    String text, {
    String? replyTo,
    String? forwardedFrom,
    List<Json>? files,
  }) async {
    if (chat == null ||
        sending ||
        uploading ||
        (text.trim().isEmpty &&
            (files ?? attachments[chat.key] ?? <Json>[]).isEmpty &&
            _pending[chat.key] == null)) {
      return false;
    }
    if (!chat.canPost) {
      error = 'Публиковать в этом канале могут только администраторы.';
      _notify();
      return false;
    }
    sending = true;
    error = null;
    _notify();
    final generation = _generation;
    try {
      if (demo) {
        final m = ChatMessage(
          id: newId(),
          senderId: userId,
          conversationId: chat.id,
          type: chat.type,
          sentAt: DateTime.now().toUtc(),
          content: '',
          text: text.trim(),
          replyTo: replyTo,
          forwardedFromMessageId: forwardedFrom,
          attachments: files ?? const [],
        );
        _cache[chat.key] = mergeMessages(_cache[chat.key] ?? [], [m]);
        _recordActivity(chat.key, m.sentAt);
        if (selected?.key == chat.key) messages = _cache[chat.key]!;
        if (forwardedFrom == null) drafts.remove(chat.key);
        return true;
      }
      var pending = _pending[chat.key];
      final firstAttempt = pending == null;
      if (pending != null &&
          (pending.text != text.trim() ||
              pending.reply != replyTo ||
              pending.forwardedFrom != forwardedFrom)) {
        throw const ApiFailure(
          0,
          'Сначала повторите неподтверждённое сообщение или обновите историю.',
        );
      }
      if (pending == null) {
        final id = newId();
        final preparedFiles = List<Json>.of(
          files ?? attachments[chat.key] ?? [],
        );
        final envelope = await encryption!.encrypt(
          chat,
          text.trim(),
          id,
          replyTo: replyTo,
          attachments: preparedFiles,
        );
        if (generation != _generation) return false;
        pending = PendingSend(
          id,
          text.trim(),
          envelope,
          replyTo,
          preparedFiles,
          forwardedFrom,
        );
        _pending[chat.key] = pending;
      }
      final Json value;
      try {
        value = object(
          await hub!.invoke('Send', [
            {
              'recipientId': chat.id,
              'recipientType': chat.type,
              'encryptedContent': pending.envelope,
              'replyToMessageId': pending.reply,
              'forwardedFromMessageId': pending.forwardedFrom,
              'mediaAttachments': [
                for (final a in pending.attachments)
                  {'mediaId': field(a, 'mediaId'), 'encryptedKey': ''},
              ],
            },
          ]),
        );
      } on HubCommandFailure catch (failure) {
        // Only a known rejection of the first attempt lets us issue a new ID.
        // A previous attempt without a reply may still have been saved.
        if (failure.sendRejected &&
            firstAttempt &&
            generation == _generation &&
            identical(_pending[chat.key], pending)) {
          _pending.remove(chat.key);
        }
        rethrow;
      }
      if (generation != _generation) return false;
      final response = ChatMessage.fromJson(value);
      requireCrypto(
        response.id == pending.id &&
            response.conversationId == chat.id &&
            response.type == chat.type &&
            response.senderId == userId &&
            response.replyTo == pending.reply &&
            response.forwardedFromMessageId == pending.forwardedFrom,
        'Подтверждение относится к другому сообщению.',
      );
      final decoded = await encryption!.decrypt(response);
      if (generation != _generation) return false;
      final jumpToEnd = selected?.key == chat.key && hasNewer;
      if (!jumpToEnd) {
        _cache[chat.key] = mergeMessages(_cache[chat.key] ?? [], [decoded]);
      }
      _recordActivity(chat.key, decoded.sentAt);
      _pending.remove(chat.key);
      if (pending.forwardedFrom == null) {
        drafts.remove(chat.key);
        attachments.remove(chat.key);
      }
      if (jumpToEnd) {
        try {
          await _loadMessages(chat, fresh: true, initial: true);
        } catch (_) {
          // The send succeeded; keep the reading window if reloading fails.
        }
      } else if (selected?.key == chat.key) {
        messages = _cache[chat.key]!;
      }
      return true;
    } catch (e) {
      if (generation == _generation) error = safeError(e);
      return false;
    } finally {
      if (generation == _generation) {
        sending = false;
        _notify();
      }
    }
  }

  Future<void> attachFile() async {
    final chat = selected;
    if (chat == null || uploading || sending || demo || pending != null) return;
    if (selectedAttachments.length >= 10) {
      throw const ApiFailure(0, 'Можно прикрепить до 10 файлов за раз.');
    }
    final generation = _generation;
    uploading = true;
    _notify();
    try {
      final file = await pickAttachment();
      if (file == null) return;
      if (generation != _generation) return;
      final attachment = await media!.upload(file.data, file.name);
      if (generation != _generation) return;
      attachments.putIfAbsent(chat.key, () => []).add(attachment.toJson());
    } finally {
      if (generation == _generation) {
        uploading = false;
        _notify();
      }
    }
  }

  void removeAttachment(int index) {
    if (selected != null && !sending && pending == null) {
      attachments[selected!.key]?.removeAt(index);
      _notify();
    }
  }

  Future<void> downloadFile(Json attachment) async {
    if (demo) return;
    final generation = _generation;
    final plaintext = await media!.load(Attachment.fromJson(attachment));
    if (generation == _generation) {
      await saveAttachment(field(attachment, 'fileName') as String, plaintext);
    }
  }

  Future<void> edit(ChatMessage message, String text) async {
    final chat = selected;
    if (chat == null || message.senderId != userId || text.trim().isEmpty) {
      return;
    }
    if (demo) {
      final changed = ChatMessage(
        id: message.id,
        senderId: message.senderId,
        conversationId: message.conversationId,
        type: message.type,
        sentAt: message.sentAt,
        content: '',
        text: text.trim(),
        replyTo: message.replyTo,
        forwardedFromMessageId: message.forwardedFromMessageId,
        forwardedFromUserId: message.forwardedFromUserId,
        forwardedFromSentAt: message.forwardedFromSentAt,
        edited: true,
      );
      _cache[chat.key] = mergeMessages(_cache[chat.key] ?? [], [changed]);
      messages = _cache[chat.key]!;
      _notify();
      return;
    }
    final envelope = await encryption!.encrypt(
      chat,
      text.trim(),
      message.id,
      replyTo: message.replyTo,
      edit: true,
    );
    await hub!.invoke('Edit', [
      {'messageId': message.id, 'newEncryptedContent': envelope},
    ]);
    await refresh();
  }

  Future<void> remove(ChatMessage message) async {
    replyRevision++;
    if (demo) {
      messages = messages.where((m) => m.id != message.id).toList();
      _cache[selected!.key] = messages;
      _notify();
      return;
    }
    await hub!.invoke('Remove', [
      {'messageId': message.id, 'requestType': 1},
    ]);
    await refresh();
  }

  Future<void> markRead() async {
    final chat = selected;
    if (chat != null) await _markRead(chat, null);
  }

  Future<void> markVisibleHistoryRead(
    String chatKey,
    ChatMessage boundary,
  ) async {
    final chat = selected;
    if (chat == null ||
        chat.key != chatKey ||
        demo ||
        loadingMessages ||
        (unread[chatKey] ?? 0) <= 0 ||
        _reading.contains(chatKey) ||
        boundary.failure != null ||
        !messages.any((m) => m.id == boundary.id)) {
      return;
    }
    final previous = _autoReadBoundary[chatKey];
    if (previous != null &&
        (boundary.sentAt.isBefore(previous.$1) ||
            (boundary.sentAt == previous.$1 &&
                boundary.id.compareTo(previous.$2) <= 0))) {
      return;
    }
    _autoReadBoundary[chatKey] = (boundary.sentAt, boundary.id);
    try {
      await _markRead(chat, boundary.id);
    } catch (_) {
      // Background receipts should not interrupt a chat. Reopening retries.
    }
  }

  Future<void> _markRead(Conversation chat, String? boundary) async {
    if (!_reading.add(chat.key)) return;
    final generation = _generation;
    try {
      final result = demo
          ? null
          : await api!.request(
              'POST',
              '/api/chats/${chat.id}/read',
              body: {'recipientType': chat.type, 'upToMessageId': ?boundary},
            );
      if (generation != _generation) return;
      final count = result is Map ? result['unreadCount'] : null;
      _readChanges[chat.key] = ++_readVersion;
      if (count is int) {
        unread[chat.key] = count;
        if (count == 0 && boundary != null && selected?.key == chat.key) {
          historyAnchorId = null;
        }
      } else if (boundary == null) {
        unread[chat.key] = 0;
      }
    } finally {
      if (generation == _generation) {
        _reading.remove(chat.key);
        _notify();
      }
    }
  }

  Future<List<Person>> searchPeople(String query) async {
    if (query.trim().isEmpty) return [];
    if (demo) {
      return friends
          .where((f) => f.name.toLowerCase().contains(query.toLowerCase()))
          .toList();
    }
    if (validId(query.trim().toLowerCase())) {
      return [
        Person.fromJson(
          object(
            await api!.request(
              'GET',
              '/api/profile/download/${query.trim().toLowerCase()}',
            ),
          ),
        ),
      ];
    }
    return objects(
      await api!.request(
        'GET',
        '/api/friends/search',
        query: {'query': query.trim()},
      ),
    ).map(Person.fromJson).toList();
  }

  UserProfileRepository get profiles => demo
      ? DemoUserProfileRepository(
          snapshot: (id) async {
            final person = id == userId
                ? me!
                : friends.where((p) => p.id == id).firstOrNull ??
                      Person(
                        id: id,
                        name: 'Дмитрий',
                        description: '**Привет!** Рад знакомству.',
                      );
            final request = [...requests, ...outgoingRequests]
                .where((r) => r['requesterId'] == id || r['addresseeId'] == id)
                .firstOrNull;
            return UserProfileSnapshot(
              person: person,
              relationship: relationshipFor(
                userId,
                id,
                friends,
                requests,
                outgoingRequests,
              ),
              requestId: request?['id'] as String?,
              blockedByMe:
                  request?['status'] == 3 && request?['requesterId'] == userId,
            );
          },
          sendRequest: sendFriendRequest,
          respondRequest: (id, accept) => acceptRequest(id, accept: accept),
          remove: (id) async => demoFriendship(id, 2),
          setBlocked: (id, blocked) async =>
              demoFriendship(id, blocked ? 3 : 2),
        )
      : dependencies.createProfiles(api!, friendsHub!, userId);

  void demoFriendship(String id, int status) {
    friends = friends.where((p) => p.id != id).toList();
    outgoingRequests = [
      ...outgoingRequests.where((r) => r['addresseeId'] != id),
      {
        'id': newId(),
        'requesterId': userId,
        'addresseeId': id,
        'status': status,
      },
    ];
    requests = requests.where((r) => r['requesterId'] != id).toList();
    _notify();
  }

  Future<void> sendFriendRequest(String user) async {
    if (demo) {
      if (user == userId ||
          friends.any((p) => p.id == user) ||
          outgoingRequests.any(
            (r) => r['addresseeId'] == user && r['status'] != 2,
          )) {
        return;
      }
      outgoingRequests = [
        ...outgoingRequests.where((r) => r['addresseeId'] != user),
        {
          'id': newId(),
          'requesterId': userId,
          'addresseeId': user,
          'status': 0,
        },
      ];
      _notify();
      return;
    }
    await friendsHub!.invoke('SendRequest', [user]);
  }

  Future<void> acceptRequest(String id, {bool accept = true}) async {
    if (demo) {
      requests = requests.where((r) => r['id'] != id).toList();
      _notify();
      return;
    }
    await friendsHub!.invoke(accept ? 'AcceptRequest' : 'RejectRequest', [id]);
    await refresh();
  }

  Future<void> chatWith(Person friend) async {
    if (demo) {
      await open(conversations.firstWhere((c) => c.peerId == friend.id));
      return;
    }
    final id =
        await api!.request('GET', '/api/user/${friend.id}/private-chat')
            as String;
    await _loadConversations();
    await open(
      Conversation(
        id: id,
        peerId: friend.id,
        title: friend.name,
        online: friend.online,
        iconId: friend.iconId,
      ),
    );
  }

  Future<void> updateDescription(String description) async {
    final person = me;
    final generation = _generation;
    if (person == null) return;
    if (description.length > 500) {
      throw const ApiFailure(0, 'Описание длиннее 500 символов.');
    }
    if (!demo) await profileHub!.invoke('SetDescription', [description]);
    if (generation != _generation || me?.id != person.id) return;
    me = Person(
      id: me!.id,
      name: me!.name,
      description: description,
      iconId: me!.iconId,
      online: me!.online,
      benefits: benefits[me!.id] ?? me!.benefits,
    );
    _notify();
  }

  Future<void> syncKeys() async {
    if (demo) return;
    await encryption!.synchronize();
    await refresh();
  }

  Future<List<Json>> sessions() async =>
      demo ? [] : objects(await api!.request('GET', '/api/session/all'));
  Future<void> _disconnect() async {
    _events?.cancel();
    await Future.wait([
      if (hub != null) hub!.stop(),
      if (friendsHub != null) friendsHub!.stop(),
      if (presenceHub != null) presenceHub!.stop(),
      if (profileHub != null) profileHub!.stop(),
    ]);
  }

  Future<void> logout() async {
    if (busy) return;
    busy = true;
    error = null;
    _notify();
    try {
      if (!demo && api?.tokens != null) {
        await api!.request('DELETE', '/api/session/close');
      }
      await _clearLocal();
    } catch (e) {
      error =
          '${safeError(e)} Сессия не отозвана; повторите выход после восстановления связи.';
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> _clearLocal() async {
    media?.clear();
    media = null;
    _generation++;
    _selection++;
    await _disconnect();
    await api?.clearSession();
    api?.close();
    api = null;
    encryption = null;
    ready = false;
    sending = false;
    demo = false;
    needsRecovery = false;
    selected = null;
    me = null;
    profileDescriptionDraft = null;
    conversations = [];
    messages = [];
    friends = [];
    requests = [];
    unread.clear();
    _clearChatPreferences();
    _cache.clear();
    _pending.clear();
    drafts.clear();
    attachments.clear();
    avatarBytes.clear();
    _avatarDownloads.clear();
    benefits.clear();
    _visibleBenefits.clear();
    _benefitsLoading.clear();
    _people.clear();
    channelPolicyVersions.clear();
    reactionStates.clear();
    _reactionDefinitions.clear();
    _reactionImages.clear();
    _reacting.clear();
    outgoingRequests = [];
    connection = ConnectionStatus.offline;
  }

  void startDemo() {
    media?.clear();
    media = null;
    benefits.clear();
    _visibleBenefits.clear();
    _benefitsLoading.clear();
    _people.clear();
    channelPolicyVersions.clear();
    reactionStates.clear();
    _reactionDefinitions.clear();
    _reactionImages.clear();
    _reacting.clear();
    profileDescriptionDraft = null;
    if (appInfo == null) unawaited(loadAppInfo());
    _generation++;
    _selection++;
    sending = false;
    unawaited(_disconnect());
    api?.close();
    api = null;
    encryption = null;
    _cache.clear();
    _pending.clear();
    drafts.clear();
    attachments.clear();
    unread.clear();
    _clearChatPreferences();
    requests = [];
    demo = true;
    ready = true;
    booting = false;
    busy = false;
    error = null;
    me = const Person(
      id: 'demo-me',
      name: 'Артём',
      description: 'Пробуем новый Govor',
    );
    friends = const [
      Person(id: 'demo-friend', name: 'Анастасия', online: true),
      Person(id: 'demo-friend-2', name: 'Михаил'),
    ];
    conversations = const [
      Conversation(
        id: 'demo-chat',
        peerId: 'demo-friend',
        title: 'Анастасия',
        online: true,
        subtitle: 'Увидимся вечером ✨',
      ),
      Conversation(
        id: 'demo-group',
        title: 'Команда Govor',
        type: 1,
        subtitle: 'Место для хороших идей',
      ),
      Conversation(
        id: 'demo-friend-chat',
        peerId: 'demo-friend-2',
        title: 'Михаил',
        subtitle: 'Спасибо, посмотрю!',
      ),
      Conversation(
        id: 'demo-news',
        title: 'Новости Govor',
        type: 1,
        isChannel: true,
        canPost: false,
        subtitle: 'Новый взгляд на общение',
      ),
    ];
    final now = DateTime.now();
    ChatMessage m(String id, String sender, String text, int minutes) =>
        ChatMessage(
          id: id,
          senderId: sender,
          conversationId: 'demo-chat',
          type: 0,
          sentAt: now.subtract(Duration(minutes: minutes)),
          content: '',
          text: text,
        );
    _cache['0/demo-chat'] = [
      m('demo-1', 'demo-friend', 'Привет! Как тебе новый Govor?', 14),
      m(
        'demo-2',
        userId,
        'Теперь и на компьютере. Очень нравится, как свет проходит через панели.',
        12,
      ),
      m(
        'demo-3',
        'demo-friend',
        'Да, это стекло выглядит здорово ✨\nИ все сообщения остаются между нами.',
        10,
      ),
      m('demo-4', userId, 'Проверим на телефоне и в браузере?', 8),
      m('demo-5', 'demo-friend', 'Давай! Увидимся вечером.', 5),
    ];
    _cache['1/demo-group'] = [
      ChatMessage(
        id: 'demo-g1',
        senderId: 'demo-friend',
        conversationId: 'demo-group',
        type: 1,
        sentAt: now,
        content: '',
        text:
            'Добро пожаловать в экспериментальный Flutter-клиент Govor. Здесь можно обсудить идеи для всех платформ.',
      ),
    ];
    for (final entry in _cache.entries) {
      _setActivity(entry.key, entry.value.lastOrNull?.sentAt);
    }
    selected = null;
    messages = [];
    connection = ConnectionStatus.offline;
    _notify();
  }

  @override
  void dispose() {
    media?.clear();
    unawaited(settings.close());
    unawaited(_appearanceSubscription.cancel());
    unawaited(appearance.close());
    _disposed = true;
    _generation++;
    _events?.cancel();
    unawaited(_disconnect());
    api?.close();
    benefits.removeListener(_notify);
    benefits.dispose();
    super.dispose();
  }
}
