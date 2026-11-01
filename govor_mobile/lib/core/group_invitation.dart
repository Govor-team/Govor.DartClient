import 'models.dart';

class GroupInvitationOptions {
  const GroupInvitationOptions({
    this.validForDays = 7,
    this.maxParticipants = 0,
    this.description = '',
  });
  final int validForDays, maxParticipants;
  final String description;

  Json toJson() {
    if (validForDays < 1 ||
        validForDays > 365 ||
        maxParticipants < 0 ||
        maxParticipants > 1000000 ||
        description.length > 500) {
      throw ArgumentError('Invalid group invitation options');
    }
    return {
      'validForDays': validForDays,
      'maxParticipants': maxParticipants,
      'description': description.trim(),
    };
  }
}
