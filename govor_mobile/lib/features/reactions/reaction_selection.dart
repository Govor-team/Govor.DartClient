import '../../core/models.dart';

/// Legacy reactions can have no catalog ID; compare their preserved code.
bool isOwnReaction(Json? mine, Json reaction) {
  if (mine == null) return false;
  final id = mine['reactionId'];
  return id != null
      ? id == reaction['reactionId']
      : mine['reactionCode'] != null &&
            mine['reactionCode'] == reaction['reactionCode'];
}
