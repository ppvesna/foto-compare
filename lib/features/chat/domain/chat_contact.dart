class ChatContact {
  final String userId;
  final String displayName;
  final String nickname;
  final String roleLabel;
  final bool canAddToTeam;

  const ChatContact({
    required this.userId,
    required this.displayName,
    required this.nickname,
    required this.roleLabel,
    required this.canAddToTeam,
  });

  String get label => displayName.trim().isNotEmpty
      ? displayName.trim()
      : nickname.trim().isNotEmpty
          ? nickname.trim()
          : 'Пользователь';

  String get subtitle =>
      nickname.trim().isEmpty ? roleLabel : '@${nickname.trim()} · $roleLabel';
}

class ChatTeamMember {
  final String userId;
  final String displayName;
  final String nickname;

  const ChatTeamMember({
    required this.userId,
    required this.displayName,
    required this.nickname,
  });

  String get label => displayName.trim().isNotEmpty
      ? displayName.trim()
      : nickname.trim().isNotEmpty
          ? nickname.trim()
          : 'Сотрудник';
}
