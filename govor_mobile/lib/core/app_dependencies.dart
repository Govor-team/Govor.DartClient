import 'api_client.dart';
import 'user_profile_repository.dart';
import 'reaction_repository.dart';
import 'auth_service.dart';
import 'chat_hub.dart';
import 'encryption_service.dart';
import 'storage.dart';
import 'preferences_repository.dart';
import 'media/attachment_repository.dart';

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
  }) : createApi = api ?? ((uri, store) => ApiClient(uri, store)),
       createAuth = auth ?? AuthService.new,
       createEncryption = encryption ?? EncryptionService.new,
       createHub = hub ?? ((api, path) => ChatHub(api, path: path)),
       createAttachments = attachments ?? EncryptedAttachmentRepository.new,
       createReactions = reactions ?? ApiReactionRepository.new,
       createProfiles = profiles ?? ApiUserProfileRepository.new,
       preferences = preferences ?? LocalPreferencesRepository();
  final ApiClient Function(ServerAddress, SecretStore) createApi;
  final AuthService Function(ApiClient) createAuth;
  final EncryptionService Function(ApiClient) createEncryption;
  final ChatHub Function(ApiClient, String) createHub;
  final AttachmentRepository Function(ApiClient) createAttachments;
  final ReactionRepository Function(ApiClient) createReactions;
  final UserProfileRepository Function(ApiClient, ChatHub, String)
  createProfiles;
  final PreferencesRepository preferences;
}
