enum ChatMessageKind {
  text,
  protocol,
  image,
  system,
}

class ChatMessage {
  final String id;
  final String threadId;
  final String senderId;
  final String senderNickname;
  final String senderDisplayName;
  final ChatMessageKind kind;
  final String text;
  final DateTime createdAt;
  final Map<String, dynamic> metadata;

  const ChatMessage({
    required this.id,
    required this.threadId,
    required this.senderId,
    required this.senderNickname,
    required this.senderDisplayName,
    required this.kind,
    required this.text,
    required this.createdAt,
    this.metadata = const {},
  });

  String get senderLabel {
    if (senderDisplayName.trim().isNotEmpty) return senderDisplayName.trim();
    if (senderNickname.trim().isNotEmpty) return senderNickname.trim();
    return 'Пользователь';
  }
}
