import 'dart:convert';

class OrganizationInvitationException implements Exception {
  final String code;
  final String message;
  final int? status;

  const OrganizationInvitationException({
    required this.code,
    required this.message,
    this.status,
  });

  factory OrganizationInvitationException.fromResponse({
    required Object? details,
    int? status,
  }) {
    final payload = _payload(details);
    final rawCode = payload['code']?.toString().trim();
    final rawMessage =
        payload['error']?.toString().trim() ?? details?.toString().trim() ?? '';
    final code =
        rawCode == null || rawCode.isEmpty ? _inferCode(rawMessage) : rawCode;
    return OrganizationInvitationException(
      code: code,
      message: rawMessage.isEmpty ? 'Invitation request failed' : rawMessage,
      status: status,
    );
  }

  static Map<String, dynamic> _payload(Object? details) {
    if (details is Map) return Map<String, dynamic>.from(details);
    if (details is String) {
      try {
        final decoded = jsonDecode(details);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {
        // A non-JSON response is handled by the message-based fallback.
      }
    }
    return const {};
  }

  static String _inferCode(String message) {
    final lower = message.toLowerCase();
    if (lower.contains('nickname') &&
        (lower.contains('conflict') ||
            lower.contains('registered') ||
            lower.contains('duplicate'))) {
      return 'nickname_conflict';
    }
    if (lower.contains('email') &&
        (lower.contains('conflict') || lower.contains('pending'))) {
      return 'email_conflict';
    }
    if (lower.contains('already') && lower.contains('organization')) {
      return 'already_member';
    }
    if (lower.contains('seat') && lower.contains('limit')) {
      return 'seat_limit';
    }
    if (lower.contains('access') || lower.contains('denied')) {
      return 'access_denied';
    }
    return 'invitation_failed';
  }

  @override
  String toString() => message;
}
