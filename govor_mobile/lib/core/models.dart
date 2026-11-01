import 'user_benefits.dart';

typedef Json = Map<String, dynamic>;

dynamic field(Json json, String name) {
  if (json.containsKey(name)) return json[name];
  final pascal = name[0].toUpperCase() + name.substring(1);
  return json[pascal];
}

Json object(Object? value) => Map<String, dynamic>.from(value as Map);
List<Json> objects(Object? value) => (value as List).map(object).toList();

class Person {
  const Person({
    required this.id,
    required this.name,
    this.description = '',
    this.online = false,
    this.iconId,
    this.benefits = const UserBenefits(),
  });
  factory Person.fromJson(Json j) => Person(
    id: j['id'] as String,
    name: j['username'] as String,
    description: j['description'] as String? ?? '',
    online: j['isOnline'] == true,
    iconId: j['iconId'] as String?,
    benefits: j['benefits'] is Map
        ? UserBenefits.fromJson(object(j['benefits']))
        : const UserBenefits(),
  );
  final String id, name, description;
  final bool online;
  final String? iconId;
  final UserBenefits benefits;
}

class Conversation {
  const Conversation({
    required this.id,
    required this.title,
    this.type = 0,
    this.subtitle = '',
    this.online = false,
    this.isChannel = false,
    this.canPost = true,
    this.unread = 0,
    this.iconId,
    this.role,
    this.canLeave = true,
    this.peerId,
  });
  final String id, title, subtitle;
  final int type, unread;
  final bool online, isChannel, canPost;
  final String? iconId;
  final int? role;
  final String? peerId;
  final bool canLeave;
  String get key => '$type/$id';
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.senderId,
    required this.conversationId,
    required this.type,
    required this.sentAt,
    required this.content,
    this.text,
    this.replyTo,
    this.forwardedFromMessageId,
    this.forwardedFromUserId,
    this.forwardedFromSentAt,
    this.edited = false,
    this.failure,
    this.pending = false,
    this.attachments = const [],
  });
  factory ChatMessage.fromJson(Json j) => ChatMessage(
    id: (j['id'] ?? j['messageId']) as String,
    senderId: j['senderId'] as String,
    conversationId: j['recipientId'] as String,
    type: j['recipientType'] as int,
    sentAt: DateTime.parse(j['sentAt'] as String).toUtc(),
    content: j['encryptedContent'] as String,
    replyTo: j['replyToMessageId'] as String?,
    forwardedFromMessageId: j['forwardedFromMessageId'] as String?,
    forwardedFromUserId: j['forwardedFromUserId'] as String?,
    forwardedFromSentAt: DateTime.tryParse(
      j['forwardedFromSentAt'] as String? ?? '',
    )?.toUtc(),
    edited: j['isEdited'] == true,
  );
  final String id, senderId, conversationId, content;
  final String? text, replyTo, failure;
  final String? forwardedFromMessageId, forwardedFromUserId;
  final DateTime? forwardedFromSentAt;
  final int type;
  final DateTime sentAt;
  final bool edited, pending;
  final List<Json> attachments;
  ChatMessage decoded(String value, [List<Json> files = const []]) =>
      ChatMessage(
        id: id,
        senderId: senderId,
        conversationId: conversationId,
        type: type,
        sentAt: sentAt,
        content: content,
        text: value,
        replyTo: replyTo,
        forwardedFromMessageId: forwardedFromMessageId,
        forwardedFromUserId: forwardedFromUserId,
        forwardedFromSentAt: forwardedFromSentAt,
        edited: edited,
        attachments: files,
      );
  ChatMessage rejected(String reason) => ChatMessage(
    id: id,
    senderId: senderId,
    conversationId: conversationId,
    type: type,
    sentAt: sentAt,
    content: content,
    replyTo: replyTo,
    forwardedFromMessageId: forwardedFromMessageId,
    forwardedFromUserId: forwardedFromUserId,
    forwardedFromSentAt: forwardedFromSentAt,
    edited: edited,
    failure: reason,
  );
}

List<ChatMessage> mergeMessages(
  Iterable<ChatMessage> previous,
  Iterable<ChatMessage> incoming,
) {
  final map = {for (final m in previous) m.id: m};
  for (final m in incoming) {
    map[m.id] = m;
  }
  return map.values.toList()..sort((a, b) {
    final date = a.sentAt.compareTo(b.sentAt);
    return date == 0 ? a.id.compareTo(b.id) : date;
  });
}
