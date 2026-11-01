import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ru.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ru'),
  ];

  /// Govor interface: Retry download
  ///
  /// In ru, this message translates to:
  /// **'Повторить загрузку'**
  String get retryDownload;

  /// Govor interface: Close
  ///
  /// In ru, this message translates to:
  /// **'Закрыть'**
  String get close;

  /// Govor interface: Save
  ///
  /// In ru, this message translates to:
  /// **'Сохранить'**
  String get save;

  /// Govor interface: Could not save file
  ///
  /// In ru, this message translates to:
  /// **'Не удалось сохранить файл'**
  String get couldNotSaveFile;

  /// Govor interface: Previous file
  ///
  /// In ru, this message translates to:
  /// **'Предыдущий файл'**
  String get previousFile;

  /// Govor interface: Next file
  ///
  /// In ru, this message translates to:
  /// **'Следующий файл'**
  String get nextFile;

  /// Govor interface: Could not open video
  ///
  /// In ru, this message translates to:
  /// **'Не удалось открыть видео'**
  String get couldNotOpenVideo;

  /// Govor interface: Govor
  ///
  /// In ru, this message translates to:
  /// **'Говор'**
  String get govor;

  /// Govor interface: Restore your encrypted history
  ///
  /// In ru, this message translates to:
  /// **'Вернём вашу зашифрованную историю'**
  String get restoreYourEncryptedHistory;

  /// Govor interface: Closer together. On every screen.
  ///
  /// In ru, this message translates to:
  /// **'Ближе друг к другу. На любом экране.'**
  String get closerTogetherOnEveryScreen;

  /// Govor interface: Key recovery
  ///
  /// In ru, this message translates to:
  /// **'Восстановление ключей'**
  String get keyRecovery;

  /// Govor interface: Create account
  ///
  /// In ru, this message translates to:
  /// **'Создать аккаунт'**
  String get createAccount;

  /// Govor interface: Welcome back
  ///
  /// In ru, this message translates to:
  /// **'С возвращением'**
  String get welcomeBack;

  /// Govor interface: Enter the recovery code from a device that already has your history.
  ///
  /// In ru, this message translates to:
  /// **'Введите резервный код с устройства, на котором уже доступна история.'**
  String get enterTheRecoveryCodeFromADeviceThatAlready;

  /// Govor interface: An invitation is required to register.
  ///
  /// In ru, this message translates to:
  /// **'Для регистрации понадобится приглашение.'**
  String get anInvitationIsRequiredToRegister;

  /// Govor interface: Sign in to your Govor account.
  ///
  /// In ru, this message translates to:
  /// **'Войдите в свой аккаунт Govor.'**
  String get signInToYourGovorAccount;

  /// Govor interface: Recovery code
  ///
  /// In ru, this message translates to:
  /// **'Резервный код'**
  String get recoveryCode;

  /// Govor interface: Enter the complete recovery code
  ///
  /// In ru, this message translates to:
  /// **'Введите полный резервный код'**
  String get enterTheCompleteRecoveryCode;

  /// Govor interface: Name
  ///
  /// In ru, this message translates to:
  /// **'Имя'**
  String get name;

  /// Govor interface: Enter your name
  ///
  /// In ru, this message translates to:
  /// **'Введите имя'**
  String get enterYourName;

  /// Govor interface: Password
  ///
  /// In ru, this message translates to:
  /// **'Пароль'**
  String get password;

  /// Govor interface: Show password
  ///
  /// In ru, this message translates to:
  /// **'Показать пароль'**
  String get showPassword;

  /// Govor interface: Hide password
  ///
  /// In ru, this message translates to:
  /// **'Скрыть пароль'**
  String get hidePassword;

  /// Govor interface: Between 8 and 256 characters
  ///
  /// In ru, this message translates to:
  /// **'От 8 до 256 символов'**
  String get between8And256Characters;

  /// Govor interface: Repeat password
  ///
  /// In ru, this message translates to:
  /// **'Повторите пароль'**
  String get repeatPassword;

  /// Govor interface: Passwords do not match
  ///
  /// In ru, this message translates to:
  /// **'Пароли не совпадают'**
  String get passwordsDoNotMatch;

  /// Govor interface: Invitation code
  ///
  /// In ru, this message translates to:
  /// **'Код приглашения'**
  String get invitationCode;

  /// Govor interface: Restore history
  ///
  /// In ru, this message translates to:
  /// **'Восстановить историю'**
  String get restoreHistory;

  /// Govor interface: Register
  ///
  /// In ru, this message translates to:
  /// **'Зарегистрироваться'**
  String get register;

  /// Govor interface: Sign in
  ///
  /// In ru, this message translates to:
  /// **'Войти'**
  String get signIn;

  /// Govor interface: Already have an account? Sign in
  ///
  /// In ru, this message translates to:
  /// **'Уже есть аккаунт? Войти'**
  String get alreadyHaveAnAccountSignIn;

  /// Govor interface: No account? Register
  ///
  /// In ru, this message translates to:
  /// **'Нет аккаунта? Зарегистрироваться'**
  String get noAccountRegister;

  /// Govor interface: Reconnect session
  ///
  /// In ru, this message translates to:
  /// **'Повторить подключение сессии'**
  String get reconnectSession;

  /// Govor interface: Explore the demo
  ///
  /// In ru, this message translates to:
  /// **'Посмотреть демоверсию'**
  String get exploreTheDemo;

  /// Govor interface: End-to-end encryption • Experimental version
  ///
  /// In ru, this message translates to:
  /// **'Сквозное шифрование • Экспериментальная версия'**
  String get endToEndEncryptionExperimentalVersion;

  /// Govor interface: Incoming
  ///
  /// In ru, this message translates to:
  /// **'Входящие'**
  String get incoming;

  /// Govor interface: Pending
  ///
  /// In ru, this message translates to:
  /// **'Ожидание'**
  String get pending;

  /// Govor interface: Search
  ///
  /// In ru, this message translates to:
  /// **'Поиск'**
  String get search;

  /// Govor interface: Username or user ID
  ///
  /// In ru, this message translates to:
  /// **'Никнейм или ID пользователя'**
  String get usernameOrUserId;

  /// Govor interface: Paste ID from clipboard
  ///
  /// In ru, this message translates to:
  /// **'Вставить ID из буфера'**
  String get pasteIdFromClipboard;

  /// Govor interface: Find
  ///
  /// In ru, this message translates to:
  /// **'Найти'**
  String get find;

  /// Govor interface: Enter a friend's name to search
  ///
  /// In ru, this message translates to:
  /// **'Введите имя друга, чтобы начать поиск'**
  String get enterAFriendSNameToSearch;

  /// Govor interface: Nothing found
  ///
  /// In ru, this message translates to:
  /// **'Ничего не найдено'**
  String get nothingFound;

  /// Govor interface: No requests yet
  ///
  /// In ru, this message translates to:
  /// **'Заявок пока нет'**
  String get noRequestsYet;

  /// Govor interface: Open chat
  ///
  /// In ru, this message translates to:
  /// **'Открыть чат'**
  String get openChat;

  /// Govor interface: Add friend
  ///
  /// In ru, this message translates to:
  /// **'Добавить в друзья'**
  String get addFriend;

  /// Govor interface: Request sent.
  ///
  /// In ru, this message translates to:
  /// **'Заявка отправлена.'**
  String get requestSent;

  /// Govor interface: User
  ///
  /// In ru, this message translates to:
  /// **'Пользователь'**
  String get user;

  /// Govor interface: Accept
  ///
  /// In ru, this message translates to:
  /// **'Принять'**
  String get accept;

  /// Govor interface: Decline
  ///
  /// In ru, this message translates to:
  /// **'Отклонить'**
  String get decline;

  /// Govor interface: Request declined
  ///
  /// In ru, this message translates to:
  /// **'Заявка отклонена'**
  String get requestDeclined;

  /// Govor interface: Request unavailable
  ///
  /// In ru, this message translates to:
  /// **'Заявка недоступна'**
  String get requestUnavailable;

  /// Govor interface: Waiting for a reply
  ///
  /// In ru, this message translates to:
  /// **'Ожидаем ответа'**
  String get waitingForAReply;

  /// Govor interface: Contacts
  ///
  /// In ru, this message translates to:
  /// **'Контакты'**
  String get contacts;

  /// Govor interface: Back
  ///
  /// In ru, this message translates to:
  /// **'Назад'**
  String get back;

  /// Govor interface: Cancel
  ///
  /// In ru, this message translates to:
  /// **'Отмена'**
  String get cancel;

  /// Govor interface: Confirm
  ///
  /// In ru, this message translates to:
  /// **'Подтвердить'**
  String get confirm;

  /// Govor interface: Groups and channels
  ///
  /// In ru, this message translates to:
  /// **'Группы и каналы'**
  String get groupsAndChannels;

  /// Govor interface: Find a community
  ///
  /// In ru, this message translates to:
  /// **'Найти сообщество'**
  String get findACommunity;

  /// Govor interface: By invitation
  ///
  /// In ru, this message translates to:
  /// **'По приглашению'**
  String get byInvitation;

  /// Govor interface: Invitation link or code
  ///
  /// In ru, this message translates to:
  /// **'Ссылка или код приглашения'**
  String get invitationLinkOrCode;

  /// Govor interface: community
  ///
  /// In ru, this message translates to:
  /// **'сообщество'**
  String get community;

  /// Govor interface: You will be able to read community messages after joining.
  ///
  /// In ru, this message translates to:
  /// **'После вступления вам станут доступны сообщения сообщества.'**
  String get youWillBeAbleToReadCommunityMessagesAfter;

  /// Govor interface: Preview invitation
  ///
  /// In ru, this message translates to:
  /// **'Посмотреть приглашение'**
  String get previewInvitation;

  /// Govor interface: Create a group or channel
  ///
  /// In ru, this message translates to:
  /// **'Создать группу или канал'**
  String get createAGroupOrChannel;

  /// Govor interface: Channel
  ///
  /// In ru, this message translates to:
  /// **'Канал'**
  String get channel;

  /// Govor interface: Group
  ///
  /// In ru, this message translates to:
  /// **'Группа'**
  String get group;

  /// Govor interface: Join
  ///
  /// In ru, this message translates to:
  /// **'Вступить'**
  String get join;

  /// Govor interface: Open profile
  ///
  /// In ru, this message translates to:
  /// **'Открыть профиль'**
  String get openProfile;

  /// Govor interface: Create community
  ///
  /// In ru, this message translates to:
  /// **'Создать сообщество'**
  String get createCommunity;

  /// Govor interface: Edit profile
  ///
  /// In ru, this message translates to:
  /// **'Изменить профиль'**
  String get editProfile;

  /// Govor interface: Title
  ///
  /// In ru, this message translates to:
  /// **'Название'**
  String get title;

  /// Govor interface: Enter a title
  ///
  /// In ru, this message translates to:
  /// **'Введите название'**
  String get enterATitle;

  /// Govor interface: Description
  ///
  /// In ru, this message translates to:
  /// **'Описание'**
  String get description;

  /// Govor interface: Private
  ///
  /// In ru, this message translates to:
  /// **'Приватное'**
  String get private;

  /// Govor interface: Join by invitation
  ///
  /// In ru, this message translates to:
  /// **'Вступление по приглашению'**
  String get joinByInvitation;

  /// Govor interface: Only administrators can post
  ///
  /// In ru, this message translates to:
  /// **'Пишут только администраторы'**
  String get onlyAdministratorsCanPost;

  /// Govor interface: Community
  ///
  /// In ru, this message translates to:
  /// **'Сообщество'**
  String get communityLabel;

  /// Govor interface: Refresh
  ///
  /// In ru, this message translates to:
  /// **'Обновить'**
  String get refresh;

  /// Govor interface: Public
  ///
  /// In ru, this message translates to:
  /// **'Публичное'**
  String get public;

  /// Govor interface: Leave this community?
  ///
  /// In ru, this message translates to:
  /// **'Выйти из сообщества?'**
  String get leaveThisCommunity;

  /// Govor interface: You will lose access to its history and new messages.
  ///
  /// In ru, this message translates to:
  /// **'Доступ к истории и новым сообщениям будет закрыт.'**
  String get youWillLoseAccessToItsHistoryAndNew;

  /// Govor interface: Leave community
  ///
  /// In ru, this message translates to:
  /// **'Выйти из сообщества'**
  String get leaveCommunity;

  /// Govor interface: Invitations
  ///
  /// In ru, this message translates to:
  /// **'Приглашения'**
  String get invitations;

  /// Govor interface: Create a link for 7 days
  ///
  /// In ru, this message translates to:
  /// **'Создать ссылку на 7 дней'**
  String get createALinkFor7Days;

  /// Govor interface: Invitation
  ///
  /// In ru, this message translates to:
  /// **'Приглашение'**
  String get invitation;

  /// Govor interface: Allowed reactions
  ///
  /// In ru, this message translates to:
  /// **'Разрешённые реакции'**
  String get allowedReactions;

  /// Govor interface: Members
  ///
  /// In ru, this message translates to:
  /// **'Участники'**
  String get members;

  /// Govor interface: Banned
  ///
  /// In ru, this message translates to:
  /// **'Заблокированные'**
  String get banned;

  /// Govor interface: Owner
  ///
  /// In ru, this message translates to:
  /// **'Владелец'**
  String get owner;

  /// Govor interface: Administrator
  ///
  /// In ru, this message translates to:
  /// **'Администратор'**
  String get administrator;

  /// Govor interface: Member
  ///
  /// In ru, this message translates to:
  /// **'Участник'**
  String get member;

  /// Govor interface: Member actions
  ///
  /// In ru, this message translates to:
  /// **'Действия с участником'**
  String get memberActions;

  /// Govor interface: Apply this action?
  ///
  /// In ru, this message translates to:
  /// **'Применить действие?'**
  String get applyThisAction;

  /// Govor interface: Remove administrator
  ///
  /// In ru, this message translates to:
  /// **'Снять администратора'**
  String get removeAdministrator;

  /// Govor interface: Make administrator
  ///
  /// In ru, this message translates to:
  /// **'Назначить администратором'**
  String get makeAdministrator;

  /// Govor interface: Transfer ownership
  ///
  /// In ru, this message translates to:
  /// **'Передать владение'**
  String get transferOwnership;

  /// Govor interface: Unban
  ///
  /// In ru, this message translates to:
  /// **'Разблокировать'**
  String get unban;

  /// Govor interface: Ban
  ///
  /// In ru, this message translates to:
  /// **'Заблокировать'**
  String get ban;

  /// Govor interface: Channel reactions
  ///
  /// In ru, this message translates to:
  /// **'Реакции канала'**
  String get channelReactions;

  /// Govor interface: All
  ///
  /// In ru, this message translates to:
  /// **'Все'**
  String get all;

  /// Govor interface: None
  ///
  /// In ru, this message translates to:
  /// **'Никакие'**
  String get none;

  /// Govor interface: Selected
  ///
  /// In ru, this message translates to:
  /// **'Выбранные'**
  String get selected;

  /// Govor interface: Reply
  ///
  /// In ru, this message translates to:
  /// **'Ответить'**
  String get reply;

  /// Govor interface: Copy text
  ///
  /// In ru, this message translates to:
  /// **'Копировать текст'**
  String get copyText;

  /// Govor interface: Forward
  ///
  /// In ru, this message translates to:
  /// **'Переслать'**
  String get forward;

  /// Govor interface: Edit
  ///
  /// In ru, this message translates to:
  /// **'Редактировать'**
  String get edit;

  /// Govor interface: Select
  ///
  /// In ru, this message translates to:
  /// **'Выбрать'**
  String get select;

  /// Govor interface: Delete
  ///
  /// In ru, this message translates to:
  /// **'Удалить'**
  String get delete;

  /// Govor interface: All reactions
  ///
  /// In ru, this message translates to:
  /// **'Все реакции'**
  String get allReactions;

  /// Govor interface: Could not load reactions
  ///
  /// In ru, this message translates to:
  /// **'Не удалось загрузить реакции'**
  String get couldNotLoadReactions;

  /// Govor interface: Retry
  ///
  /// In ru, this message translates to:
  /// **'Повторить'**
  String get retry;

  /// Govor interface: Find emoji
  ///
  /// In ru, this message translates to:
  /// **'Найти эмодзи'**
  String get findEmoji;

  /// Govor interface: Demo • Messages stay in memory; no server connection
  ///
  /// In ru, this message translates to:
  /// **'Демоверсия • Сообщения остаются в памяти, сервер не подключён'**
  String get demoMessagesStayInMemoryNoServerConnection;

  /// Govor interface: Leave
  ///
  /// In ru, this message translates to:
  /// **'Выйти'**
  String get leave;

  /// Govor interface: Chats
  ///
  /// In ru, this message translates to:
  /// **'Чаты'**
  String get chats;

  /// Govor interface: Friends and requests
  ///
  /// In ru, this message translates to:
  /// **'Друзья и заявки'**
  String get friendsAndRequests;

  /// Govor interface: Settings
  ///
  /// In ru, this message translates to:
  /// **'Настройки'**
  String get settings;

  /// Govor interface: Profile
  ///
  /// In ru, this message translates to:
  /// **'Профиль'**
  String get profile;

  /// Govor interface: Search conversations
  ///
  /// In ru, this message translates to:
  /// **'Поиск разговоров'**
  String get searchConversations;

  /// Govor interface: Friends
  ///
  /// In ru, this message translates to:
  /// **'Друзья'**
  String get friends;

  /// Govor interface: Groups
  ///
  /// In ru, this message translates to:
  /// **'Группы'**
  String get groups;

  /// Govor interface: Find a conversation
  ///
  /// In ru, this message translates to:
  /// **'Найти разговор'**
  String get findAConversation;

  /// Govor interface: Clear search
  ///
  /// In ru, this message translates to:
  /// **'Очистить поиск'**
  String get clearSearch;

  /// Govor interface: Find or create
  ///
  /// In ru, this message translates to:
  /// **'Найти или создать'**
  String get findOrCreate;

  /// Govor interface: Refresh groups
  ///
  /// In ru, this message translates to:
  /// **'Обновить группы'**
  String get refreshGroups;

  /// Govor interface: Your conversations will appear here
  ///
  /// In ru, this message translates to:
  /// **'Здесь появятся ваши разговоры'**
  String get yourConversationsWillAppearHere;

  /// Govor interface: Find friends
  ///
  /// In ru, this message translates to:
  /// **'Найти друзей'**
  String get findFriends;

  /// Govor interface: Reconnecting…
  ///
  /// In ru, this message translates to:
  /// **'Восстанавливаем соединение…'**
  String get reconnecting;

  /// Govor interface: Connecting…
  ///
  /// In ru, this message translates to:
  /// **'Подключаемся…'**
  String get connecting;

  /// Govor interface: A good conversation starts here
  ///
  /// In ru, this message translates to:
  /// **'Хороший разговор\nначинается здесь'**
  String get aGoodConversationNstartsHere;

  /// Govor interface: Choose a chat to feel closer. Private stays private.
  ///
  /// In ru, this message translates to:
  /// **'Выберите чат, чтобы быть ближе.\nЛичное остаётся личным.'**
  String get chooseAChatToFeelCloserNprivateStaysPrivate;

  /// Govor interface: End-to-end encryption
  ///
  /// In ru, this message translates to:
  /// **'Сквозное шифрование'**
  String get endToEndEncryption;

  /// Govor interface: Back to chats
  ///
  /// In ru, this message translates to:
  /// **'Назад к чатам'**
  String get backToChats;

  /// Govor interface: Online
  ///
  /// In ru, this message translates to:
  /// **'В сети'**
  String get online;

  /// Govor interface: Private chat
  ///
  /// In ru, this message translates to:
  /// **'Личный чат'**
  String get privateChat;

  /// Govor interface: Copy selected
  ///
  /// In ru, this message translates to:
  /// **'Копировать выбранные'**
  String get copySelected;

  /// Govor interface: Forward selected
  ///
  /// In ru, this message translates to:
  /// **'Переслать выбранные'**
  String get forwardSelected;

  /// Govor interface: Clear selection
  ///
  /// In ru, this message translates to:
  /// **'Отменить выбор'**
  String get clearSelection;

  /// Govor interface: Search loaded history
  ///
  /// In ru, this message translates to:
  /// **'Поиск в загруженной истории'**
  String get searchLoadedHistory;

  /// Govor interface: Chat actions
  ///
  /// In ru, this message translates to:
  /// **'Действия с чатом'**
  String get chatActions;

  /// Govor interface: Mark as read
  ///
  /// In ru, this message translates to:
  /// **'Пометить как прочитано'**
  String get markAsRead;

  /// Govor interface: Refresh history
  ///
  /// In ru, this message translates to:
  /// **'Обновить историю'**
  String get refreshHistory;

  /// Govor interface: Search loaded messages
  ///
  /// In ru, this message translates to:
  /// **'Поиск в загруженных сообщениях'**
  String get searchLoadedMessages;

  /// Govor interface: Close search
  ///
  /// In ru, this message translates to:
  /// **'Закрыть поиск'**
  String get closeSearch;

  /// Govor interface: Opening history…
  ///
  /// In ru, this message translates to:
  /// **'Открываем историю…'**
  String get openingHistory;

  /// Govor interface: No messages found
  ///
  /// In ru, this message translates to:
  /// **'Сообщений не найдено'**
  String get noMessagesFound;

  /// Govor interface: Say hello 👋
  ///
  /// In ru, this message translates to:
  /// **'Скажите «Привет» 👋'**
  String get sayHello;

  /// Govor interface: Load earlier messages
  ///
  /// In ru, this message translates to:
  /// **'Загрузить предыдущие'**
  String get loadEarlierMessages;

  /// Govor interface: Message
  ///
  /// In ru, this message translates to:
  /// **'Сообщение'**
  String get message;

  /// Govor interface: Cancel reply
  ///
  /// In ru, this message translates to:
  /// **'Отменить ответ'**
  String get cancelReply;

  /// Govor interface: Connect to the server to attach files
  ///
  /// In ru, this message translates to:
  /// **'Вложения доступны при подключении к серверу'**
  String get connectToTheServerToAttachFiles;

  /// Govor interface: Attach a file (up to 19 MB)
  ///
  /// In ru, this message translates to:
  /// **'Прикрепить файл (до 19 МБ)'**
  String get attachAFileUpTo19Mb;

  /// Govor interface: Message…
  ///
  /// In ru, this message translates to:
  /// **'Сообщение…'**
  String get messageLabel;

  /// Govor interface: Send (Ctrl+Enter)
  ///
  /// In ru, this message translates to:
  /// **'Отправить (Ctrl+Enter)'**
  String get sendCtrlEnter;

  /// Govor interface: Only channel administrators can post
  ///
  /// In ru, this message translates to:
  /// **'Публикации доступны администраторам канала'**
  String get onlyChannelAdministratorsCanPost;

  /// Govor interface: Reply to a message
  ///
  /// In ru, this message translates to:
  /// **'Ответ на сообщение'**
  String get replyToAMessage;

  /// Govor interface: Could not verify or decrypt this message
  ///
  /// In ru, this message translates to:
  /// **'Не удалось проверить или расшифровать сообщение'**
  String get couldNotVerifyOrDecryptThisMessage;

  /// Govor interface: Encrypted message
  ///
  /// In ru, this message translates to:
  /// **'Зашифрованное сообщение'**
  String get encryptedMessage;

  /// Govor interface: Copy
  ///
  /// In ru, this message translates to:
  /// **'Копировать'**
  String get copy;

  /// Govor interface: Message actions
  ///
  /// In ru, this message translates to:
  /// **'Действия с сообщением'**
  String get messageActions;

  /// Govor interface: Edit message
  ///
  /// In ru, this message translates to:
  /// **'Редактировать сообщение'**
  String get editMessage;

  /// Govor interface: Delete message?
  ///
  /// In ru, this message translates to:
  /// **'Удалить сообщение?'**
  String get deleteMessage;

  /// Govor interface: The message will be deleted for all participants.
  ///
  /// In ru, this message translates to:
  /// **'Сообщение будет удалено у всех участников.'**
  String get theMessageWillBeDeletedForAllParticipants;

  /// Govor interface: Select text messages to forward.
  ///
  /// In ru, this message translates to:
  /// **'Для пересылки выберите текстовые сообщения.'**
  String get selectTextMessagesToForward;

  /// Govor interface: Forward to chat
  ///
  /// In ru, this message translates to:
  /// **'Переслать в чат'**
  String get forwardToChat;

  /// Govor interface: Change avatar
  ///
  /// In ru, this message translates to:
  /// **'Изменить аватар'**
  String get changeAvatar;

  /// Govor interface: Tell us about yourself
  ///
  /// In ru, this message translates to:
  /// **'Расскажите о себе'**
  String get tellUsAboutYourself;

  /// Govor interface: Saving…
  ///
  /// In ru, this message translates to:
  /// **'Сохраняем…'**
  String get saving;

  /// Govor interface: Your description is saved automatically
  ///
  /// In ru, this message translates to:
  /// **'Описание сохраняется автоматически'**
  String get yourDescriptionIsSavedAutomatically;

  /// Govor interface: Interface language
  ///
  /// In ru, this message translates to:
  /// **'Язык интерфейса'**
  String get interfaceLanguage;

  /// Govor interface: Русский
  ///
  /// In ru, this message translates to:
  /// **'Русский'**
  String get russianLanguage;

  /// Govor interface: System language
  ///
  /// In ru, this message translates to:
  /// **'Как в системе'**
  String get systemLanguage;

  /// Govor interface: Could not save language. Please try again.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось сохранить язык. Повторите попытку.'**
  String get couldNotSaveLanguagePleaseTryAgain;

  /// Govor interface: Appearance
  ///
  /// In ru, this message translates to:
  /// **'Оформление'**
  String get appearance;

  /// Govor interface: Background and theme
  ///
  /// In ru, this message translates to:
  /// **'Фон и тема'**
  String get backgroundAndTheme;

  /// Govor interface: Dark theme
  ///
  /// In ru, this message translates to:
  /// **'Тёмное оформление'**
  String get darkTheme;

  /// Govor interface: Active sessions
  ///
  /// In ru, this message translates to:
  /// **'Активные сессии'**
  String get activeSessions;

  /// Govor interface: Device
  ///
  /// In ru, this message translates to:
  /// **'Устройство'**
  String get device;

  /// Govor interface: Current session
  ///
  /// In ru, this message translates to:
  /// **'Текущая сессия'**
  String get currentSession;

  /// Govor interface: End session
  ///
  /// In ru, this message translates to:
  /// **'Завершить сессию'**
  String get endSession;

  /// Govor interface: End this session?
  ///
  /// In ru, this message translates to:
  /// **'Завершить сессию?'**
  String get endThisSession;

  /// Govor interface: This device will stop receiving new messages and push notifications.
  ///
  /// In ru, this message translates to:
  /// **'Устройство перестанет получать новые сообщения и push-уведомления.'**
  String get thisDeviceWillStopReceivingNewMessagesAndPush;

  /// Govor interface: Message security
  ///
  /// In ru, this message translates to:
  /// **'Защита переписки'**
  String get messageSecurity;

  /// Govor interface: E2EE, keys and history transfer
  ///
  /// In ru, this message translates to:
  /// **'E2EE, ключи и перенос истории'**
  String get e2eeKeysAndHistoryTransfer;

  /// Govor interface: Reaction packs
  ///
  /// In ru, this message translates to:
  /// **'Паки реакций'**
  String get reactionPacks;

  /// Govor interface: Emoji for your messages
  ///
  /// In ru, this message translates to:
  /// **'Эмодзи для ваших сообщений'**
  String get emojiForYourMessages;

  /// Govor interface: Account ID
  ///
  /// In ru, this message translates to:
  /// **'ID аккаунта'**
  String get accountId;

  /// Govor interface: Copy ID
  ///
  /// In ru, this message translates to:
  /// **'Копировать ID'**
  String get copyId;

  /// Govor interface: Sign out
  ///
  /// In ru, this message translates to:
  /// **'Выйти из аккаунта'**
  String get signOut;

  /// Govor interface: Your emoji for messages
  ///
  /// In ru, this message translates to:
  /// **'Ваши эмодзи для сообщений'**
  String get yourEmojiForMessages;

  /// Govor interface: My packs
  ///
  /// In ru, this message translates to:
  /// **'Мои паки'**
  String get myPacks;

  /// Govor interface: Catalog
  ///
  /// In ru, this message translates to:
  /// **'Каталог'**
  String get catalog;

  /// Govor interface: Find a pack
  ///
  /// In ru, this message translates to:
  /// **'Найти пак'**
  String get findAPack;

  /// Govor interface: Add by code
  ///
  /// In ru, this message translates to:
  /// **'Добавить по коду'**
  String get addByCode;

  /// Govor interface: Shared pack code
  ///
  /// In ru, this message translates to:
  /// **'Код общего пака'**
  String get sharedPackCode;

  /// Govor interface: Open
  ///
  /// In ru, this message translates to:
  /// **'Открыть'**
  String get open;

  /// Govor interface: Always available
  ///
  /// In ru, this message translates to:
  /// **'Всегда доступен'**
  String get alwaysAvailable;

  /// Govor interface: Installed
  ///
  /// In ru, this message translates to:
  /// **'Установлен'**
  String get installed;

  /// Govor interface: Copy pack code
  ///
  /// In ru, this message translates to:
  /// **'Копировать код пака'**
  String get copyPackCode;

  /// Govor interface: Remove from my packs
  ///
  /// In ru, this message translates to:
  /// **'Удалить из моих паков'**
  String get removeFromMyPacks;

  /// Govor interface: Install
  ///
  /// In ru, this message translates to:
  /// **'Установить'**
  String get install;

  /// Govor interface: End-to-end encryption · E2EE
  ///
  /// In ru, this message translates to:
  /// **'Сквозное шифрование · E2EE'**
  String get endToEndEncryptionE2Ee;

  /// Govor interface: Account key
  ///
  /// In ru, this message translates to:
  /// **'Ключ аккаунта'**
  String get accountKey;

  /// Govor interface: Compare the public fingerprint with your contact over a trusted channel.
  ///
  /// In ru, this message translates to:
  /// **'Сверьте публичный отпечаток с собеседником по доверенному каналу.'**
  String get compareThePublicFingerprintWithYourContactOverA;

  /// Govor interface: View fingerprint
  ///
  /// In ru, this message translates to:
  /// **'Посмотреть отпечаток'**
  String get viewFingerprint;

  /// Govor interface: History and devices
  ///
  /// In ru, this message translates to:
  /// **'История и устройства'**
  String get historyAndDevices;

  /// Govor interface: Signing in with your password usually restores history. A recovery code helps you recover access.
  ///
  /// In ru, this message translates to:
  /// **'Обычно история переносится при входе по паролю. Резервный код пригодится для восстановления доступа.'**
  String get signingInWithYourPasswordUsuallyRestoresHistoryA;

  /// Govor interface: History transfer / recovery code
  ///
  /// In ru, this message translates to:
  /// **'Перенос истории / резервный код'**
  String get historyTransferRecoveryCode;

  /// Govor interface: Sync history
  ///
  /// In ru, this message translates to:
  /// **'Синхронизировать историю'**
  String get syncHistory;

  /// Govor interface: Password changed; history preserved.
  ///
  /// In ru, this message translates to:
  /// **'Пароль изменён, история сохранена.'**
  String get passwordChangedHistoryPreserved;

  /// Govor interface: Change password
  ///
  /// In ru, this message translates to:
  /// **'Сменить пароль'**
  String get changePassword;

  /// Govor interface: Changing your password preserves history and ends other sessions.
  ///
  /// In ru, this message translates to:
  /// **'При смене пароля история сохраняется, остальные сессии завершаются.'**
  String get changingYourPasswordPreservesHistoryAndEndsOtherSessions;

  /// Govor interface: New keys
  ///
  /// In ru, this message translates to:
  /// **'Новые ключи'**
  String get newKeys;

  /// Govor interface: Use only if all recovery methods are lost. Old encrypted history will become unavailable on this device.
  ///
  /// In ru, this message translates to:
  /// **'Только если все способы восстановления потеряны. Старая зашифрованная история на этом устройстве станет недоступна.'**
  String get useOnlyIfAllRecoveryMethodsAreLostOld;

  /// Govor interface: Start with new keys?
  ///
  /// In ru, this message translates to:
  /// **'Начать с новыми ключами?'**
  String get startWithNewKeys;

  /// Govor interface: Old history cannot be restored. Other sessions will end. Save your recovery code if you still have it.
  ///
  /// In ru, this message translates to:
  /// **'Старая история не восстановится. Остальные сессии будут завершены. Сохраните резервный код, если он ещё доступен.'**
  String get oldHistoryCannotBeRestoredOtherSessionsWillEnd;

  /// Govor interface: New keys created. Save the new recovery code.
  ///
  /// In ru, this message translates to:
  /// **'Созданы новые ключи. Сохраните новый резервный код.'**
  String get newKeysCreatedSaveTheNewRecoveryCode;

  /// Govor interface: Start chatting with new keys
  ///
  /// In ru, this message translates to:
  /// **'Начать общение с новыми ключами'**
  String get startChattingWithNewKeys;

  /// Govor interface: Initial key trust and group membership rely on the server. This protocol does not provide forward secrecy or post-compromise security.
  ///
  /// In ru, this message translates to:
  /// **'Первая встреча с ключом и состав групп доверяют серверу. Протокол не предоставляет forward secrecy и post-compromise security.'**
  String get initialKeyTrustAndGroupMembershipRelyOnThe;

  /// Govor interface: Confirm your current password
  ///
  /// In ru, this message translates to:
  /// **'Подтвердите текущий пароль'**
  String get confirmYourCurrentPassword;

  /// Govor interface: Current password
  ///
  /// In ru, this message translates to:
  /// **'Текущий пароль'**
  String get currentPassword;

  /// Govor interface: Enter your current password
  ///
  /// In ru, this message translates to:
  /// **'Введите текущий пароль'**
  String get enterYourCurrentPassword;

  /// Govor interface: New password
  ///
  /// In ru, this message translates to:
  /// **'Новый пароль'**
  String get newPassword;

  /// Govor interface: Choose a different password
  ///
  /// In ru, this message translates to:
  /// **'Выберите другой пароль'**
  String get chooseADifferentPassword;

  /// Govor interface: Repeat new password
  ///
  /// In ru, this message translates to:
  /// **'Повторите новый пароль'**
  String get repeatNewPassword;

  /// Govor interface: Continue
  ///
  /// In ru, this message translates to:
  /// **'Продолжить'**
  String get continueAction;

  /// Govor interface: Tricolor
  ///
  /// In ru, this message translates to:
  /// **'Триколор'**
  String get tricolor;

  /// Govor interface: Journey
  ///
  /// In ru, this message translates to:
  /// **'Путешествие'**
  String get journey;

  /// Govor interface: Vedas
  ///
  /// In ru, this message translates to:
  /// **'Веды'**
  String get vedas;

  /// Govor interface: Rod
  ///
  /// In ru, this message translates to:
  /// **'Род'**
  String get rod;

  /// Govor interface: Aria
  ///
  /// In ru, this message translates to:
  /// **'Ария'**
  String get aria;

  /// Govor interface: Add a background
  ///
  /// In ru, this message translates to:
  /// **'Добавить свой фон'**
  String get addABackground;

  /// Govor interface: Custom background
  ///
  /// In ru, this message translates to:
  /// **'Свой фон'**
  String get customBackground;

  /// Govor interface: Choose appearance
  ///
  /// In ru, this message translates to:
  /// **'Выберите оформление'**
  String get chooseAppearance;

  /// No description provided for @validUsername.
  ///
  /// In ru, this message translates to:
  /// **'4–44 символа: кириллица и цифры, первая — буква'**
  String get validUsername;

  /// No description provided for @selectedCount.
  ///
  /// In ru, this message translates to:
  /// **'Выбрано: {count}'**
  String selectedCount(int count);

  /// No description provided for @sessionOpened.
  ///
  /// In ru, this message translates to:
  /// **'Открыта {date}'**
  String sessionOpened(String date);

  /// No description provided for @wallpaperName.
  ///
  /// In ru, this message translates to:
  /// **'Фон: {name}'**
  String wallpaperName(String name);

  /// No description provided for @deleteWallpaperName.
  ///
  /// In ru, this message translates to:
  /// **'Удалить фон {name}'**
  String deleteWallpaperName(String name);

  /// No description provided for @joinCommunityName.
  ///
  /// In ru, this message translates to:
  /// **'Вступить в {name}?'**
  String joinCommunityName(String name);

  /// No description provided for @editedTime.
  ///
  /// In ru, this message translates to:
  /// **'изменено • {time}'**
  String editedTime(String time);

  /// No description provided for @removeReaction.
  ///
  /// In ru, this message translates to:
  /// **'Убрать реакцию'**
  String get removeReaction;

  /// No description provided for @closeNotice.
  ///
  /// In ru, this message translates to:
  /// **'Закрыть уведомление'**
  String get closeNotice;

  /// No description provided for @invitationLength.
  ///
  /// In ru, this message translates to:
  /// **'Код из 32 символов'**
  String get invitationLength;

  /// No description provided for @gradient.
  ///
  /// In ru, this message translates to:
  /// **'Градиент'**
  String get gradient;

  /// No description provided for @openConversation.
  ///
  /// In ru, this message translates to:
  /// **'Открыть переписку'**
  String get openConversation;

  /// No description provided for @copyLink.
  ///
  /// In ru, this message translates to:
  /// **'Копировать ссылку'**
  String get copyLink;

  /// No description provided for @revokeInvitation.
  ///
  /// In ru, this message translates to:
  /// **'Отозвать приглашение'**
  String get revokeInvitation;

  /// No description provided for @pendingAcknowledgment.
  ///
  /// In ru, this message translates to:
  /// **'Нет подтверждения. Повтор использует прежний ID.'**
  String get pendingAcknowledgment;

  /// No description provided for @communitySummary.
  ///
  /// In ru, this message translates to:
  /// **'{count} участников • {kind}'**
  String communitySummary(int count, String kind);

  /// No description provided for @invitationUsed.
  ///
  /// In ru, this message translates to:
  /// **'Использовано: {count}'**
  String invitationUsed(int count);

  /// No description provided for @changeMemberRights.
  ///
  /// In ru, this message translates to:
  /// **'Изменить права пользователя {name}?'**
  String changeMemberRights(String name);

  /// No description provided for @couldNotOpenLink.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось открыть ссылку'**
  String get couldNotOpenLink;

  /// No description provided for @markdownImage.
  ///
  /// In ru, this message translates to:
  /// **'Изображение по ссылке'**
  String get markdownImage;

  /// No description provided for @offline.
  ///
  /// In ru, this message translates to:
  /// **'Не в сети'**
  String get offline;

  /// No description provided for @about.
  ///
  /// In ru, this message translates to:
  /// **'О себе'**
  String get about;

  /// No description provided for @sendFriendRequest.
  ///
  /// In ru, this message translates to:
  /// **'Отправить заявку в друзья'**
  String get sendFriendRequest;

  /// No description provided for @couldNotLoadProfile.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось обновить профиль. Повторите попытку.'**
  String get couldNotLoadProfile;

  /// No description provided for @couldNotOpenChat.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось открыть переписку'**
  String get couldNotOpenChat;

  /// No description provided for @preview.
  ///
  /// In ru, this message translates to:
  /// **'Предпросмотр'**
  String get preview;

  /// No description provided for @forwarded.
  ///
  /// In ru, this message translates to:
  /// **'[Переслано]'**
  String get forwarded;

  /// No description provided for @couldNotApplyReaction.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось изменить реакцию. Повторите выбор.'**
  String get couldNotApplyReaction;

  /// No description provided for @messageDeleted.
  ///
  /// In ru, this message translates to:
  /// **'Сообщение удалено'**
  String get messageDeleted;

  /// No description provided for @removeFriend.
  ///
  /// In ru, this message translates to:
  /// **'Удалить из друзей'**
  String get removeFriend;

  /// No description provided for @blockUser.
  ///
  /// In ru, this message translates to:
  /// **'Заблокировать'**
  String get blockUser;

  /// No description provided for @unblockUser.
  ///
  /// In ru, this message translates to:
  /// **'Разблокировать'**
  String get unblockUser;

  /// No description provided for @profileTag.
  ///
  /// In ru, this message translates to:
  /// **'Профильный тег'**
  String get profileTag;

  /// No description provided for @userPrivileges.
  ///
  /// In ru, this message translates to:
  /// **'Привилегии пользователя'**
  String get userPrivileges;

  /// No description provided for @resetTag.
  ///
  /// In ru, this message translates to:
  /// **'Сбросить тег'**
  String get resetTag;

  /// No description provided for @invalidTag.
  ///
  /// In ru, this message translates to:
  /// **'Проверьте параметры оформления'**
  String get invalidTag;

  /// No description provided for @tagPermissionRequired.
  ///
  /// In ru, this message translates to:
  /// **'Для настройки тега нужны Govor+ или соответствующее право.'**
  String get tagPermissionRequired;

  /// No description provided for @tagText.
  ///
  /// In ru, this message translates to:
  /// **'Текст'**
  String get tagText;

  /// No description provided for @tagTextColor.
  ///
  /// In ru, this message translates to:
  /// **'Цвет текста'**
  String get tagTextColor;

  /// No description provided for @tagTextGradient.
  ///
  /// In ru, this message translates to:
  /// **'Градиент текста — конечный цвет'**
  String get tagTextGradient;

  /// No description provided for @tagBackground.
  ///
  /// In ru, this message translates to:
  /// **'Цвет фона'**
  String get tagBackground;

  /// No description provided for @tagBackgroundGradient.
  ///
  /// In ru, this message translates to:
  /// **'Градиент фона — конечный цвет'**
  String get tagBackgroundGradient;

  /// No description provided for @tagAngle.
  ///
  /// In ru, this message translates to:
  /// **'Угол градиента (0–360°)'**
  String get tagAngle;

  /// No description provided for @tagBorder.
  ///
  /// In ru, this message translates to:
  /// **'Цвет обводки'**
  String get tagBorder;

  /// No description provided for @tagBorderGradient.
  ///
  /// In ru, this message translates to:
  /// **'Градиент обводки — конечный цвет'**
  String get tagBorderGradient;

  /// No description provided for @tagBorderWidth.
  ///
  /// In ru, this message translates to:
  /// **'Толщина обводки (0–4)'**
  String get tagBorderWidth;

  /// No description provided for @tagShadow.
  ///
  /// In ru, this message translates to:
  /// **'Цвет тени'**
  String get tagShadow;

  /// No description provided for @tagShadowBlur.
  ///
  /// In ru, this message translates to:
  /// **'Размытие тени (0–20)'**
  String get tagShadowBlur;

  /// No description provided for @tagShadowX.
  ///
  /// In ru, this message translates to:
  /// **'Смещение тени X (−10–10)'**
  String get tagShadowX;

  /// No description provided for @tagShadowY.
  ///
  /// In ru, this message translates to:
  /// **'Смещение тени Y (−10–10)'**
  String get tagShadowY;

  /// No description provided for @tagFont.
  ///
  /// In ru, this message translates to:
  /// **'Шрифт'**
  String get tagFont;

  /// No description provided for @tagFontWeight.
  ///
  /// In ru, this message translates to:
  /// **'Насыщенность шрифта (100–900, шаг 100)'**
  String get tagFontWeight;

  /// No description provided for @tagFontSize.
  ///
  /// In ru, this message translates to:
  /// **'Размер шрифта (10–24)'**
  String get tagFontSize;

  /// No description provided for @fontSize.
  ///
  /// In ru, this message translates to:
  /// **'Размер текста'**
  String get fontSize;

  /// No description provided for @fontSizePreview.
  ///
  /// In ru, this message translates to:
  /// **'Так будут выглядеть сообщения'**
  String get fontSizePreview;

  /// No description provided for @resetFontSize.
  ///
  /// In ru, this message translates to:
  /// **'Стандартный размер'**
  String get resetFontSize;

  /// No description provided for @fontSizeSaveFailed.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось сохранить размер текста. Повторите выбор.'**
  String get fontSizeSaveFailed;

  /// No description provided for @avatar.
  ///
  /// In ru, this message translates to:
  /// **'Аватарка'**
  String get avatar;

  /// No description provided for @viewAvatar.
  ///
  /// In ru, this message translates to:
  /// **'Посмотреть аватарку'**
  String get viewAvatar;

  /// No description provided for @downloadAvatar.
  ///
  /// In ru, this message translates to:
  /// **'Скачать аватарку'**
  String get downloadAvatar;

  /// No description provided for @avatarUnavailable.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось загрузить аватарку.'**
  String get avatarUnavailable;

  /// No description provided for @createInvitation.
  ///
  /// In ru, this message translates to:
  /// **'Создать приглашение'**
  String get createInvitation;

  /// No description provided for @invitationDays.
  ///
  /// In ru, this message translates to:
  /// **'Срок действия, дней'**
  String get invitationDays;

  /// No description provided for @invalidInvitationDays.
  ///
  /// In ru, this message translates to:
  /// **'Введите от 1 до 365 дней'**
  String get invalidInvitationDays;

  /// No description provided for @invitationLimit.
  ///
  /// In ru, this message translates to:
  /// **'Лимит вступлений'**
  String get invitationLimit;

  /// No description provided for @invitationUnlimitedHint.
  ///
  /// In ru, this message translates to:
  /// **'0 — без лимита, максимум 1 000 000'**
  String get invitationUnlimitedHint;

  /// No description provided for @invalidInvitationLimit.
  ///
  /// In ru, this message translates to:
  /// **'Введите число от 0 до 1 000 000'**
  String get invalidInvitationLimit;

  /// No description provided for @invitationDescription.
  ///
  /// In ru, this message translates to:
  /// **'Описание ссылки'**
  String get invitationDescription;

  /// No description provided for @couldNotCreateInvitation.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось создать ссылку. Проверьте соединение и права доступа.'**
  String get couldNotCreateInvitation;

  /// No description provided for @removeAvatar.
  ///
  /// In ru, this message translates to:
  /// **'Удалить аватарку'**
  String get removeAvatar;

  /// No description provided for @groupAvatarHint.
  ///
  /// In ru, this message translates to:
  /// **'PNG, JPEG или WebP · до 2 МиБ · до 2048 px'**
  String get groupAvatarHint;

  /// No description provided for @unlimitedInvitations.
  ///
  /// In ru, this message translates to:
  /// **'Без лимита'**
  String get unlimitedInvitations;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'ru'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'ru':
      return AppLocalizationsRu();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
