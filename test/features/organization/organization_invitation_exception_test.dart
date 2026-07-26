import 'package:flutter_test/flutter_test.dart';
import 'package:photo_compare/features/organization/organization.dart';

void main() {
  test('reads a structured invitation error returned by the edge function', () {
    final error = OrganizationInvitationException.fromResponse(
      details: const {
        'code': 'nickname_conflict',
        'error': 'invitation_nickname_conflict',
      },
      status: 400,
    );

    expect(error.code, 'nickname_conflict');
    expect(error.message, 'invitation_nickname_conflict');
    expect(error.status, 400);
  });

  test('infers a nickname conflict from a legacy function response', () {
    final error = OrganizationInvitationException.fromResponse(
      details: '''
        {"error":"PostgrestException(message: This nickname is already registered)"}
      ''',
      status: 400,
    );

    expect(error.code, 'nickname_conflict');
    expect(error.status, 400);
  });

  test('keeps an unknown invitation failure readable', () {
    final error = OrganizationInvitationException.fromResponse(
      details: 'Temporary server error',
      status: 500,
    );

    expect(error.code, 'invitation_failed');
    expect(error.message, 'Temporary server error');
  });
}
