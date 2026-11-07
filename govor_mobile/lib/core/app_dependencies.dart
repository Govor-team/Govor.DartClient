import 'api_client.dart';
import 'user_profile_repository.dart';
import 'reaction_repository.dart';
import 'auth_service.dart';
import 'chat_hub.dart';
import 'encryption_service.dart';
import 'storage.dart';
import 'preferences_repository.dart';
import 'media/attachment_repository.dart';
import 'media/media_cache.dart';
import 'chat_pins.dart';

/// Composition root. All session services can be replaced without platform IO.
class AppDependencies {
  AppDependencies({
    ApiClient Function(ServerAddress, SecretStore)? api,
    AuthService Function(ApiClient)? auth,
    EncryptionService Function(ApiClient)? encryption,
    ChatHub Function(ApiClient, String)? hub,
    AttachmentRepository Function(ApiClient)? attachments,
    ReactionRepository Function(ApiClient)? reactions,
    UserProfileRepository Function(ApiClient, ChatHub, String)? profiles,
    PreferencesRepository? preferences,
    MediaCache? mediaCache,
    ChatPinsRepository? chatPins,
  }) : createApi = api ?? ((uri, store) => ApiClient(uri, store)),
       createAuth = auth ?? AuthService.new,
       createEncryption = encryption ?? EncryptionService.new,
       createHub = hub ?? ((api, path) => ChatHub(api, path: path)),
       _createAttachments = attachments,
       _mediaCache = mediaCache,
       chatPins = chatPins ?? ChatPinsRepository(),
       createReactions = reactions ?? ApiReactionRepository.new,
       createProfiles = profiles ?? ApiUserProfileRepository.new,
       preferences = preferences ?? LocalPreferencesRepository();
  final ApiClient Function(ServerAddress, SecretStore) createApi;
  final AuthService Function(ApiClient) createAuth;
  final EncryptionService Function(ApiClient) createEncryption;
  final ChatHub Function(ApiClient, String) createHub;
  final AttachmentRepository Function(ApiClient)? _createAttachments;
  final MediaCache? _mediaCache;
  final ChatPinsRepository chatPins;

  late final MediaCache mediaCache = _mediaCache ?? _defaultMediaCache();
  MediaCache _defaultMediaCache() {
    final prefs = preferences;
    final mediaPrefs = prefs is MediaPreferencesRepository
        ? prefs as MediaPreferencesRepository
        : null;
    return MediaCache(
      loadLimit: mediaPrefs?.loadMediaCacheLimit,
      saveLimit: mediaPrefs?.saveMediaCacheLimit,
    );
  }

  AttachmentRepository createAttachments(ApiClient api) =>
      _createAttachments?.call(api) ??
      EncryptedAttachmentRepository(api, disk: mediaCache);
  final ReactionRepository Function(ApiClient) createReactions;
  final UserProfileRepository Function(ApiClient, ChatHub, String)
  createProfiles;
  final PreferencesRepository preferences;
}
